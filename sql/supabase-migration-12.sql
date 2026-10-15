-- =========================================================
--  Pilates Studio — マイグレーション ⑫
--  ・回数券（5回で1セット）／加圧と痩身の共用・差額／期限と変更履歴
--  ・紹介割（紹介した人・された人の両方）／誕生日割／商品スタンプを美容にも拡大
--  ・予約とレッスン記録の複数プラン／予約の変更（どこからどこへ）
--  ・お客様アプリからの予約受付をやめる
--  Supabase の SQL Editor に貼り付けて「Run」してください。何度実行しても安全です。
-- =========================================================

-- ---------- 複数プラン・予約の変更 ----------
alter table public.reservations add column if not exists categories text[];
alter table public.reservations add column if not exists moved_to   uuid references public.reservations(id) on delete set null;
alter table public.reservations add column if not exists moved_from uuid references public.reservations(id) on delete set null;
alter table public.sessions     add column if not exists categories text[];
update public.reservations set categories = array[category] where categories is null and category is not null;
update public.sessions     set categories = array[category] where categories is null and category is not null;

-- ---------- 紹介者・割引の内訳 ----------
alter table public.customers add column if not exists referred_by uuid references public.customers(id) on delete set null;
alter table public.payments  add column if not exists discounts jsonb;   -- [{kind:'referral'|'birthday', amount, coupon_id, year}]

-- ---------- 料金・割引の設定 ----------
alter table public.studio_settings add column if not exists slimming_price  int default 8000;  -- 痩身の1回料金（全員一律）
alter table public.studio_settings add column if not exists set_size        int default 5;     -- 回数券の回数
alter table public.studio_settings add column if not exists referral_amount int default 1000;  -- 紹介割
alter table public.studio_settings add column if not exists birthday_amount int default 1500;  -- 誕生日割
-- お客様アプリからの予約受付はやめる
update public.studio_settings set booking_enabled = false where id = 1;

-- ---------- 回数券 ----------
create table if not exists public.ticket_sets (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references public.customers(id) on delete cascade,
  plan         text not null,              -- training（加圧）| slimming（痩身）
  total        int  not null default 5,    -- 回数
  unit_price   numeric,                    -- 1回あたりの料金（購入時）
  price        numeric,                    -- お支払い額
  payment_id   uuid references public.payments(id) on delete set null,
  purchased_on date not null default current_date,
  expires_on   date,                       -- 期限（顧客情報から入力）
  note         text,
  created_at   timestamptz default now()
);
create index if not exists idx_ticket_sets_customer on public.ticket_sets(customer_id);

create table if not exists public.ticket_uses (
  id             uuid primary key default gen_random_uuid(),
  set_id         uuid not null references public.ticket_sets(id) on delete cascade,
  customer_id    uuid references public.customers(id) on delete cascade,
  used_on        date not null default current_date,
  plan           text,                     -- 実際に受けたプラン（加圧の券で痩身なら slimming）
  surcharge      numeric default 0,        -- 差額
  payment_id     uuid references public.payments(id) on delete set null,
  reservation_id uuid references public.reservations(id) on delete set null,
  created_at     timestamptz default now()
);
create index if not exists idx_ticket_uses_set on public.ticket_uses(set_id);

create table if not exists public.ticket_expiry_log (
  id         uuid primary key default gen_random_uuid(),
  set_id     uuid not null references public.ticket_sets(id) on delete cascade,
  old_date   date,
  new_date   date,
  note       text,
  changed_at timestamptz default now()
);

-- ---------- 割引券（紹介割など） ----------
create table if not exists public.coupons (
  id              uuid primary key default gen_random_uuid(),
  customer_id     uuid not null references public.customers(id) on delete cascade,
  kind            text not null,            -- referral
  amount          int  not null,
  issued_on       date not null default current_date,
  expires_on      date,
  used_payment_id uuid references public.payments(id) on delete set null,
  used_on         date,
  note            text,
  created_at      timestamptz default now()
);
create index if not exists idx_coupons_customer on public.coupons(customer_id);

alter table public.ticket_sets       enable row level security;
alter table public.ticket_uses       enable row level security;
alter table public.ticket_expiry_log enable row level security;
alter table public.coupons           enable row level security;
drop policy if exists ts_all on public.ticket_sets;       create policy ts_all on public.ticket_sets       for all using (is_owner()) with check (is_owner());
drop policy if exists tu_all on public.ticket_uses;       create policy tu_all on public.ticket_uses       for all using (is_owner()) with check (is_owner());
drop policy if exists te_all on public.ticket_expiry_log; create policy te_all on public.ticket_expiry_log for all using (is_owner()) with check (is_owner());
drop policy if exists cp_all on public.coupons;           create policy cp_all on public.coupons           for all using (is_owner()) with check (is_owner());

-- ---------- お客様アプリ用 ----------
-- 自分の予約（変更済み・キャンセルは除く）
create or replace function public.my_reservations()
returns table(id uuid, date date, "time" text, category text, duration int, status text)
language sql security definer set search_path = public stable as $$
  select r.id, r.date, r.time, coalesce(r.category, r.categories[1]), r.duration, coalesce(r.status, 'booked')
  from public.reservations r
  where r.customer_id = public.my_customer_id()
    and r.date >= (now() at time zone 'Asia/Tokyo')::date
    and coalesce(r.status, 'booked') not in ('cancelled', 'moved')
  order by r.date, r.time
  limit 20;
$$;

-- 商品スタンプ（プロテイン＋美容の合計個数）
create or replace function public.my_coupon_status()
returns json language sql security definer set search_path = public stable as $$
  with pays as (
    select p.* from public.payments p
    where p.customer_id = public.my_customer_id() and p.voided_at is null
  ),
  q as (
    select coalesce(sum(coalesce(nullif(i->>'qty','')::numeric, 1)), 0) as n
    from pays,
         jsonb_array_elements(case when jsonb_typeof(pays.items) = 'array' then pays.items else '[]'::jsonb end) i
    where coalesce(i->>'kind', '') not in ('training', 'slimming', 'bust', '')
  ),
  legacy as (select count(*) as n from pays where subtotal is null and category = 'protein'),
  u as (select coalesce(sum(coupons_used), 0) as n from pays),
  s as (select coupon_every, coupon_amount from public.studio_settings where id = 1)
  select json_build_object(
    'qty',    (select n from q) + (select n from legacy),
    'used',   (select n from u),
    'every',  coalesce((select coupon_every  from s), 3),
    'amount', coalesce((select coupon_amount from s), 1000)
  );
$$;

-- 回数券（残り回数・期限）
create or replace function public.my_tickets()
returns table(plan text, total int, used int, expires_on date, purchased_on date)
language sql security definer set search_path = public stable as $$
  select t.plan, t.total,
         (select count(*)::int from public.ticket_uses u
            left join public.payments up on up.id = u.payment_id
           where u.set_id = t.id and (u.payment_id is null or up.voided_at is null)),
         t.expires_on, t.purchased_on
  from public.ticket_sets t
  left join public.payments p on p.id = t.payment_id
  where t.customer_id = public.my_customer_id()
    and (t.payment_id is null or p.voided_at is null)
  order by t.purchased_on desc;
$$;

-- 使える割引券（紹介割・誕生日割）
create or replace function public.my_coupons()
returns json language sql security definer set search_path = public stable as $$
  with me as (select * from public.customers where id = public.my_customer_id()),
  s as (select coalesce(birthday_amount, 1500) as bday from public.studio_settings where id = 1),
  today as (select (now() at time zone 'Asia/Tokyo')::date as d)
  select json_build_object(
    'referral', (select coalesce(json_agg(json_build_object('amount', c.amount, 'note', c.note)), '[]'::json)
                 from public.coupons c where c.customer_id = (select id from me)
                   and (c.used_payment_id is null or exists (select 1 from public.payments up where up.id = c.used_payment_id and up.voided_at is not null))
                   and (c.expires_on is null or c.expires_on >= (select d from today))),
    'birthday', (select case when extract(month from me.birthday) = extract(month from (select d from today))
                   and not exists (
                     select 1 from public.payments p, jsonb_array_elements(coalesce(p.discounts, '[]'::jsonb)) x
                     where p.customer_id = me.id and p.voided_at is null and x->>'kind' = 'birthday'
                       and extract(year from p.date) = extract(year from (select d from today)))
                 then (select bday from s) else 0 end from me)
  );
$$;

notify pgrst, 'reload schema';

do $$ begin raise notice 'Migration 12 complete.'; end $$;
