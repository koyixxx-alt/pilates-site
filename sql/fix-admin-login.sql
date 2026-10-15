-- =========================================================
--  管理者（ID: admin）でログインできないときの修復
--  ・パスワードを最初のもの（jwxgZshvt7HW）に戻し、初回変更を必須にする
--  ・メール確認済みにする／ログインに必要な情報が欠けていれば補う
--  ・最後に状態を表示する（パスワードそのものは表示しない）
--  何度実行しても安全です。
-- =========================================================
set search_path = public, extensions, auth;

do $$
declare
  uid uuid;
  em  text := 'admin@noailles-studio.netlify.app';
begin
  select id into uid from auth.users where lower(email) = em;
  if uid is null then
    uid := public._create_login_user(em, 'jwxgZshvt7HW');
  else
    update auth.users set
      encrypted_password         = crypt('jwxgZshvt7HW', gen_salt('bf')),
      email_confirmed_at         = coalesce(email_confirmed_at, now()),
      confirmation_token         = coalesce(confirmation_token, ''),
      recovery_token             = coalesce(recovery_token, ''),
      email_change_token_new     = coalesce(email_change_token_new, ''),
      email_change               = coalesce(email_change, ''),
      email_change_token_current = coalesce(email_change_token_current, ''),
      phone_change               = coalesce(phone_change, ''),
      phone_change_token         = coalesce(phone_change_token, ''),
      reauthentication_token     = coalesce(reauthentication_token, ''),
      banned_until               = null,
      updated_at                 = now()
    where id = uid;
    if not exists (select 1 from auth.identities where user_id = uid and provider = 'email') then
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), uid, uid::text,
              jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true),
              'email', now(), now(), now());
    end if;
  end if;
  insert into public.super_admins (user_id, note, must_change_pw) values (uid, '開発者（ID: admin）', true)
  on conflict (user_id) do update set must_change_pw = true;
end $$;

-- 状態の確認（すべて true なら、ID「admin」と最初のパスワードでログインできます）
select
  u.email_confirmed_at is not null                                   as confirmed,
  u.encrypted_password = crypt('jwxgZshvt7HW', u.encrypted_password) as password_ok,
  exists(select 1 from auth.identities i where i.user_id = u.id)     as identity_ok,
  exists(select 1 from public.super_admins s where s.user_id = u.id) as is_admin
from auth.users u
where lower(u.email) = 'admin@noailles-studio.netlify.app';
