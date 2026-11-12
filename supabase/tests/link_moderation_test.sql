-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 048: 장인 외부 링크 삭제를 감독관도 (일반 장인 링크만, 운영진 링크 거부, 사유 필수, 운영자 모드 꺼짐 거부, 신고 목록/기각은 운영자만)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP   '00000000-0000-0000-0000-00000000000a'
\set MOD  '00000000-0000-0000-0000-00000000000b'
\set MOD2 '00000000-0000-0000-0000-000000000015'
\set U    '00000000-0000-0000-0000-00000000000d'
\set V    '00000000-0000-0000-0000-00000000000c'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'MOD2', 'm2@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator', influencer = 'pro', influencer_at = now() where id = :'MOD';
update public.profiles set nickname = '감독둘', role = 'moderator', influencer = 'creator', influencer_at = now() where id = :'MOD2';
update public.profiles set nickname = '장인유저', influencer = 'creator', influencer_at = now() where id = :'U';
update public.profiles set nickname = '보통' where id = :'V';
delete from notifications;
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
-- 링크는 표에 바로 넣는다 (올리는 규칙은 influencer_links_test). 운영자 링크는 장인 신청이 막혀 있어 생길 수 없지만 거부되는지 보려고 넣는다
insert into ext_links (owner_id, url, host) values
  (:'U', 'https://youtube.com/@u1', 'youtube.com'), (:'U', 'https://youtube.com/@u2', 'youtube.com'), (:'U', 'https://youtube.com/@u3', 'youtube.com'),
  (:'MOD', 'https://youtube.com/@mod', 'youtube.com'), (:'MOD2', 'https://youtube.com/@mod2', 'youtube.com'), (:'OP', 'https://youtube.com/@op', 'youtube.com');
insert into ids select 'u' || row_number() over (order by id), id from ext_links where owner_id = :'U';
insert into ids select 'mod', id from ext_links where owner_id = :'MOD';
insert into ids select 'mod2', id from ext_links where owner_id = :'MOD2';
insert into ids select 'op', id from ext_links where owner_id = :'OP';
insert into link_reports (link_id, reporter_id, reason) values (pg_temp.id('u1'), :'V', 'spam');

-- ===== 1. 감독관 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 사유 없으면 거부', format('select remove_link(%s, %L)', pg_temp.id('u1'), '  '), '삭제 사유를 적어');
select t.fails('감독관: 사유 null도 거부', format('select remove_link(%s, null)', pg_temp.id('u1')), '삭제 사유를 적어');
select remove_link(pg_temp.id('u1'), '광고 링크');
select t.fails('감독관: 내 링크(운영진) 거부', format('select remove_link(%s, %L)', pg_temp.id('mod'), 'x'), '운영진이 올린 링크는 운영자만');
select t.fails('감독관: 다른 감독관 링크 거부', format('select remove_link(%s, %L)', pg_temp.id('mod2'), 'x'), '운영진이 올린 링크는 운영자만');
select t.fails('감독관: 운영자 링크 거부', format('select remove_link(%s, %L)', pg_temp.id('op'), 'x'), '운영진이 올린 링크는 운영자만');
select t.fails('감독관: 없는 링크', 'select remove_link(999999, ''x'')', '링크를 찾지 못했습니다');
select t.fails('감독관: 신고 목록은 운영자만', 'select admin_link_reports()', '운영자만');
select t.fails('감독관: 신고 기각은 운영자만', format('select dismiss_link_reports(%s, null)', pg_temp.id('u2')), '운영자만');
select t.fails('감독관: 허용 사이트 빼기는 운영자만', $$select admin_remove_link_domain('x.com', 'x')$$, '운영자만');
reset role;
select t.ok('감독관 삭제: 링크와 그 신고 줄이 사라짐', not exists (select 1 from ext_links where id = pg_temp.id('u1'))
  and not exists (select 1 from link_reports));
select t.ok('감독관 삭제: 올린 장인에게 link_removed (사유)', exists (select 1 from notifications where user_id = :'U' and kind = 'link_removed'
  and message = '프로필에 올린 링크가 운영 원칙에 따라 삭제됐습니다. 사유: 광고 링크'));
select t.ok('감독관 삭제: 처리 기록에 감독관으로', exists (select 1 from moderation_log where action = 'remove_link' and target_kind = 'link'
  and target_id = pg_temp.id('u1')::text and actor_role = 'moderator' and actor_nickname = '감독' and note like 'https://youtube.com/@u1%광고 링크'));
select t.ok('거부된 삭제는 아무것도 바꾸지 않음', (select count(*) = 5 from ext_links) and (select count(*) = 1 from moderation_log)
  and (select count(*) = 1 from notifications where kind = 'link_removed'));

-- ===== 2. 일반 회원 / 비로그인 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails('일반 회원 거부', format('select remove_link(%s, %L)', pg_temp.id('u2'), 'x'), '운영자만');
set request.jwt.claim.sub = :'U';
select t.fails('장인 본인도 이 함수로는 거부 (본인은 링크 관리에서 지움)', format('select remove_link(%s, %L)', pg_temp.id('u2'), 'x'), '운영자만');
reset role;
set role anon;
select t.fails('비로그인 거부', format('select remove_link(%s, %L)', pg_temp.id('u2'), 'x'), 'permission denied');
reset role;

-- ===== 3. 운영자 (모드) =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.fails('운영자 모드 꺼짐 거부', format('select remove_link(%s, %L)', pg_temp.id('u2'), 'x'), '운영자만');
select t.fails('운영자 모드 꺼짐: 운영진 링크도 거부', format('select remove_link(%s, %L)', pg_temp.id('mod'), 'x'), '운영자만');
select set_operator_mode(true);
select t.fails('운영자: 사유 필수', format('select remove_link(%s, %L)', pg_temp.id('mod2'), ''), '삭제 사유를 적어');
select remove_link(pg_temp.id('mod2'), '감독관 링크 정리');
select remove_link(pg_temp.id('u2'), '중복');
reset role;
select t.ok('운영자: 감독관 링크도 일반 링크도 삭제, 처리 기록은 운영자로', not exists (select 1 from ext_links where id in (pg_temp.id('mod2'), pg_temp.id('u2')))
  and (select count(*) = 2 from moderation_log where action = 'remove_link' and actor_role = 'admin'));
select t.ok('운영자 삭제: 감독관 장인에게도 알림', exists (select 1 from notifications where user_id = :'MOD2' and kind = 'link_removed'));
select t.ok('남은 링크: U 1 / 감독 1 / 운영자 1', (select count(*) = 3 from ext_links));
