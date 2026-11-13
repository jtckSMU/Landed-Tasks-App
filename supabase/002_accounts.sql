-- Team Roles Board: logins managed from the board itself
-- Run once after setup.sql (SQL Editor -> New query -> paste -> Run).
-- Adds: first-time admin setup, "Add member" with a temporary password,
-- admin password resets, and a forced password change on first log-in.

alter table public.profiles add column if not exists must_change_password boolean not null default false;

create or replace function public.member_email(p_username text) returns text
language sql immutable as $$ select lower(p_username) || '@landed-tasks.app' $$;

-- Creates a login directly in Supabase Auth (email confirmed, no emails sent).
create or replace function public._create_login(p_username text, p_password text) returns uuid
language plpgsql security definer set search_path = public, extensions, auth as $$
declare uid uuid := gen_random_uuid(); em text := public.member_email(p_username);
begin
  if p_username !~ '^[a-z0-9._-]{2,30}$' then
    raise exception 'Usernames use 2-30 lowercase letters, numbers, dots, dashes or underscores.';
  end if;
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'Passwords need at least 8 characters.';
  end if;
  if exists (select 1 from auth.users where email = em) then
    raise exception 'The username % is already taken.', p_username;
  end if;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
    extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true),
    'email', now(), now(), now());
  return uid;
end $$;
revoke all on function public._create_login(text, text) from public, anon, authenticated;

-- First-time setup: only works while the project has no logins at all, and only for "jonathan".
create or replace function public.setup_needed() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select not exists (select 1 from auth.users)
$$;

create or replace function public.bootstrap_admin(p_password text) returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
declare uid uuid;
begin
  if exists (select 1 from auth.users) then
    raise exception 'Setup is already done. Log in instead.';
  end if;
  uid := public._create_login('jonathan', p_password);
  update public.profiles set role = 'admin', active = true, must_change_password = false, display_name = 'Jonathan'
  where id = uid;
  insert into public.audit_log (user_id, section, action, summary)
  values (uid, 'Team', 'Added', 'jonathan (first-time setup)');
end $$;

-- Admin: add a member with a temporary password; they must change it at first log-in.
create or replace function public.admin_create_member(p_username text, p_display_name text, p_password text) returns uuid
language plpgsql security definer set search_path = public, extensions, auth as $$
declare uid uuid;
begin
  if not public.is_admin() then raise exception 'Only admins can add members.'; end if;
  uid := public._create_login(lower(trim(p_username)), p_password);
  update public.profiles
  set active = true, must_change_password = true,
      display_name = coalesce(nullif(trim(p_display_name), ''), initcap(lower(trim(p_username))))
  where id = uid;
  return uid;
end $$;

-- Admin: give someone a new temporary password; they must change it at next log-in.
create or replace function public.admin_set_password(p_user uuid, p_password text) returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
declare uname text;
begin
  if not public.is_admin() then raise exception 'Only admins can reset passwords.'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'Passwords need at least 8 characters.'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now()
  where id = p_user;
  update public.profiles set must_change_password = true where id = p_user returning username into uname;
  insert into public.audit_log (user_id, section, action, summary)
  values (auth.uid(), 'Team', 'Password reset', coalesce(uname, 'unknown') || ' must choose a new password at next log-in');
end $$;

-- The member has chosen their own password.
create or replace function public.password_changed() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  update public.profiles set must_change_password = false where id = auth.uid();
  insert into public.audit_log (user_id, section, action, summary)
  values (auth.uid(), 'Logins', 'Password changed', 'Chose their own password');
end $$;

revoke all on function public.setup_needed(), public.bootstrap_admin(text),
  public.admin_create_member(text, text, text), public.admin_set_password(uuid, text),
  public.password_changed() from public;
grant execute on function public.setup_needed(), public.bootstrap_admin(text) to anon, authenticated;
grant execute on function public.admin_create_member(text, text, text), public.admin_set_password(uuid, text),
  public.password_changed() to authenticated;
