-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_push_wanted_after.sql)
-- 073 push_wanted: 마지막 조건만 「웹 구독이 있음」 → 「웹 구독이 있거나 앱 기기 토큰(device_push_tokens)이 있음」.
--   웹 구독만 있는 사람(전과 같음), 앱 토큰만 있는 사람(true), 둘 다 없는 사람(false), 설정을 끈 사람(false),
--   운영진 알림(감독관·운영자 모드)과 묶음별 기본값이 전과 같음, 알림 종류 전체 × 사람 전체에서 「067 판단 그대로 + 기기 조건만 바뀜」,
--   트리거가 앱 전용 사람에게도 Edge Function을 부름, push_targets는 앱 전용 사람에게 웹 구독 [](빈 목록)을 줌,
--   함수 모양·권한·소유자 그대로, 소유자 권한으로 device_push_tokens를 읽을 수 있음(RLS 정책 없음이어도), 068 쓰기 함수 수 그대로.
--   (074가 push_wanted에 댓글 묶음 줄을 더한 뒤에도 돌도록: 본문 지문은 074 줄을 뺀 값으로 비교, 비교 기준 core에도 074 줄 - 댓글 묶음 자체는 comment_push_test)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set W   '00000000-0000-0000-0000-0000000000f1'
\set A   '00000000-0000-0000-0000-0000000000f2'
\set N   '00000000-0000-0000-0000-0000000000f3'
\set WA  '00000000-0000-0000-0000-0000000000f4'
\set OFF '00000000-0000-0000-0000-0000000000f5'
\set INF '00000000-0000-0000-0000-0000000000f6'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'mod@x.com'), (:'W', 'w@x.com'), (:'A', 'a@x.com'),
  (:'N', 'n@x.com'), (:'WA', 'wa@x.com'), (:'OFF', 'off@x.com'), (:'INF', 'inf@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '웹만' where id = :'W';
update public.profiles set nickname = '앱만' where id = :'A';
update public.profiles set nickname = '없음' where id = :'N';
update public.profiles set nickname = '둘다' where id = :'WA';
update public.profiles set nickname = '끔' where id = :'OFF';
update public.profiles set nickname = '장인' where id = :'INF';
create function pg_temp.tk(n int) returns text language sql immutable as $$ select md5('tok' || n) || md5('ken' || n) $$;

-- 067 본문 그대로 (비교 기준). core = 마지막 기기 조건을 뺀 판단, old = 067 전체(웹 구독 필요)
create function pg_temp.core(p_user uuid, p_kind text) returns boolean language sql stable as $$
  select case public.push_group(p_kind)
    when 'staff_new' then
      exists (select 1 from public.profiles p
               where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
      and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
    when 'my_results' then
      coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
    when 'follow_builds' then
      coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
    when 'notice' then
      coalesce((select s.notice from public.push_settings s where s.user_id = p_user), true)
    when 'new_followers' then
      coalesce((select s.new_followers from public.push_settings s where s.user_id = p_user), false)
    when 'build_edits' then
      coalesce((select s.build_edits from public.push_settings s where s.user_id = p_user), true)
    when 'comments' then
      coalesce((select s.comments from public.push_settings s where s.user_id = p_user), true)  -- 074 (073 판단과 무관한 묶음 추가)
    else false
  end $$;
create function pg_temp.web(p uuid) returns boolean language sql stable as $$ select exists (select 1 from public.push_subscriptions where user_id = p) $$;
create function pg_temp.app(p uuid) returns boolean language sql stable as $$ select exists (select 1 from public.device_push_tokens where user_id = p) $$;
create function pg_temp.old(p_user uuid, p_kind text) returns boolean language sql stable as $$ select pg_temp.core(p_user, p_kind) and pg_temp.web(p_user) $$;
-- 알림 종류 전체 (notifications_kind_check에서 읽음) + 없는 종류 하나
create function pg_temp.kinds() returns setof text language sql stable as $$
  select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] from pg_constraint where conname = 'notifications_kind_check'
  union select 'no_such_kind' $$;
-- 트리거가 부른 알림 번호들
create function pg_temp.called(p uuid) returns integer language sql stable as $$
  select count(*)::int from net.calls c join public.notifications n on n.id = (c.body ->> 'notification_id')::bigint where n.user_id = p $$;

-- 기기: W 웹만, A 앱만(iOS), WA 둘 다, OFF 앱만(설정 끔), MOD·OP 앱만(Android), INF 앱만, N 없음
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth) values
  (:'W', 'https://push.example/w', 'k', 'a'), (:'WA', 'https://push.example/wa', 'k', 'a');
insert into public.device_push_tokens (user_id, platform, token) values
  (:'A', 'ios', pg_temp.tk(1)), (:'WA', 'android', pg_temp.tk(2)), (:'OFF', 'ios', pg_temp.tk(3)),
  (:'MOD', 'android', pg_temp.tk(4)), (:'OP', 'android', pg_temp.tk(5)), (:'INF', 'ios', pg_temp.tk(6));
insert into public.push_settings (user_id, staff_new, my_results, follow_builds, notice, new_followers, build_edits, comments)
  values (:'OFF', false, false, false, false, false, false, false);  -- comments: 074

-- ===== 1. 함수 모양·권한·소유자 그대로, 본문은 마지막 조건만 =====
select t.ok('push_wanted 본문 지문: 074가 더한 댓글 줄을 빼면 e6f1723a… (073 파일 그대로)',
  (select md5(replace(replace(prosrc, E'\r', ''), E'\n    when ''comments'' then\n      coalesce((select s.comments from public.push_settings s where s.user_id = p_user), true)  -- 074 댓글·답글', '')) from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure) = 'e6f1723ae3a6b0126ece4b51488a067c');
select t.ok('새 조건을 옛 조건으로 되바꾸면(074 댓글 줄도 빼고) 067 본문 지문 bfb8e950… (나머지 판단은 한 글자도 안 바뀜)',
  (select md5(replace(replace(replace(prosrc, E'\r', ''), E'\n    when ''comments'' then\n      coalesce((select s.comments from public.push_settings s where s.user_id = p_user), true)  -- 074 댓글·답글', ''),
     E'  and (exists (select 1 from public.push_subscriptions where user_id = p_user)\n       or exists (select 1 from public.device_push_tokens where user_id = p_user));  -- 073: 웹 구독 또는 앱 기기 토큰',
     '  and exists (select 1 from public.push_subscriptions where user_id = p_user);'))
     from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure) = 'bfb8e95016ca726a7dade1b76bb56fce');
select t.ok('이름·인자·반환·stable·security definer·search_path "" 그대로, 같은 이름 함수 1개', (
  select prorettype = 'boolean'::regtype and provolatile = 's' and prosecdef and proconfig = array['search_path=""']
    from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure)
  and (select count(*) from pg_proc where proname = 'push_wanted') = 1);
select t.ok('실행 권한 그대로: anon·authenticated·service_role 모두 못 부름 (남의 설정을 묻지 못하게)',
  not has_function_privilege('anon', 'public.push_wanted(uuid, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.push_wanted(uuid, text)', 'execute')
  and not has_function_privilege('service_role', 'public.push_wanted(uuid, text)', 'execute'));
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.fails('로그인 사용자는 직접 못 부름', format('select push_wanted(%L, %L)', :'A', 'link_removed'), 'permission denied');
reset role;
select t.ok('068 쓰기 함수 수: 105 / 첫 줄 검사 31 / 허용 목록 74 (080 · 081 포함, push_wanted는 쓰기 함수 아님)', (
  select count(*) = 105
     and count(*) filter (where p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);') = 31
     and count(*) filter (where exists (select 1 from public.restriction_exemptions e where e.kind = 'function'
                                         and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')')) = 74
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));

-- ===== 2. 소유자 권한으로 device_push_tokens를 읽을 수 있음 =====
select t.ok('push_wanted 소유자 = device_push_tokens 소유자, FORCE RLS 꺼짐, 소유자 select 권한 있음',
  (select proowner from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure)
    = (select relowner from pg_class where oid = 'public.device_push_tokens'::regclass)
  and not (select relforcerowsecurity from pg_class where oid = 'public.device_push_tokens'::regclass)
  and has_table_privilege((select proowner from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure), 'public.device_push_tokens', 'select'));
-- 로컬 postgres는 슈퍼유저라 위 확인만으로는 RLS를 지나는지 알 수 없다 → 슈퍼유저·BYPASSRLS가 아닌 역할을 표 소유자로 바꿔 보고 되돌린다
begin;
create role owner_sim_073 nosuperuser nobypassrls;
alter table public.device_push_tokens owner to owner_sim_073;
set local role owner_sim_073;
select count(*) as sim_seen from public.device_push_tokens \gset
reset role;
rollback;
select t.ok('슈퍼유저가 아닌 표 소유자도 RLS(정책 없음)에 막히지 않고 6줄 모두 읽음 (운영 postgres 소유자와 같은 규칙)', :sim_seen = 6);
select t.ok('흉내 역할은 되돌려짐 (소유자 postgres 그대로)', pg_get_userbyid((select relowner from pg_class where oid = 'public.device_push_tokens'::regclass)) = 'postgres'
  and not exists (select 1 from pg_roles where rolname = 'owner_sim_073'));
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.fails('일반 로그인 사용자는 여전히 device_push_tokens를 직접 못 읽음', 'select count(*) from device_push_tokens', 'permission denied');
reset role;

-- ===== 3. 사람별 결과 =====
select t.ok('웹 구독만 있는 사람(W): 전과 같음 - 내 결과·공지·팔로우·빌드 수정 true, 운영진·새 팔로워(기본 꺼짐)·없는 종류 false',
  push_wanted(:'W', 'link_removed') and push_wanted(:'W', 'notice_posted') and push_wanted(:'W', 'followed_build_created') and push_wanted(:'W', 'build_edited')
  and not push_wanted(:'W', 'inquiry_received') and not push_wanted(:'W', 'new_followers') and not push_wanted(:'W', 'level_up'));
select t.ok('웹 구독만 있는 사람(W): 모든 종류에서 067 결과와 같음',
  (select bool_and(push_wanted(:'W', k) = pg_temp.old(:'W', k)) from pg_temp.kinds() k));
select t.ok('앱 토큰만 있는 사람(A): true (073 전에는 false였음)',
  push_wanted(:'A', 'link_removed') and push_wanted(:'A', 'warning_received') and push_wanted(:'A', 'notice_posted')
  and not pg_temp.old(:'A', 'link_removed'));
select t.ok('앱 토큰만 있는 사람(A): 묶음 판단은 067 그대로 (운영진 false, 새 팔로워 기본 꺼짐 false, 푸시 안 하는 종류 false)',
  not push_wanted(:'A', 'proposal_submitted') and not push_wanted(:'A', 'new_followers') and not push_wanted(:'A', 'level_up')
  and not push_wanted(:'A', 'no_such_kind'));
select t.ok('둘 다 없는 사람(N): 모든 종류 false', (select bool_and(not push_wanted(:'N', k)) from pg_temp.kinds() k));
select t.ok('둘 다 있는 사람(WA): 모든 종류에서 067 결과와 같음', (select bool_and(push_wanted(:'WA', k) = pg_temp.old(:'WA', k)) from pg_temp.kinds() k));
select t.ok('설정을 모두 끈 사람(OFF, 앱 토큰 있음): 모든 종류 false', (select bool_and(not push_wanted(:'OFF', k)) from pg_temp.kinds() k));
select t.ok('감독관(MOD, 앱만): 운영진 알림 true, 내 결과 true', push_wanted(:'MOD', 'inquiry_received') and push_wanted(:'MOD', 'report_received')
  and push_wanted(:'MOD', 'link_removed'));
select t.ok('운영자(OP, 앱만) 운영자 모드 켬: 운영진 알림 true', push_wanted(:'OP', 'post_created') and push_wanted(:'OP', 'influencer_applied'));
update public.profiles set operator_mode = false where id = :'OP';
select t.ok('운영자 모드 끔: 운영진 알림 false, 내 결과는 그대로 true', not push_wanted(:'OP', 'post_created') and push_wanted(:'OP', 'link_removed'));
update public.profiles set operator_mode = true where id = :'OP';
insert into public.push_settings (user_id, staff_new) values (:'MOD', false);
select t.ok('감독관이 운영진 알림 설정을 끄면 false, 다른 묶음은 true', not push_wanted(:'MOD', 'inquiry_received') and push_wanted(:'MOD', 'notice_posted'));
delete from public.push_settings where user_id = :'MOD';
select t.ok('장인(INF, 앱만): 새 팔로워는 설정 줄이 없으면 꺼짐', not push_wanted(:'INF', 'new_followers'));
insert into public.push_settings (user_id, new_followers) values (:'INF', true);
select t.ok('장인이 새 팔로워를 켜면 true (앱만이어도)', push_wanted(:'INF', 'new_followers'));
update public.push_settings set new_followers = false, notice = false where user_id = :'INF';
select t.ok('묶음 하나만 끄면 그 묶음만 false', not push_wanted(:'INF', 'notice_posted') and push_wanted(:'INF', 'followed_build_created')
  and push_wanted(:'INF', 'build_edited') and push_wanted(:'INF', 'link_removed'));
delete from public.push_settings where user_id = :'INF';

-- ===== 4. 전체 표: 모든 사람 × 모든 종류 =====
select t.ok('모든 사람 × 모든 종류: push_wanted = 067 판단(core) 그대로 and (웹 구독 or 앱 토큰)', (
  select bool_and(push_wanted(p.id, k) = (pg_temp.core(p.id, k) and (pg_temp.web(p.id) or pg_temp.app(p.id))))
    from public.profiles p, pg_temp.kinds() k));
select t.ok('웹 구독이 있는 모든 사람 × 모든 종류: 067 결과와 같음 (웹 사용자 동작 변화 없음)', (
  select bool_and(push_wanted(p.id, k) = pg_temp.old(p.id, k)) from public.profiles p, pg_temp.kinds() k where pg_temp.web(p.id)));
select t.ok('결과가 067과 달라지는 경우는 「웹 구독 없음 + 앱 토큰 있음」에서 false → true 뿐', not exists (
  select 1 from public.profiles p, pg_temp.kinds() k
   where push_wanted(p.id, k) <> pg_temp.old(p.id, k)
     and not (not pg_temp.web(p.id) and pg_temp.app(p.id) and push_wanted(p.id, k) and not pg_temp.old(p.id, k))));
select t.ok('검사 범위: 알림 종류 50개 이상, 사람 8명 이상', (select count(*) from pg_temp.kinds()) >= 50 and (select count(*) from public.profiles) >= 8);

-- ===== 5. 트리거가 Edge Function을 부르는지 · push_targets =====
insert into vault.decrypted_secrets values ('push_function_url', 'https://fn.test/functions/v1/web-push'), ('push_webhook_secret', 's3cret');
delete from net.calls;
insert into public.notifications (user_id, kind, message) values
  (:'W', 'link_removed', '웹만'), (:'A', 'link_removed', '앱만'), (:'N', 'link_removed', '없음'),
  (:'WA', 'link_removed', '둘다'), (:'OFF', 'link_removed', '끔'), (:'A', 'proposal_submitted', '앱만 운영진 종류'),
  (:'MOD', 'inquiry_received', '감독관 앱만');
select t.ok('트리거: 웹만 1·앱만 1·둘 다 1·감독관(앱만) 운영진 알림 1 → 부름', pg_temp.called(:'W') = 1 and pg_temp.called(:'A') = 1
  and pg_temp.called(:'WA') = 1 and pg_temp.called(:'MOD') = 1);
select t.ok('트리거: 둘 다 없음·설정 끔·운영진이 아닌 사람의 운영진 종류 → 안 부름', pg_temp.called(:'N') = 0 and pg_temp.called(:'OFF') = 0
  and not exists (select 1 from net.calls c join public.notifications n on n.id = (c.body ->> 'notification_id')::bigint where n.kind = 'proposal_submitted'));
select t.ok('부르는 내용은 그대로 (주소·비밀 값 헤더·알림 번호만)', (select bool_and(url = 'https://fn.test/functions/v1/web-push'
  and headers ->> 'x-push-secret' = 's3cret' and (select array_agg(k) from jsonb_object_keys(body) k) = array['notification_id']) from net.calls));
select id as aid from public.notifications where user_id = :'A' and message = '앱만' \gset
select id as wid from public.notifications where user_id = :'W' and message = '웹만' \gset
select public.push_targets(:aid) as ta \gset
select t.ok('push_targets(앱만 사람의 알림): 알림 내용은 있고 웹 구독 목록은 [] → Edge Function이 웹 0건 뒤 앱 발송으로 이어감',
  (:'ta'::jsonb -> 'notification' ->> 'kind') = 'link_removed' and (:'ta'::jsonb -> 'subscriptions') = '[]'::jsonb);
select t.ok('push_targets(웹만 사람의 알림): 웹 구독 1개 그대로 (앱 토큰은 웹 목록에 섞이지 않음)',
  jsonb_array_length(public.push_targets(:wid) -> 'subscriptions') = 1
  and (public.push_targets(:wid) -> 'subscriptions' -> 0 ->> 'endpoint') = 'https://push.example/w');

-- ===== 6. 앱 토큰을 해제하면 다시 false =====
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('A가 로그아웃(토큰 해제)', unregister_device_push_token(pg_temp.tk(1)));
reset role;
select t.ok('토큰이 없어지면 다시 false (둘 다 없는 사람과 같음)', not push_wanted(:'A', 'link_removed'));
delete from net.calls;
insert into public.notifications (user_id, kind, message) values (:'A', 'link_removed', '해제 뒤');
select t.ok('해제 뒤 알림: 트리거가 안 부름', pg_temp.called(:'A') = 0);

-- ===== 7. 탈퇴(계정 삭제)하면 토큰과 함께 사라져 대상 아님 =====
delete from auth.users where id = :'INF';
select t.ok('삭제된 사람은 false', not push_wanted(:'INF', 'link_removed'));
