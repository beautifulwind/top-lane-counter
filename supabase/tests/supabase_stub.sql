-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- Supabase 흉내: auth 스키마, auth.uid(), anon/authenticated 역할
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
grant usage on schema public to anon, authenticated;
create schema auth;
grant usage on schema auth to anon, authenticated;
create table auth.users (id uuid primary key, email text, created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated;
-- 테스트 도우미: sql을 실행해서 기대한 오류가 나는지 확인
create schema t;
grant usage on schema t to anon, authenticated;
create function t.fails(label text, q text, expected text) returns void language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    if sqlerrm ilike '%' || expected || '%' then
      raise notice 'PASS  %', label;
      return;
    end if;
    raise exception 'FAIL  % — 다른 오류: %', label, sqlerrm;
  end;
  raise exception 'FAIL  % — 오류가 나야 하는데 성공함', label;
end $$;
create function t.ok(label text, cond boolean) returns void language plpgsql as $$
begin
  if cond then raise notice 'PASS  %', label; else raise exception 'FAIL  %', label; end if;
end $$;
grant execute on all functions in schema t to anon, authenticated;
