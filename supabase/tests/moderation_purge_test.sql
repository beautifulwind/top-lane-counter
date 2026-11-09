-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 035: 처리 기록(moderation_log) 1년 보관 후 삭제
\set ON_ERROR_STOP 1
\set QUIET 1
\set U '00000000-0000-0000-0000-00000000000d'
insert into auth.users (id, email) values (:'U', 'u@x.com');

select t.ok('설정값 365일', (select value = 365 from public.xp_rules where key = 'moderation_log_keep_days'));
delete from moderation_log;
insert into moderation_log (actor_id, actor_nickname, actor_role, action, target_kind, target_id, created_at) values
  (:'U', '영자', 'admin', 'hide',            'post', '1', now() - interval '366 days'),
  (:'U', '영자', 'admin', 'grant_moderator', 'user', 'x', now() - interval '400 days'),
  (:'U', '영자', 'admin', 'restore',         'post', '2', now() - interval '364 days'),
  (:'U', '영자', 'admin', 'hide',            'post', '3', now());
select t.ok('1년 지난 2건만 지움(지정·해제 기록 포함)', (select public.purge_old_moderation_log() = 2));
select t.ok('남은 것은 364일 된 것과 오늘 것', (select count(*) = 2 from moderation_log));
update public.xp_rules set value = 30 where key = 'moderation_log_keep_days';
select t.ok('보관 기간은 설정값을 따름', (select public.purge_old_moderation_log() = 1));
select t.ok('오늘 기록만 남음', (select count(*) = 1 from moderation_log));
update public.xp_rules set value = 365 where key = 'moderation_log_keep_days';

set role authenticated;
select t.fails('삭제 함수는 사람이 못 부름', $$select purge_old_moderation_log()$$, 'permission denied');
reset role;
select t.ok('anon도 못 부름', not has_function_privilege('anon', 'public.purge_old_moderation_log()', 'execute')
  and not has_function_privilege('authenticated', 'public.purge_old_moderation_log()', 'execute'));
