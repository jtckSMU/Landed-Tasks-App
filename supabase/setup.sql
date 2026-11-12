-- Team Roles Board: Supabase setup
-- Run once in Supabase: SQL Editor -> New query -> paste this whole file -> Run.
-- Create the team's logins (Authentication -> Users -> Add user) BEFORE running it,
-- so everyone gets a profile. Anyone added later gets one automatically.

create extension if not exists pgcrypto;

-- ---------- people ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null,
  display_name text not null,
  role text not null default 'member' check (role in ('admin','member')),
  -- New logins start switched off; an admin switches them on in the Team tab.
  active boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare u text := lower(split_part(new.email, '@', 1));
begin
  -- The owner's login (jonathan) is switched on as admin straight away; everyone else waits for approval.
  insert into public.profiles (id, username, display_name, role, active)
  values (new.id, u, initcap(u), case when u = 'jonathan' then 'admin' else 'member' end, u = 'jonathan')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Logins created before this script runs are the starting team, so they start switched on.
insert into public.profiles (id, username, display_name, active)
select id, lower(split_part(email, '@', 1)), initcap(split_part(email, '@', 1)), true
from auth.users
on conflict (id) do nothing;

-- The owner account is an admin (manages the Team tab).
update public.profiles set role = 'admin' where username = 'jonathan';

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active)
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'admin')
$$;

-- ---------- board data ----------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  owner text not null,
  due date not null,
  done boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.late (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  late_date date not null,
  reason text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  entry_date date not null,
  description text not null,
  type text not null check (type in ('in','out')),
  amount numeric(12,2) not null check (amount > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.roles (
  id text primary key,
  name text not null,
  sort int not null default 0,
  people text not null default '',
  backup text not null default '',
  items text[] not null default '{}'
);

create table if not exists public.late_policy (
  id int primary key default 1 check (id = 1),
  first text not null default 'Verbal warning',
  second text not null default '$50 fine',
  onwards text not null default ''
);

-- ---------- entry records (written only by the database itself) ----------
create table if not exists public.audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid references public.profiles(id) on delete set null,
  by_label text,
  section text not null,
  action text not null,
  summary text not null default '',
  changes jsonb not null default '[]'
);
create index if not exists audit_log_at on public.audit_log (at desc);

-- ---------- data carried over from the claude.ai board (runs before the audit triggers exist) ----------
insert into public.tasks (title, owner, due, done, created_at)
select * from (values
  ('Order Banner', 'YC', date '2026-11-03', true, to_timestamp(1793716529602/1000.0)),
  ('Liaise for telemarketer', 'Jonathan', date '2026-11-18', false, to_timestamp(1794504044100/1000.0)),
  ('Design banner – template / pricing', 'Jordon', date '2026-10-23', true, to_timestamp(1793700000000/1000.0)),
  ('Collect & Hang Banner', 'Jonathan', date '2026-11-16', false, to_timestamp(1793865810514/1000.0)),
  ('Arrange catchup session with 107H Highland Road Owner', 'YC', date '2026-11-16', false, to_timestamp(1793717056312/1000.0))
) v where not exists (select 1 from public.tasks);

insert into public.accounts (entry_date, description, type, amount, created_at)
select date '2026-11-03', 'Banner Printing', 'out', 80, to_timestamp(1793720986888/1000.0)
where not exists (select 1 from public.accounts);

insert into public.roles (id, name, sort, people, backup, items) values
  ('sales', 'Sales', 0, 'Jonathan', 'Rachael', array['Sales angle','How to sell','Where buyers come from']),
  ('marketing', 'Marketing', 1, 'Jordon', 'Rachael', array['Video','Photo','Social media','Design flyers / banners']),
  ('ops', 'Ops & admin', 2, 'YC', 'Rachael', array['Arrange Activities','Admin & Finance matters'])
on conflict (id) do nothing;

insert into public.late_policy (id, first, second, onwards)
values (1, 'Verbal warning', '$50 fine', '$100')
on conflict (id) do nothing;

insert into public.audit_log (at, by_label, section, action, summary, changes)
select * from (values
  (to_timestamp(1793700000000/1000.0), 'Old board', 'Import', 'Imported', 'Data carried over from the claude.ai board', '[]'::jsonb),
  (to_timestamp(1794503998988/1000.0), 'Jonathan (old board)', 'Task', 'Added', 'Liaise for telemarketer · Jonathan · due 2026-11-18', '[]'::jsonb),
  (to_timestamp(1794504006935/1000.0), 'Jonathan (old board)', 'Task', 'Edited', 'Collect & Hang Banner · Jonathan · due 2026-11-16', '[{"field":"Deadline","from":"2026-11-13","to":"2026-11-16"}]'::jsonb),
  (to_timestamp(1794504024800/1000.0), 'Jonathan (old board)', 'Task', 'Deleted', 'Liaise for telemarketer · Jonathan · due 2026-11-18', '[]'::jsonb),
  (to_timestamp(1794504044508/1000.0), 'Jonathan (old board)', 'Task', 'Added', 'Liaise for telemarketer · Jonathan · due 2026-11-18', '[]'::jsonb),
  (to_timestamp(1794505015773/1000.0), 'Jonathan (old board)', 'Task', 'Reopened', 'Arrange catchup session with 107H Highland Road Owner · YC · due 2026-11-05', '[]'::jsonb),
  (to_timestamp(1794505023890/1000.0), 'Jonathan (old board)', 'Task', 'Edited', 'Arrange catchup session with 107H Highland Road Owner · YC · due 2026-11-16', '[{"field":"Deadline","from":"2026-11-05","to":"2026-11-16"}]'::jsonb),
  (to_timestamp(1794506141689/1000.0), 'Jonathan (old board)', 'Logins', 'Logged in', 'Opened the old claude.ai board', '[]'::jsonb)
) v where not exists (select 1 from public.audit_log);

-- ---------- automatic entry records on every change ----------
create or replace function public.audit_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  o jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  act text := case tg_op when 'INSERT' then 'Added' when 'UPDATE' then 'Edited' else 'Deleted' end;
  sec text; summ text; labels jsonb; ch jsonb := '[]'; k text; v_from text; v_to text;
begin
  if tg_table_name = 'tasks' then
    sec := 'Task'; labels := '{"title":"Task","owner":"In charge","due":"Deadline","done":"Done"}';
    summ := concat_ws(' · ', r->>'title', r->>'owner', 'due ' || (r->>'due'));
  elsif tg_table_name = 'late' then
    sec := 'Late'; labels := '{"name":"Name","late_date":"Date","reason":"Reason"}';
    summ := concat_ws(' · ', r->>'name', r->>'late_date', nullif(r->>'reason', ''));
  elsif tg_table_name = 'accounts' then
    sec := 'Accounts'; labels := '{"entry_date":"Date","description":"Description","type":"Type","amount":"Amount"}';
    summ := concat_ws(' · ', r->>'description', upper(r->>'type') || ' S$' || (r->>'amount'), r->>'entry_date');
  elsif tg_table_name = 'roles' then
    sec := 'Roles'; labels := '{"people":"Person in charge","backup":"Back-up","items":"Responsibilities"}';
    summ := r->>'name';
  elsif tg_table_name = 'late_policy' then
    sec := 'Late rule'; labels := '{"first":"1st time","second":"2nd time","onwards":"3rd time onwards"}';
    summ := 'Consequences';
  elsif tg_table_name = 'profiles' then
    sec := 'Team'; labels := '{"display_name":"Name","role":"Role","active":"Can log in"}';
    summ := r->>'username';
  end if;

  if tg_op = 'UPDATE' then
    for k in select jsonb_object_keys(labels) loop
      if (o->k) is distinct from (r->k) then
        v_from := case when jsonb_typeof(o->k) = 'array' then (select string_agg(x, '; ') from jsonb_array_elements_text(o->k) x) else o->>k end;
        v_to   := case when jsonb_typeof(r->k) = 'array' then (select string_agg(x, '; ') from jsonb_array_elements_text(r->k) x) else r->>k end;
        ch := ch || jsonb_build_array(jsonb_build_object('field', labels->>k, 'from', coalesce(v_from, ''), 'to', coalesce(v_to, '')));
      end if;
    end loop;
    if ch = '[]'::jsonb then return null; end if;
    if tg_table_name = 'tasks' and jsonb_array_length(ch) = 1 and ch->0->>'field' = 'Done' then
      act := case when (r->>'done')::boolean then 'Completed' else 'Reopened' end;
      ch := '[]';
    end if;
  end if;

  insert into public.audit_log (user_id, section, action, summary, changes)
  values (auth.uid(), sec, act, coalesce(summ, ''), ch);
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['tasks','late','accounts','roles','late_policy','profiles'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update or delete on public.%1$s for each row execute function public.audit_change()', t);
  end loop;
end $$;

-- Logins, log-outs, password changes and blocked log-ins. The server stamps the time and the person.
create or replace function public.log_session_event(p_action text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); act text := p_action;
begin
  if uid is null or p_action not in ('Logged in','Logged out','Password changed') then return; end if;
  if not public.is_member() then act := 'Blocked'; end if;
  if act in ('Logged in','Blocked') and exists (
    select 1 from public.audit_log
    where user_id = uid and section = 'Logins' and action = act and at > now() - interval '30 minutes'
  ) then return; end if;
  insert into public.audit_log (user_id, section, action, summary)
  values (uid, 'Logins', act, case act
    when 'Logged in' then 'Opened the board'
    when 'Logged out' then 'Logged out'
    when 'Password changed' then 'Changed their password'
    else 'Tried to log in with a disabled account' end);
end $$;

-- ---------- who can do what ----------
alter table public.profiles    enable row level security;
alter table public.tasks       enable row level security;
alter table public.late        enable row level security;
alter table public.accounts    enable row level security;
alter table public.roles       enable row level security;
alter table public.late_policy enable row level security;
alter table public.audit_log   enable row level security;

drop policy if exists "members read profiles" on public.profiles;
create policy "members read profiles" on public.profiles for select to authenticated
  using (public.is_member() or id = auth.uid());
drop policy if exists "admins edit profiles" on public.profiles;
create policy "admins edit profiles" on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

do $$
declare t text;
begin
  foreach t in array array['tasks','late','accounts'] loop
    execute format('drop policy if exists "members use %1$s" on public.%1$s', t);
    execute format('create policy "members use %1$s" on public.%1$s for all to authenticated using (public.is_member()) with check (public.is_member())', t);
  end loop;
  foreach t in array array['roles','late_policy'] loop
    execute format('drop policy if exists "members read %1$s" on public.%1$s', t);
    execute format('create policy "members read %1$s" on public.%1$s for select to authenticated using (public.is_member())', t);
    execute format('drop policy if exists "members edit %1$s" on public.%1$s', t);
    execute format('create policy "members edit %1$s" on public.%1$s for update to authenticated using (public.is_member()) with check (public.is_member())', t);
  end loop;
end $$;

-- Entry records: members can read them; nobody can add, change or delete them from the app.
drop policy if exists "members read records" on public.audit_log;
create policy "members read records" on public.audit_log for select to authenticated
  using (public.is_member());

-- Explicit table access for logged-in users (the security rules above still decide which rows).
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.tasks, public.late, public.accounts to authenticated;
grant select, update on public.roles, public.late_policy, public.profiles to authenticated;
revoke all on public.tasks, public.late, public.accounts, public.roles, public.late_policy, public.profiles from anon;

revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;
revoke execute on function public.log_session_event(text) from anon, public;
grant execute on function public.log_session_event(text) to authenticated;

-- ---------- live updates ----------
do $$
declare t text;
begin
  foreach t in array array['tasks','late','accounts','roles','late_policy','audit_log','profiles'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
