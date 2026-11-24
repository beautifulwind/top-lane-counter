-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_device_push_tokens_after.sql)
-- 072 앱 푸시 기기 토큰: 표 모양·제약·RLS·권한(앱 직접 접근 불가, service_role 읽기·지우기만), 함수 모양·권한(로그인만),
--   본인 등록·갱신(중복 줄 없음, 시각·앱 버전 갱신), 다른 계정이 같은 토큰을 등록하면 소유자 이전, 남의 토큰은 해제 불가·없는 토큰은 false,
--   platform·token·app_version 검증(오류 문장·상세에 토큰 없음), 한 사람 10대(가장 오래 확인 안 된 것부터 지움, 방금 등록한 기기는 남김),
--   비로그인 거부, 비회원(게스트) 가능, 068 활동 제한 중에도 등록·해제 가능(허용 목록), 사용자 삭제·탈퇴(delete_my_account) 때 함께 삭제,
--   알림·웹 푸시 호출·push_subscriptions·push_targets에 영향 없음
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-00000000000a'
\set A  '00000000-0000-0000-0000-0000000000e1'
\set B  '00000000-0000-0000-0000-0000000000e2'
\set C  '00000000-0000-0000-0000-0000000000e3'
\set R  '00000000-0000-0000-0000-0000000000e4'
\set G  '00000000-0000-0000-0000-0000000000e5'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'A', 'a@x.com'), (:'B', 'b@x.com'), (:'C', 'c@x.com'), (:'R', 'r@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '에이' where id = :'A';
update public.profiles set nickname = '비이' where id = :'B';
update public.profiles set nickname = '씨이' where id = :'C';
update public.profiles set nickname = '제한맨' where id = :'R';
-- 64자 16진수 토큰 (APNs 모양). n이 다르면 다른 토큰
create function pg_temp.tk(n int) returns text language sql immutable as $$ select md5('tok' || n) || md5('ken' || n) $$;
-- 토큰 줄 보기 (테스트용, 소유자·종류·버전) - 슈퍼유저 권한으로
create function pg_temp.owner(p_platform text, p_token text) returns uuid language sql volatile security definer as $$
  select user_id from public.device_push_tokens where platform = p_platform and token = p_token $$;
create function pg_temp.cnt(p uuid) returns integer language sql volatile security definer as $$
  select count(*)::int from public.device_push_tokens where user_id = p $$;
-- 오류 문장 + 상세 + 힌트 (토큰이 새지 않는지 보려고)
create function pg_temp.err(q text) returns text language plpgsql as $$
declare m text; d text; h text;
begin
  execute q;
  return null;
exception when others then
  get stacked diagnostics m = message_text, d = pg_exception_detail, h = pg_exception_hint;
  return coalesce(m, '') || ' #' || coalesce(d, '') || ' #' || coalesce(h, '');
end $$;
-- 바뀌면 안 되는 것: 웹 푸시 구독 · 알림 · 웹 푸시 호출 · push_targets 결과
create function pg_temp.web() returns text language sql volatile security definer as $$
  select (select count(*) || '/' || md5(coalesce(string_agg(s::text, '|' order by s.id), '')) from public.push_subscriptions s)
    || '#' || (select count(*) || '·' || coalesce(max(id), 0) from public.notifications)
    || '#' || (select count(*) from net.calls) $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

-- 웹 푸시 구독 하나 (영향 없는지 보려고) + 알림 하나 (push_targets 결과 비교)
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth) values (:'A', 'https://push.example/a1', 'k', 'a');
insert into public.notifications (user_id, kind, message) values (:'A', 'revision_request', '테스트 알림');
select max(id) as nid from public.notifications \gset
select public.push_targets(:nid)::text as targets0 \gset
select pg_temp.web() as web0 \gset

-- ===== 1. 표 모양·제약·RLS·권한 =====
select t.ok('표 device_push_tokens: 칸 7개 (id·user_id·platform·token·app_version·created_at·last_seen_at)', (
  select string_agg(column_name || ':' || is_nullable, ',' order by ordinal_position)
    from information_schema.columns where table_schema = 'public' and table_name = 'device_push_tokens')
  = 'id:NO,user_id:NO,platform:NO,token:NO,app_version:YES,created_at:NO,last_seen_at:NO');
select t.ok('(platform, token) unique, user_id → profiles on delete cascade (push_subscriptions와 같음)',
  exists (select 1 from pg_constraint where conname = 'device_push_tokens_platform_token_key' and contype = 'u'
           and pg_get_constraintdef(oid) = 'UNIQUE (platform, token)')
  and (select confdeltype = 'c' and confrelid = 'public.profiles'::regclass from pg_constraint where conname = 'device_push_tokens_user_id_fkey')
  and (select confdeltype from pg_constraint where conname = 'push_subscriptions_user_id_fkey') = 'c');
select t.ok('RLS 켬, 정책 없음', (select relrowsecurity from pg_class where oid = 'public.device_push_tokens'::regclass)
  and not exists (select 1 from pg_policy where polrelid = 'public.device_push_tokens'::regclass));
select t.ok('표 권한: anon·authenticated 아무것도 없음, service_role은 select·delete만', not exists (
    select 1 from unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p
     where has_table_privilege('anon', 'public.device_push_tokens', p) or has_table_privilege('authenticated', 'public.device_push_tokens', p))
  and has_table_privilege('service_role', 'public.device_push_tokens', 'select') and has_table_privilege('service_role', 'public.device_push_tokens', 'delete')
  and not has_table_privilege('service_role', 'public.device_push_tokens', 'insert') and not has_table_privilege('service_role', 'public.device_push_tokens', 'update'));
select t.fails('제약: platform web 불가 (표에 직접)', format($$insert into public.device_push_tokens (user_id, platform, token) values (%L, 'web', %L)$$, :'A', pg_temp.tk(900)), 'device_push_tokens_platform_check');
select t.fails('제약: 짧은 토큰 불가', format($$insert into public.device_push_tokens (user_id, platform, token) values (%L, 'ios', 'abc')$$, :'A'), 'device_push_tokens_token_check');
select t.fails('제약: 공백 든 토큰 불가', format($$insert into public.device_push_tokens (user_id, platform, token) values (%L, 'ios', %L)$$, :'A', pg_temp.tk(901) || ' x'), 'device_push_tokens_token_check');
select t.fails('제약: 이상한 앱 버전 불가', format($$insert into public.device_push_tokens (user_id, platform, token, app_version) values (%L, 'ios', %L, '1 2')$$, :'A', pg_temp.tk(902)), 'device_push_tokens_app_version_check');

-- ===== 2. 함수 모양·권한·068 =====
select t.ok('함수 2개: security definer, search_path "", volatile, jsonb / boolean', (
  select bool_and(prosecdef and proconfig = array['search_path=""'] and provolatile = 'v') and count(*) = 2
    from pg_proc where oid in ('public.register_device_push_token(text, text, text)'::regprocedure, 'public.unregister_device_push_token(text)'::regprocedure))
  and (select prorettype = 'jsonb'::regtype from pg_proc where oid = 'public.register_device_push_token(text, text, text)'::regprocedure)
  and (select prorettype = 'boolean'::regtype from pg_proc where oid = 'public.unregister_device_push_token(text)'::regprocedure));
select t.ok('권한: 로그인만 (anon·public 없음)', (
  select bool_and(has_function_privilege('authenticated', oid, 'execute') and not has_function_privilege('anon', oid, 'execute')
                  and not exists (select 1 from unnest(proacl) a where a::text like '=%'))
    from pg_proc where oid in ('public.register_device_push_token(text, text, text)'::regprocedure, 'public.unregister_device_push_token(text)'::regprocedure)));
select t.ok('068: 두 함수는 assert_can_write 없이 허용 목록에 (웹 푸시 켜기·끄기 정책과 같은 이유)',
  (select count(*) from public.restriction_exemptions where kind = 'function'
     and name in ('register_device_push_token(text, text, text)', 'unregister_device_push_token(text)')) = 2
  and not exists (select 1 from pg_proc where proname in ('register_device_push_token', 'unregister_device_push_token') and prosrc like '%assert_can_write%')
  and exists (select 1 from public.restriction_exemptions where kind = 'policy' and name = 'public.push_subscriptions: push_subscriptions: 본인 넣기'));
select t.ok('068 쓰기 함수 수: 103개 (071의 101 + 2), 첫 줄 검사 30개 그대로, 허용 목록 함수 73개', (
  select count(*) = 103
     and count(*) filter (where p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);') = 30
     and count(*) filter (where exists (select 1 from public.restriction_exemptions e where e.kind = 'function'
                                         and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')')) = 73
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));

-- ===== 3. 비로그인·로그인 정보 없음 =====
set role anon;
select t.fails('비로그인: 등록 불가', format($$select register_device_push_token('ios', %L, '1.3.0')$$, pg_temp.tk(1)), 'permission denied');
select t.fails('비로그인: 해제 불가', format($$select unregister_device_push_token(%L)$$, pg_temp.tk(1)), 'permission denied');
select t.fails('비로그인: 표 읽기 불가', $$select count(*) from device_push_tokens$$, 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = '';
select t.fails('로그인 정보 없음: 등록 거부', format($$select register_device_push_token('ios', %L, null)$$, pg_temp.tk(1)), '로그인해 주세요');
select t.fails('로그인 정보 없음: 해제 거부', format($$select unregister_device_push_token(%L)$$, pg_temp.tk(1)), '로그인해 주세요');
reset role;

-- ===== 4. 본인 등록·갱신 =====
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('A: iOS 기기 등록 → { platform: ios, devices: 1 } (토큰은 돌려주지 않음)',
  register_device_push_token('ios', pg_temp.tk(1), '1.3.0') = '{"platform": "ios", "devices": 1}'::jsonb);
reset role;
select t.ok('줄 하나, 소유자 A, 앱 버전 1.3.0', pg_temp.owner('ios', pg_temp.tk(1)) = :'A'
  and (select app_version from device_push_tokens where token = pg_temp.tk(1)) = '1.3.0');
update device_push_tokens set created_at = now() - interval '3 days', last_seen_at = now() - interval '2 days' where token = pg_temp.tk(1);
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('같은 기기 다시 등록 (대소문자·공백 섞인 platform, 새 앱 버전) → 여전히 1대',
  (register_device_push_token('  IOS ', ' ' || pg_temp.tk(1) || ' ', '1.3.1') ->> 'devices')::int = 1);
reset role;
select t.ok('다시 등록: 중복 줄 없음, last_seen_at 갱신, 앱 버전 갱신, created_at 그대로(같은 소유자)', (
  select count(*) = 1 and bool_and(last_seen_at > now() - interval '1 minute' and app_version = '1.3.1' and created_at < now() - interval '2 days')
    from device_push_tokens where token = pg_temp.tk(1)));
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('앱 버전 빈 칸·null → null로 저장', (register_device_push_token('ios', pg_temp.tk(1), '  ') ->> 'devices')::int = 1);
reset role;
select t.ok('앱 버전 null', (select app_version is null from device_push_tokens where token = pg_temp.tk(1)));
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('같은 토큰이라도 android는 다른 줄 (platform, token이 기준)', (register_device_push_token('android', pg_temp.tk(1), '1.3.0') ->> 'devices')::int = 2);
select t.ok('A: android 기기 하나 더', (register_device_push_token('android', 'fcm:' || pg_temp.tk(2) || '_-.x', '1.3.0') ->> 'platform') = 'android');
select t.fails('앱은 표를 직접 못 읽음', $$select count(*) from device_push_tokens$$, 'permission denied');
select t.fails('앱은 표에 직접 못 넣음', format($$insert into device_push_tokens (user_id, platform, token) values (%L, 'ios', %L)$$, :'A', pg_temp.tk(3)), 'permission denied');
select t.fails('앱은 표를 직접 못 고침', format($$update device_push_tokens set user_id = %L$$, :'A'), 'permission denied');
select t.fails('앱은 표를 직접 못 지움', $$delete from device_push_tokens$$, 'permission denied');
reset role;
select t.ok('A 기기 3대', pg_temp.cnt(:'A') = 3);

-- ===== 5. 다른 계정이 같은 토큰을 등록하면 소유자 이전 =====
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.ok('B: A가 쓰던 iOS 토큰 등록 (같은 기기에서 B로 로그인) → B 1대', (register_device_push_token('ios', pg_temp.tk(1), '1.3.0') ->> 'devices')::int = 1);
reset role;
select t.ok('소유자가 B로 바뀜 (줄은 하나), created_at 새로, A는 2대', pg_temp.owner('ios', pg_temp.tk(1)) = :'B'
  and (select count(*) = 1 and bool_and(created_at > now() - interval '1 minute') from device_push_tokens where token = pg_temp.tk(1) and platform = 'ios')
  and pg_temp.cnt(:'A') = 2);

-- ===== 6. 해제 =====
-- 같은 글자 tk(1)이 ios(B 소유)·android(A 소유) 두 줄에 있다
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('A: tk(1) 해제 → true (A 소유인 android 줄만 지움)', unregister_device_push_token(pg_temp.tk(1)) = true);
reset role;
select t.ok('A의 android 줄만 지워지고 B의 ios 줄은 그대로', pg_temp.owner('android', pg_temp.tk(1)) is null
  and pg_temp.owner('ios', pg_temp.tk(1)) = :'B' and pg_temp.cnt(:'A') = 1);
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('A: 남(B)의 토큰 해제 → false (지워지지 않음)', unregister_device_push_token(pg_temp.tk(1)) = false);
reset role;
select t.ok('B 토큰 그대로', pg_temp.owner('ios', pg_temp.tk(1)) = :'B');
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('없는 토큰 해제 → false, 오류 없음', unregister_device_push_token(pg_temp.tk(777)) = false);
select t.ok('null·빈 토큰 해제 → false', unregister_device_push_token(null) = false and unregister_device_push_token('') = false);
set request.jwt.claim.sub = :'B';
select t.ok('B: 자기 토큰 해제 → true', unregister_device_push_token(' ' || pg_temp.tk(1)) = true);
select t.ok('B: 두 번째 해제 → false', unregister_device_push_token(pg_temp.tk(1)) = false);
reset role;
select t.ok('B 기기 0대', pg_temp.cnt(:'B') = 0);

-- ===== 7. 검증 오류 (문장·상세·힌트에 토큰이 나오지 않음) =====
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.fails('platform web 거부', format($$select register_device_push_token('web', %L, null)$$, pg_temp.tk(10)), 'ios 또는 android만');
select t.fails('platform null 거부', format($$select register_device_push_token(null, %L, null)$$, pg_temp.tk(10)), 'ios 또는 android만');
select t.fails('토큰 null 거부', $$select register_device_push_token('ios', null, null)$$, '알림 토큰 형식');
select t.fails('토큰 31자 거부', $$select register_device_push_token('ios', repeat('a', 31), null)$$, '알림 토큰 형식');
select t.fails('토큰 1001자 거부', $$select register_device_push_token('ios', repeat('a', 1001), null)$$, '알림 토큰 형식');
select t.fails('토큰 안 공백·줄바꿈 거부', format($$select register_device_push_token('android', %L, null)$$, pg_temp.tk(10) || E'\n' || pg_temp.tk(11)), '알림 토큰 형식');
select t.fails('토큰 따옴표·슬래시 거부', format($$select register_device_push_token('android', %L, null)$$, pg_temp.tk(10) || '/''x'), '알림 토큰 형식');
select t.fails('앱 버전 33자 거부', format($$select register_device_push_token('ios', %L, %L)$$, pg_temp.tk(10), repeat('1', 33)), '앱 버전 형식');
select t.fails('앱 버전 공백 거부', format($$select register_device_push_token('ios', %L, '1.3 beta')$$, pg_temp.tk(10)), '앱 버전 형식');
select t.ok('토큰 1000자·32자는 됨', (register_device_push_token('android', repeat('b', 1000), null) ->> 'devices')::int = 2
  and (register_device_push_token('android', repeat('c', 32), null) ->> 'devices')::int = 3);
select t.ok('오류 문장·상세·힌트에 토큰이 없음 (형식 오류 / 앱 버전 오류 / 종류 오류)',
  position(pg_temp.tk(10) in pg_temp.err(format($$select register_device_push_token('android', %L, null)$$, pg_temp.tk(10) || ' x'))) = 0
  and position(pg_temp.tk(10) in pg_temp.err(format($$select register_device_push_token('ios', %L, '1 2')$$, pg_temp.tk(10)))) = 0
  and position(pg_temp.tk(10) in pg_temp.err(format($$select register_device_push_token('web', %L, null)$$, pg_temp.tk(10)))) = 0
  and pg_temp.err(format($$select register_device_push_token('ios', %L, '1 2')$$, pg_temp.tk(10))) like '앱 버전 형식%');
reset role;
select t.ok('오류 난 등록은 줄을 남기지 않음', not exists (select 1 from device_push_tokens where token like pg_temp.tk(10) || '%'));
set role authenticated;
set request.jwt.claim.sub = :'A';
select unregister_device_push_token(repeat('b', 1000)), unregister_device_push_token(repeat('c', 32)) \gset
reset role;

-- ===== 8. 한 사람 10대 =====
-- A는 지금 1대(android fcm:…). 11대를 더 등록하면서 last_seen_at을 하나씩 과거로 밀어 순서를 정한다
set role authenticated;
set request.jwt.claim.sub = :'C';
select count(register_device_push_token(case when n % 2 = 0 then 'ios' else 'android' end, pg_temp.tk(100 + n), '1.3.0')) as reg10 from generate_series(1, 10) n \gset
reset role;
select t.ok('C: 10대까지는 그대로', pg_temp.cnt(:'C') = 10);
-- 확인 시각: tk(101)이 가장 오래됨 → tk(110)이 가장 최근
update device_push_tokens d set last_seen_at = now() - make_interval(hours => 20 - x.n)
  from generate_series(1, 10) x(n) where d.user_id = :'C' and d.token = pg_temp.tk(100 + x.n);
set role authenticated;
set request.jwt.claim.sub = :'C';
select t.ok('C: 11번째 등록 → 10대 (가장 오래 확인 안 된 tk(101) 지움)', (register_device_push_token('ios', pg_temp.tk(111), null) ->> 'devices')::int = 10);
reset role;
select t.ok('지워진 것은 tk(101)뿐, 새 기기 tk(111)은 남음', pg_temp.owner('android', pg_temp.tk(101)) is null
  and pg_temp.owner('ios', pg_temp.tk(111)) = :'C' and pg_temp.owner('ios', pg_temp.tk(102)) = :'C');
-- tk(102)가 이제 가장 오래됨. 그런데 tk(102)를 다시 등록하면(앱을 다시 엶) 최근이 되어 남고, 다음 새 기기 때는 tk(103)이 지워진다
set role authenticated;
set request.jwt.claim.sub = :'C';
select t.ok('C: 가장 오래된 tk(102)를 다시 등록 → 10대 그대로 (아무것도 안 지움)', (register_device_push_token('ios', pg_temp.tk(102), null) ->> 'devices')::int = 10);
select t.ok('C: 새 기기 tk(112) → 10대', (register_device_push_token('ios', pg_temp.tk(112), null) ->> 'devices')::int = 10);
reset role;
select t.ok('이번엔 tk(103)이 지워지고 다시 확인한 tk(102)는 남음', pg_temp.owner('android', pg_temp.tk(103)) is null
  and pg_temp.owner('ios', pg_temp.tk(102)) = :'C' and pg_temp.cnt(:'C') = 10);
select t.ok('다른 사람(A) 기기는 C의 제한에 영향 없음', pg_temp.cnt(:'A') = 1);
-- 남의 토큰을 가져와도 내 쪽 제한만 계산: A가 C의 토큰 하나를 등록 → C 9대, A 2대
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('A가 C의 기기 토큰 등록 → A 2대', (register_device_push_token('ios', pg_temp.tk(112), null) ->> 'devices')::int = 2);
reset role;
select t.ok('C는 9대로 줄어듦 (소유자 이전)', pg_temp.cnt(:'C') = 9 and pg_temp.owner('ios', pg_temp.tk(112)) = :'A');

-- ===== 9. 비회원(게스트)·활동 제한 =====
set role authenticated;
set request.jwt.claim.sub = :'G';
select t.ok('비회원(게스트)도 등록 가능 (웹 푸시 켜기와 같음)', (register_device_push_token('android', pg_temp.tk(200), null) ->> 'devices')::int = 1);
reset role;
insert into public.user_restrictions (user_id, reason, days, ends_at, created_by) values (:'R', '욕설 반복', 7, now() + interval '7 days', :'OP');
set role authenticated;
set request.jwt.claim.sub = :'R';
select t.ok('활동 제한 중인 사람: 쓰기는 막힘 (can_write false)', not can_write());
select t.ok('활동 제한 중에도 등록 가능', (register_device_push_token('ios', pg_temp.tk(300), '1.3.0') ->> 'devices')::int = 1);
select t.ok('활동 제한 중에도 해제 가능', unregister_device_push_token(pg_temp.tk(300)) = true);
select t.ok('다시 등록 (아래 탈퇴 검사용)', (register_device_push_token('ios', pg_temp.tk(300), '1.3.0') ->> 'devices')::int = 1);
reset role;

-- ===== 10. 발송 쪽 (service_role): 읽기·지우기만 =====
-- (운영 Supabase의 service_role은 기본 권한으로 notifications도 읽는다 - 로컬 흉내에는 그 권한이 없어 받는 사람 id를 미리 꺼내 둔다)
select user_id as nuid from public.notifications where id = :nid \gset
set role service_role;
select t.ok('service_role: 모든 토큰을 읽음 (RLS 우회)', (select count(*) from device_push_tokens) = pg_temp.cnt(:'A') + pg_temp.cnt(:'C') + pg_temp.cnt(:'G') + pg_temp.cnt(:'R'));
select t.ok('service_role: 알림 번호로 받는 사람의 토큰을 찾을 수 있음 (notifications.user_id)', (
  select count(*) from device_push_tokens d where d.user_id = :'nuid') = 2);
delete from device_push_tokens where platform = 'android' and token = pg_temp.tk(200);
select t.ok('service_role: 무효 토큰 지우기 (G의 기기)', not exists (select 1 from device_push_tokens where platform = 'android' and token = pg_temp.tk(200)));
select t.fails('service_role: 직접 넣기 불가', format($$insert into device_push_tokens (user_id, platform, token) values (%L, 'ios', %L)$$, :'A', pg_temp.tk(400)), 'permission denied');
select t.fails('service_role: 직접 고치기 불가', $$update device_push_tokens set app_version = '9'$$, 'permission denied');
reset role;

-- ===== 11. 사용자 삭제·탈퇴 때 함께 삭제 =====
select t.ok('준비: R 1대, C 9대', pg_temp.cnt(:'R') = 1 and pg_temp.cnt(:'C') = 9);
delete from auth.users where id = :'C';
select t.ok('auth.users에서 C 삭제 → C 토큰 9대 모두 삭제', not exists (select 1 from device_push_tokens where user_id = :'C')
  and pg_temp.owner('ios', pg_temp.tk(102)) is null);
set role authenticated;
set request.jwt.claim.sub = :'R';
select t.ok('R 탈퇴(delete_my_account, 활동 제한 중에도 가능)', delete_my_account('제한맨') is null);
reset role;
select t.ok('탈퇴 → R 토큰 삭제, 다른 사람 토큰은 그대로', pg_temp.cnt(:'R') = 0 and not exists (select 1 from profiles where id = :'R')
  and pg_temp.cnt(:'A') = 2);

-- ===== 12. 기존 웹 푸시·알림에 영향 없음 =====
select t.ok('push_subscriptions·알림·웹 푸시 호출(net.calls) 그대로', pg_temp.web() = :'web0');
select t.ok('push_targets 결과 그대로 (앱 토큰은 웹 구독 목록에 섞이지 않음)', public.push_targets(:nid)::text = :'targets0');
select t.ok('A의 웹 푸시 구독은 1개 그대로', (select count(*) from push_subscriptions where user_id = :'A') = 1);
