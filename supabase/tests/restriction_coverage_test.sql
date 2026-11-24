-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_restrictions_after.sql)
-- 068 활동 제한 빠뜨림 방지: 일반 사용자(로그인·비로그인)가 부를 수 있는 "쓰기 함수"(volatile, 트리거 아님)와
-- "쓰기 정책"(public·storage의 넣기·고치기·지우기)을 DB에서 전부 뽑아,
--   함수: 맨 앞(선언부 첫 줄 또는 begin 바로 뒤)에 assert_can_write()가 있거나, 허용 목록(restriction_exemptions)에 이유와 함께 있어야
--   정책: 식에 can_write()·사진 올리기 사전 검사가 있거나, 그 표·그 동작에 restriction_guard 트리거가 있거나, 허용 목록에 있어야
-- 통과한다. 새 쓰기 함수를 만들고 둘 다 하지 않으면 이 검사가 실패한다(아래 6번이 그것을 직접 확인한다).
\set ON_ERROR_STOP 1
\set QUIET 1

-- 쓰기 함수 판정
create function pg_temp.fn_coverage() returns table (sig text, state text) language sql stable as $$
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')',
         case
           when p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);' then 'checked'
           when p.prosrc like '%assert_can_write%' then 'NOT_FIRST'
           when exists (select 1 from public.restriction_exemptions e
                         where e.kind = 'function' and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')') then 'exempt'
           else 'MISSING'
         end
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
$$;
-- 쓰기 정책 판정
create function pg_temp.policy_coverage() returns table (name text, cmd text, state text) language sql stable as $$
  select pp.schemaname || '.' || pp.tablename || ': ' || pp.policyname, pp.cmd,
         case
           when exists (select 1 from public.restriction_exemptions e
                         where e.kind = 'policy' and e.name = pp.schemaname || '.' || pp.tablename || ': ' || pp.policyname) then 'exempt'
           when pp.cmd in ('INSERT', 'UPDATE')
            and coalesce(pp.qual, '') || ' ' || coalesce(pp.with_check, '') ~ '(can_write|media_upload_problem|profile_photo_upload_problem)\(\)' then 'checked'
           when pp.cmd in ('INSERT', 'UPDATE') and exists (
             select 1 from pg_trigger tg
              where tg.tgrelid = format('%I.%I', pp.schemaname, pp.tablename)::regclass and not tg.tgisinternal and tg.tgenabled <> 'D'
                and tg.tgfoid = 'public.restriction_guard()'::regprocedure
                and (tg.tgtype & 2) <> 0                                                    -- before
                and (tg.tgtype & case pp.cmd when 'INSERT' then 4 else 16 end) <> 0) then 'trigger'
           else 'MISSING'
         end
    from pg_policies pp
   where pp.cmd <> 'SELECT' and pp.schemaname in ('public', 'storage')
     and pp.roles && array['authenticated', 'anon', 'public']::name[]
$$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== 1. 함수 =====
select t.ok('쓰기 함수가 있다 (판정 대상 90개 넘게)', (select count(*) from pg_temp.fn_coverage()) > 90);
select coalesce(string_agg(sig || ' ' || state, ', ' order by sig), '') as bad_fn from pg_temp.fn_coverage() where state not in ('checked', 'exempt') \gset
select t.ok('모든 쓰기 함수: 맨 앞에 검사가 있거나 허용 목록에 있음 [' || :'bad_fn' || ']', :'bad_fn' = '');
select t.ok('검사가 든 함수 30개 (068의 29개 + 071 set_build_difficulty)', (select count(*) from pg_temp.fn_coverage() where state = 'checked') = 30);
select t.ok('검사와 허용 목록에 둘 다 있는 함수 없음', not exists (
  select 1 from pg_temp.fn_coverage() c join public.restriction_exemptions e on e.kind = 'function' and e.name = c.sig where c.state = 'checked'
  union all
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace join public.restriction_exemptions e
      on e.kind = 'function' and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')'
   where n.nspname = 'public' and p.prosrc like '%assert_can_write%'));
select coalesce(string_agg(e.name, ', '), '') as stale_fn from public.restriction_exemptions e
 where e.kind = 'function' and not exists (select 1 from pg_temp.fn_coverage() c where c.sig = e.name) \gset
select t.ok('허용 목록의 함수가 모두 실제로 있는 쓰기 함수 [' || :'stale_fn' || ']', :'stale_fn' = '');
select t.ok('막아야 하는 대표 함수는 검사 쪽 (허용 목록이 아님)', (select count(*) from pg_temp.fn_coverage()
  where state = 'checked' and sig in ('create_post(text, text, text[])', 'create_comment(bigint, text, text[], bigint)',
    'create_doc_comment(bigint, text, bigint)', 'create_build(bigint, jsonb)', 'create_matchup(text, text, jsonb)',
    'edit_build(bigint, integer, jsonb)', 'vote_build(bigint, smallint)', 'vote_post(bigint)', 'save_build(bigint)',
    'follow_influencer(uuid)', 'apply_influencer(text, text, text, text, text, text)', 'set_profile_photo(text)',
    'set_build_link(bigint, text)', 'set_profile_links(text[])', 'report_post(bigint, text, text)', 'report_wiki(bigint, bigint, text, text)')) = 16);

-- ===== 2. 정책 =====
select coalesce(string_agg(name || ' ' || cmd || ' ' || state, ', ' order by name), '') as bad_pol from pg_temp.policy_coverage() where state = 'MISSING' \gset
select t.ok('모든 쓰기 정책: 검사·트리거가 있거나 허용 목록에 있음 [' || :'bad_pol' || ']', :'bad_pol' = '');
select coalesce(string_agg(e.name, ', '), '') as stale_pol from public.restriction_exemptions e
 where e.kind = 'policy' and not exists (select 1 from pg_temp.policy_coverage() c where c.name = e.name) \gset
select t.ok('허용 목록의 정책이 모두 실제로 있음 [' || :'stale_pol' || ']', :'stale_pol' = '');
select t.ok('직접 넣기 정책 2개는 can_write(), 사진 올리기 2개는 사전 검사, 프로필 고치기는 트리거',
  (select count(*) from pg_temp.policy_coverage() where state = 'checked') = 4
  and (select state from pg_temp.policy_coverage() where name = 'public.profiles: profiles: 본인 수정') = 'trigger');
select t.ok('사진 올리기 사전 검사 2개가 제한 문장을 돌려준다', (select count(*) from pg_proc
  where proname in ('media_upload_problem', 'profile_photo_upload_problem') and prosrc like '%public.restriction_message(me)%') = 2);
select t.ok('로그인 사용자가 쓸 수 있는 public 표는 모두 RLS 켬', not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
     and (has_table_privilege('authenticated', c.oid, 'insert') or has_table_privilege('authenticated', c.oid, 'update')
          or has_table_privilege('authenticated', c.oid, 'delete') or has_table_privilege('anon', c.oid, 'insert'))));

-- ===== 3. 표 트리거 (둘째 겹) =====
select t.ok('restriction_guard 트리거 29개, 모두 before·켜짐', (select count(*) from pg_trigger
  where tgfoid = 'public.restriction_guard()'::regprocedure and not tgisinternal and (tgtype & 2) <> 0 and tgenabled = 'O') = 29);
select t.ok('새 줄을 막는 표 19개', (select count(distinct tgrelid) from pg_trigger
  where tgfoid = 'public.restriction_guard()'::regprocedure and (tgtype & 4) <> 0) = 19);
select t.ok('트리거는 지우기(DELETE)를 막지 않는다', not exists (select 1 from pg_trigger
  where tgfoid = 'public.restriction_guard()'::regprocedure and (tgtype & 8) <> 0));

-- ===== 4. 새 쓰기 함수를 만들고 검사를 빠뜨리면 실패하는지 (이 검사가 제 할 일을 하는지) =====
begin;
create function public.zz_forgot_check(p bigint) returns void language plpgsql security definer set search_path = '' as $$ begin perform 1; end $$;
grant execute on function public.zz_forgot_check(bigint) to authenticated;
select t.ok('검사도 허용 목록도 없는 새 함수 → MISSING으로 잡힘', (select state from pg_temp.fn_coverage() where sig = 'zz_forgot_check(bigint)') = 'MISSING');
create or replace function public.zz_forgot_check(p bigint) returns void language plpgsql security definer set search_path = '' as $$
declare
  x int := 1;
  _can_write constant boolean := public.assert_can_write();
begin perform 1; end $$;
select t.ok('검사가 맨 앞이 아니면 NOT_FIRST로 잡힘', (select state from pg_temp.fn_coverage() where sig = 'zz_forgot_check(bigint)') = 'NOT_FIRST');
insert into public.restriction_exemptions (kind, name, reason) values ('function', 'zz_forgot_check(bigint)', '검사');
create or replace function public.zz_forgot_check(p bigint) returns void language plpgsql security definer set search_path = '' as $$ begin perform 1; end $$;
select t.ok('허용 목록에 넣으면 exempt', (select state from pg_temp.fn_coverage() where sig = 'zz_forgot_check(bigint)') = 'exempt');
create policy "zz 검사 정책" on public.posts for insert to authenticated with check (true);
select t.ok('검사 없는 새 쓰기 정책도 트리거가 있는 표면 trigger, 없는 표면 MISSING',
  (select state from pg_temp.policy_coverage() where name = 'public.posts: zz 검사 정책') = 'trigger');
create policy "zz 검사 정책" on public.inquiries for update to authenticated using (true);
select t.ok('트리거 없는 표의 새 쓰기 정책 → MISSING', (select state from pg_temp.policy_coverage() where name = 'public.inquiries: zz 검사 정책') = 'MISSING');
rollback;
select t.ok('검사용으로 만든 것은 되돌림', to_regprocedure('public.zz_forgot_check(bigint)') is null);
