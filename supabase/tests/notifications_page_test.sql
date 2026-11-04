-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 027: 알림 화면 — 모두 읽음(본인 것만, 맨 위 번호까지), 90일 지난 알림 지우기(사람은 못 부름), 색인
\set ON_ERROR_STOP 1
\set QUIET 1
\set B '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
insert into auth.users (id, email) values (:'B', 'u@x.com'), (:'D', 'u2@x.com');
update public.profiles set nickname = '유저' where id = :'B';
update public.profiles set nickname = '유저2' where id = :'D';

-- 알림은 DB 함수만 만든다 → postgres로 직접 넣어 준비
insert into public.notifications (user_id, kind, message, created_at) values
  (:'B', 'level_up', '레벨이 올랐습니다: Lv.2', now() - interval '100 days'),
  (:'B', 'level_up', '레벨이 올랐습니다: Lv.3', now() - interval '1 day'),
  (:'B', 'level_up', '레벨이 올랐습니다: Lv.4', now()),
  (:'D', 'level_up', '레벨이 올랐습니다: Lv.2', now());
create temp table ids as select max(id) filter (where message like '%Lv.3' and user_id = :'B') as mid,
                                max(id) filter (where message like '%Lv.4') as top from public.notifications;
grant select on ids to authenticated;

select t.ok('색인 있음', exists (select 1 from pg_indexes where indexname = 'notifications_user_recent_idx'));
select t.ok('보관 기간 설정 90일', (select value = 90 from public.xp_rules where key = 'notification_keep_days'));

-- ===== 1. 모두 읽음: 본인 것만, 맨 위 번호까지 =====
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('처음엔 안 읽은 알림 3개', (select count(*) = 3 from public.notifications where read_at is null));
select mark_all_notifications_read((select mid from ids)) as t1 \gset
select t.ok('맨 위 번호(Lv.3)까지만 읽음, 그 뒤에 온 Lv.4는 그대로',
  (select count(*) filter (where read_at is not null) = 2 and count(*) filter (where read_at is null and message like '%Lv.4') = 1 from public.notifications));
select t.ok('읽음 시각 = 돌려준 시각 (화면의 "새" 표시용)', (select bool_and(read_at = :'t1'::timestamptz) from public.notifications where read_at is not null));
select mark_all_notifications_read((select top from ids));
select t.ok('다시 부르면 나머지도 읽음', (select count(*) = 0 from public.notifications where read_at is null));
reset role;
select t.ok('남의 알림은 그대로', (select read_at is null from public.notifications where user_id = :'D'));

set role anon;
select t.fails('로그인 안 하면 못 부름', 'select mark_all_notifications_read(1)', 'permission denied');
reset role;

-- ===== 2. 90일 지난 알림 지우기: pg_cron(postgres)만 =====
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('사람은 지우기 함수를 못 부름', 'select purge_old_notifications()', 'permission denied');
reset role;
select t.ok('지운 개수 1 (100일 된 것만)', purge_old_notifications() = 1);
select t.ok('남은 알림 3개 (1일 된 것·오늘 것)', (select count(*) = 3 from public.notifications));
update public.xp_rules set value = 0 where key = 'notification_keep_days';
select t.ok('보관 기간을 0일로 바꾸면 모두 지움', purge_old_notifications() = 3);
