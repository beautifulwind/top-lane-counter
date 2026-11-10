-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 037: 웹 푸시 — 기기 알림 주소·종류별 설정 RLS, 알림이 생길 때 보낼 대상 판단, Edge Function용 함수
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set U2  '00000000-0000-0000-0000-00000000000e'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'U2', 'u2@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '유저둘' where id = :'U2';

-- ===== 1. 기기 알림 주소: 본인 것만 =====
set role anon;
select t.fails('비로그인은 못 읽음', 'select * from push_subscriptions', 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (auth.uid(), 'https://push.test/u-1', 'k', 'a');
select t.fails('남의 이름으로 못 넣음',
  $$insert into push_subscriptions (user_id, endpoint, p256dh, auth) values ('00000000-0000-0000-0000-00000000000e', 'https://push.test/x', 'k', 'a')$$,
  'row-level security');
select t.fails('https 주소만', $$insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (auth.uid(), 'http://push.test/x', 'k', 'a')$$, 'check');
select t.fails('고치기 권한 없음', $$update push_subscriptions set p256dh = 'z'$$, 'permission denied');
select t.ok('본인 것은 보임', (select count(*) = 1 from push_subscriptions));
set request.jwt.claim.sub = :'U2';
select t.ok('남의 것은 안 보임', (select count(*) = 0 from push_subscriptions));
delete from push_subscriptions where endpoint = 'https://push.test/u-1';
select t.fails('같은 주소를 다른 사람이 넣으면 거부 (남의 줄을 덮어쓰지 못함)',
  $$insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (auth.uid(), 'https://push.test/u-1', 'k', 'a')$$, 'duplicate');
reset role;
select t.ok('남의 것은 못 지움', (select count(*) = 1 from push_subscriptions where user_id = :'U'));

-- 한 사람 최대 10대: 11번째를 넣으면 가장 오래된 것이 빠진다
set role authenticated;
set request.jwt.claim.sub = :'U2';
insert into push_subscriptions (user_id, endpoint, p256dh, auth)
select auth.uid(), 'https://push.test/u2-' || g, 'k', 'a' from generate_series(1, 11) g;
select t.ok('최대 10대', (select count(*) = 10 from push_subscriptions));
select t.ok('가장 오래된 것이 빠짐', not exists (select 1 from push_subscriptions where endpoint = 'https://push.test/u2-1'));
delete from push_subscriptions;
select t.ok('본인 것 지우기', (select count(*) = 0 from push_subscriptions));
reset role;

-- ===== 2. 종류별 설정: 본인 것만, 저장(upsert) =====
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into push_settings (user_id, my_results) values (auth.uid(), false)
  on conflict (user_id) do update set my_results = excluded.my_results;
insert into push_settings (user_id, my_results) values (auth.uid(), true)
  on conflict (user_id) do update set my_results = excluded.my_results;
select t.ok('설정 저장·고치기', (select my_results and staff_new from push_settings));
select t.fails('남의 설정은 못 넣음', $$insert into push_settings (user_id) values ('00000000-0000-0000-0000-00000000000e')$$, 'row-level security');
select t.fails('내 설정 줄을 남의 것으로 못 바꿈', $$update push_settings set user_id = '00000000-0000-0000-0000-00000000000e'$$, 'row-level security');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U2';
select t.ok('남의 설정은 안 보임', (select count(*) = 0 from push_settings));
select t.fails('보낼 대상 판단 함수는 직접 못 부름', format('select push_wanted(%L, %L)', :'U', 'proposal_approved'), 'permission denied');
select t.fails('Edge Function용 함수는 로그인 사용자가 못 부름', 'select push_targets(1)', 'permission denied');
select t.fails('만료 지우기 함수도 못 부름', 'select push_forget(array[1]::bigint[])', 'permission denied');
reset role;

-- ===== 3. 알림이 생기면 Edge Function 부르기 =====
-- 운영자·감독관·유저 모두 기기 하나씩
insert into push_subscriptions (user_id, endpoint, p256dh, auth) values
  (:'OP', 'https://push.test/op', 'k', 'a'), (:'MOD', 'https://push.test/mod', 'k', 'a');
-- Vault 설정 전: 알림은 생기고 부르기는 없음
insert into notifications (user_id, kind, message) values (:'U', 'proposal_approved', '설정 전');
select t.ok('Vault 설정 전: 알림은 저장, 부르기 없음', (select count(*) = 0 from net.calls) and exists (select 1 from notifications where message = '설정 전'));
insert into vault.decrypted_secrets values ('push_function_url', 'https://fn.test/functions/v1/web-push'), ('push_webhook_secret', 's3cret');

-- 유저가 새 카운터 제안 → 운영자·감독관에게 proposal_submitted → 둘 다 부름
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build()) returning id as gp \gset
reset role;
select t.ok('새 제안: 운영자·감독관 알림마다 부름',
  (select count(*) = 2 from net.calls c join notifications n on n.id = (c.body ->> 'notification_id')::bigint
    where n.kind = 'proposal_submitted' and n.user_id in (:'OP', :'MOD')));
select t.ok('주소·비밀 값 헤더·알림 번호만 보냄',
  (select bool_and(url = 'https://fn.test/functions/v1/web-push' and headers ->> 'x-push-secret' = 's3cret'
                   and (select array_agg(k) from jsonb_object_keys(body) k) = array['notification_id']) from net.calls));

-- 운영자 승인 → 유저에게 proposal_approved → 부름 (처리한 운영자 본인에게는 알림 자체가 없음)
delete from net.calls;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select approve_proposal(:gp, '좋습니다', null, null, t.pv(:gp)) as garen \gset
reset role;
select t.ok('승인: 제안자에게 부름',
  exists (select 1 from net.calls c join notifications n on n.id = (c.body ->> 'notification_id')::bigint
           where n.kind = 'proposal_approved' and n.user_id = :'U'));
select t.ok('푸시하지 않는 종류(경험치·레벨 등)는 안 부름',
  not exists (select 1 from net.calls c join notifications n on n.id = (c.body ->> 'notification_id')::bigint
               where public.push_group(n.kind) is null));
select t.ok('부른 것은 모두 유저 것 (운영자 본인 제외 규칙 그대로)',
  (select bool_and(n.user_id = :'U') from net.calls c join notifications n on n.id = (c.body ->> 'notification_id')::bigint));

-- 기기가 없는 사람(유저둘)의 알림은 부르지 않음
delete from net.calls;
insert into notifications (user_id, kind, message) values (:'U2', 'proposal_rejected', '기기 없음');
select t.ok('기기가 없으면 안 부름', (select count(*) = 0 from net.calls));

-- 운영자 모드 끔 → 운영진 알림은 운영자에게 안 감, 감독관에게는 감
update profiles set operator_mode = false where id = :'OP';
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Ornn', auth.uid(), :'doc', t.build()) returning id as orp \gset
reset role;
select t.ok('운영자 모드 끔: 운영자 알림은 저장되지만 푸시 안 함',
  exists (select 1 from notifications where user_id = :'OP' and kind = 'proposal_submitted' and proposal_id = :orp)
  and not exists (select 1 from net.calls c join notifications n on n.id = (c.body ->> 'notification_id')::bigint where n.user_id = :'OP'));
select t.ok('운영자 모드 끔: 감독관에게는 감',
  exists (select 1 from net.calls c join notifications n on n.id = (c.body ->> 'notification_id')::bigint where n.user_id = :'MOD'));
update profiles set operator_mode = true where id = :'OP';

-- 종류별 설정: 감독관이 운영진 알림 끔, 유저가 내 제안 결과 끔
delete from net.calls;
insert into push_settings (user_id, staff_new) values (:'MOD', false);
update push_settings set my_results = false where user_id = :'U';
insert into notifications (user_id, kind, message) values
  (:'MOD', 'inquiry_received', '새 문의'), (:'U', 'build_rejected', '거절'), (:'OP', 'inquiry_received', '새 문의');
select t.ok('설정을 끈 종류는 안 부름 (운영자만 부름)',
  (select count(*) = 1 from net.calls c join notifications n on n.id = (c.body ->> 'notification_id')::bigint where n.user_id = :'OP'));
update push_settings set my_results = true where user_id = :'U';
delete from push_settings where user_id = :'MOD';

-- 운영진이 아닌 사람에게 운영진 종류가 있어도 안 감 (예: 감독관 해제 뒤)
delete from net.calls;
insert into notifications (user_id, kind, message) values (:'U', 'proposal_submitted', '이상한 줄');
select t.ok('운영진이 아니면 운영진 알림 푸시 안 함', (select count(*) = 0 from net.calls));

-- 내 제안 결과 종류 전부
delete from net.calls;
insert into notifications (user_id, kind, message)
select :'U', k, '결과' from unnest(array['proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'revision_request', 'counter_restored', 'build_restored']) k;
insert into notifications (user_id, kind, message)
select :'U', k, '안 보냄' from unnest(array['revision_cancelled', 'build_hidden', 'level_up', 'post_comment', 'inquiry_answered']) k;
select t.ok('승인·거절·재검토 요청·다시 공개 7종만 부름', (select count(*) = 7 from net.calls));

-- Edge Function 부르기가 실패해도 알림 저장은 그대로
create or replace function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000)
returns bigint language plpgsql as $$ begin raise exception 'pg_net 꺼짐'; end $$;
set client_min_messages = error;
insert into notifications (user_id, kind, message) values (:'U', 'proposal_approved', '부르기 실패');
reset client_min_messages;
select t.ok('부르기 실패: 알림은 저장됨', exists (select 1 from notifications where message = '부르기 실패'));

-- ===== 4. Edge Function용 함수 (service_role) =====
select id as nid from notifications where message = '부르기 실패' \gset
set role service_role;
select push_targets(:nid) as tg \gset
reset role;
select t.ok('push_targets: 알림 내용과 받을 기기',
  (:'tg'::jsonb -> 'notification' ->> 'kind') = 'proposal_approved'
  and jsonb_array_length(:'tg'::jsonb -> 'subscriptions') = 1
  and (:'tg'::jsonb -> 'subscriptions' -> 0 ->> 'endpoint') = 'https://push.test/u-1');
update push_settings set my_results = false where user_id = :'U';
set role service_role;
select t.ok('push_targets: 그 사이 설정을 끄면 기기 없음', jsonb_array_length(push_targets(:nid) -> 'subscriptions') = 0);
reset role;
update push_settings set my_results = true where user_id = :'U';
update notifications set created_at = now() - interval '2 hours' where id = :nid;
set role service_role;
select t.ok('push_targets: 1시간 지난 알림은 보내지 않음', jsonb_array_length(push_targets(:nid) -> 'subscriptions') = 0);
reset role;
select id as sid from push_subscriptions where endpoint = 'https://push.test/u-1' \gset
set role service_role;
select push_forget(array[:sid]::bigint[]) as forgot \gset
reset role;
select t.ok('push_forget: 만료 주소 지움', :forgot = 1 and not exists (select 1 from push_subscriptions where endpoint = 'https://push.test/u-1'));

-- ===== 5. 탈퇴하면 기기 주소·설정도 함께 지워짐 =====
insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (:'U2', 'https://push.test/u2-gone', 'k', 'a');
insert into push_settings (user_id) values (:'U2');
delete from auth.users where id = :'U2';
select t.ok('탈퇴: 기기 주소·설정 삭제',
  not exists (select 1 from push_subscriptions where user_id = :'U2') and not exists (select 1 from push_settings where user_id = :'U2'));
