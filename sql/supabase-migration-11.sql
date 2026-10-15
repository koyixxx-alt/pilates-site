-- =========================================================
--  Pilates Studio — マイグレーション ⑪（お客様アプリの機能追加）
--  ・プロテインの購入時期（お客様アプリに表示）
--  ・目標（体重・体脂肪率）／次回までのセルフケア（宿題）
--  ・スタジオからのお知らせ
--  ・ご利用履歴（お支払いの記録）
--  Supabase の SQL Editor に貼り付けて「Run」してください。何度実行しても安全です。
-- =========================================================

-- ---------- 目標・セルフケア ----------
alter table public.customers add column if not exists goal_weight   numeric;  -- 目標体重（kg）
alter table public.customers add column if not exists goal_body_fat numeric;  -- 目標体脂肪率（%）
alter table public.sessions  add column if not exists homework      text;     -- 次回までのセルフケア（宿題）

-- ---------- スタジオからのお知らせ ----------
create table if not exists public.announcements (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text,
  published  boolean default true,   -- 公開する
  pinned     boolean default false,  -- 上に固定
  starts_on  date,                   -- 表示開始日（空なら今すぐ）
  ends_on    date,                   -- 表示終了日（空ならずっと）
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.announcements enable row level security;
drop policy if exists ann_read  on public.announcements;
create policy ann_read  on public.announcements for select
  using (is_owner() or (published and auth.uid() is not null));
drop policy if exists ann_write on public.announcements;
create policy ann_write on public.announcements for all using (is_owner()) with check (is_owner());

-- ---------- お客様アプリ：プロテインの最新の購入（自分の分だけ） ----------
create or replace function public.my_protein_status()
returns json language sql security definer set search_path = public stable as $$
  select row_to_json(x) from (
    select pr.purchase_date, pr.volume_g, pr.serving_g, pr.per_day, prod.name as product_name
    from public.proteins pr
    left join public.products prod on prod.id = pr.product_id
    left join public.payments pay  on pay.id  = pr.payment_id
    where pr.customer_id = public.my_customer_id()
      and (pr.payment_id is null or pay.voided_at is null)
    order by pr.purchase_date desc, pr.created_at desc
    limit 1
  ) x;
$$;

-- ---------- お客様アプリ：ご利用履歴（取り消した会計は出さない） ----------
create or replace function public.my_payments()
returns table(date date, amount numeric, items jsonb, category text, method text, coupons_used int, coupon_discount numeric)
language sql security definer set search_path = public stable as $$
  select p.date, p.amount, p.items::jsonb, p.category, p.method, coalesce(p.coupons_used, 0), coalesce(p.coupon_discount, 0)
  from public.payments p
  where p.customer_id = public.my_customer_id() and p.voided_at is null
  order by p.date desc, p.created_at desc
  limit 60;
$$;

notify pgrst, 'reload schema';

do $$ begin raise notice 'Migration 11 complete.'; end $$;
