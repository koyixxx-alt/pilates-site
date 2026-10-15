-- =========================================================
--  Pilates Studio — マイグレーション ⑩（IDとパスワードでのログイン）
--  ・お店のアカウントを「ID＋パスワード」で作れるようにする
--    （まだお店のアカウントが無いときだけ、お店側アプリの最初の画面から作成できる）
--  ・開発者の管理者アカウント（ID: admin）を作成する（初回ログインでパスワード変更）
--  Supabase の SQL Editor に貼り付けて「Run」してください。何度実行しても安全です。
--
--  ※ ID は、裏側では「ID@noailles-studio.netlify.app」というログイン用の内部アドレスになります。
--    （メールは送られません。アプリの画面では ID だけが表示されます）
-- =========================================================

-- ---------- ログイン用アカウントを作る（内部用。アプリからは直接呼べない） ----------
create or replace function public._create_login_user(p_email text, p_password text)
returns uuid language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  uid uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', lower(p_email),
    crypt(p_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
    '', '', '', '', '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
          jsonb_build_object('sub', uid::text, 'email', lower(p_email), 'email_verified', true),
          'email', now(), now(), now());
  return uid;
end $$;
revoke all on function public._create_login_user(text, text) from public, anon, authenticated;

-- ---------- まだお店のアカウントが無いか（最初の画面を出すかどうか） ----------
create or replace function public.owner_setup_needed()
returns boolean language sql security definer set search_path = public stable as $$
  select not exists(select 1 from public.profiles where role = 'owner');
$$;
grant execute on function public.owner_setup_needed() to anon, authenticated;

-- ---------- お店のアカウントを作る（ID＋パスワード） ----------
--  ・お店のアカウントがまだ1つも無いとき（はじめての設定） … 誰でも1回だけ作れる
--  ・それ以外 … 開発者（管理者）だけが運営管理画面から作れる
create or replace function public.create_owner_account(p_login_id text, p_password text)
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_id    text := lower(trim(coalesce(p_login_id, '')));
  v_email text;
  uid     uuid;
begin
  perform pg_advisory_xact_lock(hashtext('pilates-create-owner'));
  if exists(select 1 from public.profiles where role = 'owner') and not public.is_super_admin() then
    raise exception 'すでにお店のアカウントがあります。ログインしてください';
  end if;
  if v_id !~ '^[a-z0-9][a-z0-9._-]{2,29}$' then
    raise exception 'IDは半角の英字・数字で3〜30文字にしてください（記号は . _ - のみ）';
  end if;
  if v_id in ('admin', 'adomin', 'root', 'support') then raise exception 'このIDは使えません'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'パスワードは8文字以上にしてください'; end if;
  v_email := v_id || '@noailles-studio.netlify.app';
  if exists(select 1 from auth.users where lower(email) = v_email) then raise exception 'このIDはすでに使われています'; end if;

  uid := public._create_login_user(v_email, p_password);
  insert into public.profiles (id, role, full_name) values (uid, 'owner', v_id)
  on conflict (id) do update set role = 'owner';
end $$;
grant execute on function public.create_owner_account(text, text) to anon, authenticated;

-- ---------- 開発者の管理者アカウント（ID: admin） ----------
alter table public.super_admins add column if not exists must_change_pw boolean default false;
create or replace function public.admin_mark_pw_changed()
returns void language sql security definer set search_path = public as $$
  update public.super_admins set must_change_pw = false where user_id = auth.uid();
$$;

do $$
declare
  uid uuid;
begin
  select id into uid from auth.users where lower(email) = 'admin@noailles-studio.netlify.app';
  if uid is null then
    -- 初回のパスワード（ログイン後すぐ変更が必要）
    uid := public._create_login_user('admin@noailles-studio.netlify.app', 'jwxgZshvt7HW');
    insert into public.super_admins (user_id, note, must_change_pw) values (uid, '開発者（ID: admin）', true)
    on conflict (user_id) do update set must_change_pw = true;
  else
    insert into public.super_admins (user_id, note, must_change_pw) values (uid, '開発者（ID: admin）', true)
    on conflict (user_id) do nothing;
  end if;
end $$;

notify pgrst, 'reload schema';

-- 確認：admin_ready が true なら管理者アカウントの準備完了
select exists(
  select 1 from public.super_admins s join auth.users u on u.id = s.user_id
  where lower(u.email) = 'admin@noailles-studio.netlify.app'
) as admin_ready;
