-- Emulates the parts of Supabase that the migrations rely on, so they run on a plain Postgres.
-- Runs once, as the bootstrap superuser, before any migration.
--
--   * the API roles (anon, authenticated, service_role) and the auth admin role
--   * auth.users and auth.uid(), which reads the caller from request.jwt.claim.sub
--   * Supabase's default privileges: new objects in public start open to the API roles,
--     which is exactly what the revoke statements in the migrations have to undo
\set ON_ERROR_STOP 1

create role postgres login createrole bypassrls;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role supabase_auth_admin nologin;

grant anon, authenticated, service_role to postgres;
grant supabase_auth_admin to postgres with admin option;
grant all on database cifro to postgres;
grant all on schema public to postgres;
grant usage on schema public to anon, authenticated, service_role;

create schema auth;
grant usage on schema auth to postgres, anon, authenticated, service_role, supabase_auth_admin;
create table auth.users (id uuid primary key, raw_user_meta_data jsonb not null default '{}');
grant all on auth.users to postgres, supabase_auth_admin;

create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to public;

alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on functions to anon, authenticated, service_role;
