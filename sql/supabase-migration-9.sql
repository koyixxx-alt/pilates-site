-- =========================================================
--  Pilates Studio — マイグレーション ⑨
--  ・顧客：姓／名・フリガナ（セイ／メイ）・郵便番号
--  ・お客様アプリからの予約（空き確認・予約・キャンセル）と、お店への通知
--  ・予約受付の設定（営業時間・定休日・1回の時間・受付期限）
--  Supabase の SQL Editor に貼り付けて「Run」してください。何度実行しても安全です。
-- =========================================================

-- ---------- 顧客：姓・名・フリガナ・郵便番号 ----------
alter table public.customers add column if not exists last_name   text;
alter table public.customers add column if not exists first_name  text;
alter table public.customers add column if not exists last_kana   text;
alter table public.customers add column if not exists first_kana  text;
alter table public.customers add column if not exists postal_code text;

-- 今までの「お名前」「ふりがな」を、空白の位置で姓と名に分けて入れておく
update public.customers
   set last_name  = split_part(regexp_replace(trim(name), '\s+', ' ', 'g'), ' ', 1),
       first_name = nullif(trim(substr(regexp_replace(trim(name), '\s+', ' ', 'g'),
                      length(split_part(regexp_replace(trim(name), '\s+', ' ', 'g'), ' ', 1)) + 1)), '')
 where last_name is null and name is not null;
update public.customers
   set last_kana  = split_part(regexp_replace(trim(kana), '\s+', ' ', 'g'), ' ', 1),
       first_kana = nullif(trim(substr(regexp_replace(trim(kana), '\s+', ' ', 'g'),
                      length(split_part(regexp_replace(trim(kana), '\s+', ' ', 'g'), ' ', 1)) + 1)), '')
 where last_kana is null and kana is not null and kana <> '';

-- ---------- 予約：どこから入った予約か・お店が確認したか ----------
alter table public.reservations add column if not exists source       text default 'owner';  -- owner | customer
alter table public.reservations add column if not exists seen_at      timestamptz;           -- お店が通知を確認した日時
alter table public.reservations add column if not exists cancelled_at timestamptz;
alter table public.reservations add column if not exists cancelled_by text;                  -- owner | customer

-- ---------- 予約受付の設定 ----------
alter table public.studio_settings add column if not exists booking_enabled  boolean default false; -- アプリからの予約を受け付ける
alter table public.studio_settings add column if not exists open_time        text    default '10:00';
alter table public.studio_settings add column if not exists close_time       text    default '21:00';
alter table public.studio_settings add column if not exists lesson_minutes   int     default 50;
alter table public.studio_settings add column if not exists slot_step        int     default 30;    -- 何分刻みで選べるか
alter table public.studio_settings add column if not exists closed_days      int[]   default '{}';  -- 定休日（0=日〜6=土）
alter table public.studio_settings add column if not exists book_days_ahead  int     default 30;    -- 何日先まで予約できるか
alter table public.studio_settings add column if not exists book_min_hours   int     default 3;     -- 何時間前まで予約できるか
alter table public.studio_settings add column if not exists cancel_min_hours int     default 24;    -- 何時間前までキャンセルできるか

-- ---------- お客様アプリ：自分の予約（キャンセル用にIDも返す） ----------
drop function if exists public.my_reservations();
create function public.my_reservations()
returns table(id uuid, date date, "time" text, category text, duration int, status text)
language sql security definer set search_path = public stable as $$
  select r.id, r.date, r.time, r.category, r.duration, coalesce(r.status, 'booked')
  from public.reservations r
  where r.customer_id = public.my_customer_id()
    and r.date >= (now() at time zone 'Asia/Tokyo')::date
    and coalesce(r.status, 'booked') <> 'cancelled'
  order by r.date, r.time
  limit 20;
$$;

-- ---------- お客様アプリ：空き確認（埋まっている時間だけ。誰の予約かは返さない） ----------
create or replace function public.busy_slots(d1 date, d2 date)
returns table(date date, "time" text, duration int)
language sql security definer set search_path = public stable as $$
  select r.date, r.time, coalesce(r.duration, 50)
  from public.reservations r
  where public.my_customer_id() is not null
    and r.date between d1 and least(d2, d1 + 62)
    and coalesce(r.status, 'booked') <> 'cancelled'
    and r.time ~ '^\d{1,2}:\d{2}$';
$$;

-- ---------- お客様アプリ：予約する（重なりはここで必ずチェック） ----------
create or replace function public.book_reservation(p_date date, p_time text, p_category text, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  cid    uuid := public.my_customer_id();
  c      public.customers%rowtype;
  s      public.studio_settings%rowtype;
  dur    int;
  st     timestamp;
  en     timestamp;
  nowj   timestamp := (now() at time zone 'Asia/Tokyo');
  new_id uuid;
begin
  if cid is null then raise exception 'お客様情報が見つかりません'; end if;
  select * into c from public.customers where id = cid;
  if c.withdrawn_at is not null then raise exception '退会済みのため予約できません'; end if;
  select * into s from public.studio_settings where id = 1;
  if not coalesce(s.booking_enabled, false) then raise exception '現在、アプリからのご予約は受け付けていません'; end if;
  if p_time !~ '^\d{2}:\d{2}$' then raise exception '時刻が正しくありません'; end if;

  dur := coalesce(s.lesson_minutes, 50);
  st  := p_date + p_time::time;
  en  := st + make_interval(mins => dur);
  if st < nowj + make_interval(hours => coalesce(s.book_min_hours, 3)) then raise exception 'この時間はもう予約できません'; end if;
  if p_date > nowj::date + coalesce(s.book_days_ahead, 30) then raise exception 'まだ予約できない日付です'; end if;
  if extract(dow from p_date)::int = any(coalesce(s.closed_days, '{}')) then raise exception '定休日です'; end if;
  if p_time::time < coalesce(s.open_time, '10:00')::time
     or en::date <> p_date or en::time > coalesce(s.close_time, '21:00')::time then
    raise exception '営業時間外です';
  end if;

  -- 同じ日の予約を同時に取られないよう、日付ごとに順番待ちにする
  perform pg_advisory_xact_lock(hashtext('pilates-book-' || p_date::text));
  if exists(
    select 1 from public.reservations r
    where r.date = p_date and coalesce(r.status, 'booked') <> 'cancelled' and r.time ~ '^\d{1,2}:\d{2}$'
      and (p_date + r.time::time) < en
      and (p_date + r.time::time + make_interval(mins => coalesce(r.duration, 50))) > st
  ) then
    raise exception 'この時間はすでに埋まっています。別の時間をお選びください';
  end if;

  if p_category not in ('training', 'slimming', 'bust') then p_category := null; end if;
  insert into public.reservations (customer_id, date, time, duration, category, note, status, source)
  values (cid, p_date, p_time, dur, p_category, nullif(trim(coalesce(p_note, '')), ''), 'booked', 'customer')
  returning id into new_id;
  return new_id;
end $$;

-- ---------- お客様アプリ：キャンセル（期限まで） ----------
create or replace function public.cancel_my_reservation(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r    public.reservations%rowtype;
  s    public.studio_settings%rowtype;
  nowj timestamp := (now() at time zone 'Asia/Tokyo');
begin
  select * into r from public.reservations where id = p_id and customer_id = public.my_customer_id();
  if not found then raise exception '予約が見つかりません'; end if;
  select * into s from public.studio_settings where id = 1;
  if (r.date + coalesce(nullif(r.time, ''), '00:00')::time) < nowj + make_interval(hours => coalesce(s.cancel_min_hours, 24)) then
    raise exception 'キャンセルの受付期限を過ぎています。お店にご連絡ください';
  end if;
  update public.reservations
     set status = 'cancelled', cancelled_at = now(), cancelled_by = 'customer', seen_at = null
   where id = p_id;
end $$;

-- ---------- 予約が入ったら、開いているお店側アプリにすぐ知らせる（リアルタイム） ----------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reservations') then
    alter publication supabase_realtime add table public.reservations;
  end if;
end $$;

notify pgrst, 'reload schema';

do $$ begin raise notice 'Migration 9 complete.'; end $$;
