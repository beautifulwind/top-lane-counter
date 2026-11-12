-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 047: 장인 외부 링크 + 공개 프로필 (주소 검사/허용 사이트/프로필 링크/빌드 링크/공개 범위/신고/삭제/해제/탈퇴)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set GU  '00000000-0000-0000-0000-000000000010'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '장인유저', influencer = 'creator', influencer_at = now() where id = :'U';
update public.profiles set nickname = '보통' where id = :'V';
update public.profiles set nickname = '장인둘', influencer = 'pro', influencer_at = now() where id = :'W';
update public.profiles set nickname = '손님' where id = :'GU';
delete from notifications;
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
-- 퀸 빌드 2개 중 하나를 U가 처음 만든 빌드로 (fixtures는 작성자 없음)
insert into ids select 'b1', min(id) from builds;
insert into ids select 'b2', max(id) from builds;
insert into ids select 'c1', counter_id from builds where id = pg_temp.id('b1');
update builds set author_id = :'U' where id = pg_temp.id('b1');
update builds set author_id = :'W' where id = pg_temp.id('b2');
create temp table snap as select id, to_jsonb(b) as j from builds b;

-- ===== 1. 허용 사이트 =====
select t.ok('허용 사이트 9개', (select count(*) = 9 from link_domains)
  and (select array_agg(domain order by domain) from link_domains)
      = array['afreecatv.com', 'chzzk.naver.com', 'instagram.com', 'sooplive.co.kr', 'twitch.tv', 'twitter.com', 'x.com', 'youtu.be', 'youtube.com']);
set role anon;
select t.ok('비로그인도 허용 사이트를 읽음', (select count(*) = 9 from public.link_domains));
select t.fails('비로그인은 링크 표를 못 읽음', 'select * from public.ext_links', 'permission denied');
select t.fails('비로그인은 신고 표를 못 읽음', 'select * from public.link_reports', 'permission denied');
reset role;

-- ===== 2. 주소 검사 =====
select t.ok('정리: 사이트 이름 소문자, 하위 도메인 허용',
  ext_link_parse('HTTPS://WWW.YouTube.com/@Faker') = array['https://www.youtube.com/@Faker', 'www.youtube.com']
  and (ext_link_parse('https://youtu.be/abc?t=10'))[2] = 'youtu.be'
  and (ext_link_parse('https://m.twitch.tv/faker'))[2] = 'm.twitch.tv'
  and (ext_link_parse('https://chzzk.naver.com/live/abc'))[2] = 'chzzk.naver.com'
  and (ext_link_parse('https://www.instagram.com/p/x%20y/'))[2] = 'www.instagram.com');
select t.fails('http 거부', $$select ext_link_parse('http://youtube.com/@a')$$, 'https://로 시작하는');
select t.fails('javascript: 거부', $$select ext_link_parse('javascript:alert(1)')$$, 'https://로 시작하는');
select t.fails('빈 주소', $$select ext_link_parse('  ')$$, '링크 주소를 적어');
select t.fails('300자 넘음', format('select ext_link_parse(%L)', 'https://youtube.com/' || repeat('a', 290)), '300자 이하');
select t.fails('띄어쓰기', $$select ext_link_parse('https://youtube.com/@a b')$$, '쓸 수 없는 글자');
select t.fails('한글', $$select ext_link_parse('https://youtube.com/@장인')$$, '쓸 수 없는 글자');
select t.fails(E'보이지 않는 글자 U+200B', format('select ext_link_parse(%L)', E'https://youtube.com/@a\u200Bb'), '쓸 수 없는 글자');
select t.fails(E'줄 바꿈 글자 U+2028', format('select ext_link_parse(%L)', E'https://youtube.com/@a\u2028'), '쓸 수 없는 글자');
select t.fails(E'전각 글자 사이트 이름', format('select ext_link_parse(%L)', E'https://\uFF59outube.com/@a'), '쓸 수 없는 글자');
select t.fails('따옴표/꺾쇠', $$select ext_link_parse('https://youtube.com/"><script>')$$, '쓸 수 없는 글자');
select t.fails('백슬래시', $$select ext_link_parse('https://youtube.com\@evil.com')$$, '쓸 수 없는 글자');
select t.fails('%00 제어 문자', $$select ext_link_parse('https://youtube.com/a%00b')$$, '쓸 수 없는 글자');
select t.fails('% 뒤 16진수 아님', $$select ext_link_parse('https://youtube.com/a%zz')$$, '쓸 수 없는 글자');
select t.fails('계정 정보 user@', $$select ext_link_parse('https://youtube.com@evil.com/x')$$, '계정 정보');
select t.fails('계정 정보 user:pw@', $$select ext_link_parse('https://a:b@youtube.com/x')$$, '계정 정보');
select t.fails('포트', $$select ext_link_parse('https://youtube.com:8443/x')$$, '포트 번호');
select t.fails('IP 주소', $$select ext_link_parse('https://1.2.3.4/x')$$, '사이트 이름이 올바르지');
select t.fails('xn-- 사이트 이름', $$select ext_link_parse('https://xn--yutube-wqf.youtube.com/x')$$, '사이트 이름이 올바르지');
select t.fails('끝에 점', $$select ext_link_parse('https://youtube.com./x')$$, '사이트 이름이 올바르지');
select t.fails('허용 안 된 사이트', $$select ext_link_parse('https://evil.com/youtube.com')$$, '허용된 사이트의 주소만');
select t.fails('허용 사이트처럼 보이는 다른 사이트', $$select ext_link_parse('https://youtube.com.evil.com/x')$$, '허용된 사이트의 주소만');
select t.fails('이름에 허용 사이트가 붙은 다른 사이트', $$select ext_link_parse('https://notyoutube.com/x')$$, '허용된 사이트의 주소만');
select t.fails('단축 주소 사이트', $$select ext_link_parse('https://bit.ly/abc')$$, '허용된 사이트의 주소만');
select t.fails('넘기기 하위 사이트 l.instagram.com', $$select ext_link_parse('https://l.instagram.com/?u=x')$$, '단축/우회 주소');
select t.fails('넘기기 경로 /redirect', $$select ext_link_parse('https://www.youtube.com/redirect?q=evil')$$, '단축/우회 주소');
select t.fails('주소 안의 다른 주소', $$select ext_link_parse('https://www.youtube.com/watch?v=a&next=https://evil.com')$$, '단축/우회 주소');
select t.fails('주소 안의 다른 주소 (인코딩)', $$select ext_link_parse('https://www.youtube.com/watch?u=https%3A%2F%2Fevil.com')$$, '단축/우회 주소');

-- ===== 3. 프로필 링크 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails('장인이 아니면 프로필 링크 불가', $$select set_profile_links(array['https://youtube.com/@v'])$$, '인증된 장인만');
select t.fails('장인이 아니면 빌드 링크 불가', format('select set_build_link(%s, %L)', pg_temp.id('b1'), 'https://youtube.com/@v'), '인증된 장인만');
select t.ok('장인이 아니면 내 링크는 비어 있음', (my_links() ->> 'influencer') is null and jsonb_array_length(my_links() -> 'profile') = 0);
set request.jwt.claim.sub = :'GU';
select t.fails('비회원(닉네임 있음)도 장인이 아니라 불가', $$select set_profile_links(array['https://youtube.com/@g'])$$, '인증된 장인만');
set request.jwt.claim.sub = :'U';
select t.fails('6개는 거부', $$select set_profile_links(array['https://youtube.com/@1', 'https://youtube.com/@2', 'https://youtube.com/@3',
  'https://youtube.com/@4', 'https://youtube.com/@5', 'https://youtube.com/@6'])$$, '5개까지');
select t.fails('같은 주소 두 번', $$select set_profile_links(array['https://youtube.com/@a', 'https://YOUTUBE.com/@a'])$$, '같은 주소를 두 번');
select t.fails('하나라도 틀리면 아무것도 안 바뀜', $$select set_profile_links(array['https://youtube.com/@a', 'https://evil.com/'])$$, '허용된 사이트의 주소만');
select t.ok('그대로 0개', (select count(*) = 0 from ext_links));
select t.ok('5개 올림 (빈 칸은 건너뜀)', jsonb_array_length(set_profile_links(array['https://www.youtube.com/@faker', '', 'https://twitch.tv/faker',
  'https://x.com/faker', 'https://instagram.com/faker', 'https://chzzk.naver.com/faker'])) = 5);
insert into ids select 'yt', id from ext_links where url = 'https://www.youtube.com/@faker';
insert into ids select 'tw', id from ext_links where url = 'https://twitch.tv/faker';
select t.ok('순서 바꾸기/하나 빼기', jsonb_array_length(set_profile_links(array['https://twitch.tv/faker', 'https://www.youtube.com/@faker'])) = 2);
select t.ok('남은 주소는 같은 줄 (순서만 바뀜)', (select sort from ext_links where id = pg_temp.id('tw')) = 0 and (select sort from ext_links where id = pg_temp.id('yt')) = 1
  and (select count(*) from ext_links where owner_id = auth.uid()) = 2);
select t.fails('표에 직접 넣기 불가', $$insert into ext_links (owner_id, url, host) values (auth.uid(), 'https://youtube.com/@x', 'youtube.com')$$, 'permission denied');
select t.fails('표 직접 고치기 불가', $$update ext_links set url = 'https://evil.com/' where owner_id = auth.uid()$$, 'permission denied');
select t.fails('허용 사이트 직접 넣기 불가', $$insert into link_domains (domain, label) values ('evil.com', 'x')$$, 'permission denied');

-- ===== 4. 빌드 링크 (그 장인만, 빌드 내용과 별개) =====
select t.fails('남이 처음 만든 빌드에는 불가', format('select set_build_link(%s, %L)', pg_temp.id('b2'), 'https://youtube.com/watch?v=a'), '내가 처음 만든 빌드에만');
select t.fails('없는 빌드', $$select set_build_link(999999, 'https://youtube.com/watch?v=a')$$, '빌드를 찾지 못했습니다');
select t.ok('내 빌드에 링크', (set_build_link(pg_temp.id('b1'), 'https://youtu.be/abc') ->> 'url') = 'https://youtu.be/abc');
insert into ids select 'bl', id from ext_links where build_id = pg_temp.id('b1');
select t.ok('같은 주소로 다시 저장하면 같은 줄', (set_build_link(pg_temp.id('b1'), 'https://youtu.be/abc') ->> 'id')::bigint = pg_temp.id('bl'));
select t.ok('주소를 바꿈', (set_build_link(pg_temp.id('b1'), 'https://youtu.be/xyz') ->> 'url') = 'https://youtu.be/xyz');
select t.ok('빌드마다 1개 그대로', (select count(*) = 1 from ext_links where build_id = pg_temp.id('b1')));
select t.ok('빈 주소면 null', set_build_link(pg_temp.id('b1'), ' ') is null);
select t.ok('빈 주소면 지움', not exists (select 1 from ext_links where build_id = pg_temp.id('b1')));
select set_build_link(pg_temp.id('b1'), 'https://youtu.be/abc');
update ids set v = (select id from ext_links where build_id = pg_temp.id('b1')) where k = 'bl';
select t.ok('내 링크: 프로필 2 + 빌드 1, 한도 5, 허용 사이트 9', jsonb_array_length(my_links() -> 'profile') = 2
  and jsonb_array_length(my_links() -> 'builds') = 1 and (my_links() ->> 'max')::int = 5 and jsonb_array_length(my_links() -> 'domains') = 9
  and (my_links() -> 'builds' -> 0 ->> 'visible')::boolean);
set request.jwt.claim.sub = :'W';
select t.fails('다른 장인도 남의 빌드에는 불가', format('select set_build_link(%s, %L)', pg_temp.id('b1'), 'https://youtube.com/@w'), '내가 처음 만든 빌드에만');
select set_profile_links(array['https://sooplive.co.kr/w']);
reset role;
select t.ok('빌드 내용(버전/수정 시각/스냅숏)은 그대로', not exists (
  select 1 from builds b join snap s on s.id = b.id where to_jsonb(b) is distinct from s.j));

-- ===== 5. 공개 범위 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.ok('다른 회원은 표를 직접 읽어도 0줄', (select count(*) = 0 from ext_links));
set role anon;
select t.ok('공개 프로필: 장인은 보임 (닉네임/유형/링크 2/빌드 1/빌드 링크)',
  (public_profile(:'U') ->> 'nickname') = '장인유저' and (public_profile(:'U') ->> 'influencer') = 'creator'
  and jsonb_array_length(public_profile(:'U') -> 'links') = 2 and (public_profile(:'U') ->> 'build_count')::int = 1
  and (public_profile(:'U') -> 'builds' -> 0 -> 'link' ->> 'url') = 'https://youtu.be/abc'
  and (public_profile(:'U') -> 'links' -> 0 ->> 'url') = 'https://twitch.tv/faker');
select t.ok('공개 프로필 칸은 이것뿐 (이메일/라이엇/레벨/역할/가입일 없음)',
  (select array_agg(k order by k) from jsonb_object_keys(public_profile(:'U')) k) = array['build_count', 'builds', 'id', 'influencer', 'links', 'nickname']
  and public_profile(:'U')::text not like '%u@x.com%');
select t.ok(E'장인 아님\u00B7없는 id\u00B7모양 틀린 id\u00B7빈 값은 모두 똑같이 null',
  public_profile(:'V') is null and public_profile('00000000-0000-0000-0000-0000000000ff') is null
  and public_profile('abc') is null and public_profile(null) is null and public_profile('') is null and public_profile(:'OP') is null);
select t.ok('상대법 빌드 링크: 공개 빌드의 장인 링크만', (build_links(pg_temp.id('c1')) -> pg_temp.id('b1')::text ->> 'url') = 'https://youtu.be/abc'
  and (select count(*) = 1 from jsonb_object_keys(build_links(pg_temp.id('c1')))));
reset role;
update builds set status = 'hidden', hide_reason = '검사' where id = pg_temp.id('b1');
set role anon;
select t.ok('빌드를 숨기면 빌드 링크/최근 빌드에서 빠짐', build_links(pg_temp.id('c1')) = '{}'::jsonb
  and jsonb_array_length(public_profile(:'U') -> 'builds') = 0 and (public_profile(:'U') ->> 'build_count')::int = 0);
reset role;
update builds set status = 'approved', hide_reason = null where id = pg_temp.id('b1');

-- ===== 6. 신고 (정식 회원) -> 운영자 알림 =====
select t.ok('손님 계정은 비회원', (select is_guest from profiles where id = :'GU'));
set role authenticated;
set request.jwt.claim.sub = :'GU';
select t.fails('비회원은 신고 불가', format('select report_link(%s, %L)', pg_temp.id('yt'), 'spam'), '비회원은 신고할 수 없습니다');
set request.jwt.claim.sub = :'U';
select t.fails('내 링크는 신고 불가', format('select report_link(%s, %L)', pg_temp.id('yt'), 'spam'), '내 링크는 신고할 수 없습니다');
set request.jwt.claim.sub = :'V';
select t.fails('이유 필수', format('select report_link(%s, %L)', pg_temp.id('yt'), 'abuse'), '신고 이유를 골라');
select t.fails('기타는 내용 필수', format('select report_link(%s, %L)', pg_temp.id('yt'), 'other'), '기타 이유를 적어');
select t.fails('없는 링크', $$select report_link(999999, 'spam')$$, '신고할 수 없는 링크');
select report_link(pg_temp.id('yt'), 'not_own', '남의 채널');
select t.fails('같은 링크 두 번', format('select report_link(%s, %L)', pg_temp.id('yt'), 'spam'), '이미 신고한 링크');
select t.fails('신고 표 직접 읽기 불가 (0줄)', $$select 1/(select count(*) from link_reports)::int$$, 'division by zero');
set request.jwt.claim.sub = :'W';
select report_link(pg_temp.id('yt'), 'spam');
reset role;
select t.ok(E'알림: 운영자에게만 한 번 "(외부 링크)" (감독관\u00B7두 번째 신고는 없음)',
  (select count(*) = 1 from notifications where kind = 'report_received' and user_id = :'OP' and message = '새 신고가 들어왔습니다. (외부 링크)')
  and not exists (select 1 from notifications where kind = 'report_received' and user_id <> :'OP'));
select t.ok('푸시 묶음은 그대로 staff_new', push_group('report_received') = 'staff_new' and push_group('link_removed') = 'my_results');

-- ===== 7. 운영자: 목록 / 기각 / 삭제 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관은 링크 신고 목록 불가', 'select admin_link_reports()', '운영자만');
select t.fails('감독관은 링크 삭제 불가', format('select remove_link(%s, %L)', pg_temp.id('yt'), 'x'), '운영자만');
select t.fails('감독관은 기각 불가', format('select dismiss_link_reports(%s, %L)', pg_temp.id('yt'), 'x'), '운영자만');
select t.fails('감독관은 허용 사이트 더하기 불가', $$select admin_add_link_domain('example.com', 'x')$$, '운영자만');
select t.ok('감독관은 링크 표를 읽어도 0줄', (select count(*) = 0 from ext_links));
set request.jwt.claim.sub = :'V';
select t.fails('일반 회원도 링크 삭제 불가', format('select remove_link(%s, %L)', pg_temp.id('yt'), 'x'), '운영자만');
set request.jwt.claim.sub = :'OP';
select t.ok('운영자 목록: 링크 1개 + 신고 2건 + 주인/공개 여부',
  (admin_link_reports() ->> 'total')::int = 1 and jsonb_array_length(admin_link_reports() -> 'links' -> 0 -> 'reports') = 2
  and (admin_link_reports() -> 'links' -> 0 -> 'owner' ->> 'nickname') = '장인유저'
  and (admin_link_reports() -> 'links' -> 0 ->> 'visible')::boolean);
select t.ok('운영자는 링크 표를 모두 읽음', (select count(*) = 4 from ext_links));
select set_operator_mode(false);
select t.fails('운영자 모드를 끄면 불가', 'select admin_link_reports()', '운영자만');
select set_operator_mode(true);
select t.ok('기각: 2건', dismiss_link_reports(pg_temp.id('yt'), '본인 채널 확인') = 2);
select t.fails('처리할 신고 없음', format('select dismiss_link_reports(%s, null)', pg_temp.id('yt')), '처리할 신고가 없습니다');
select t.ok('기각 뒤 목록 0', (admin_link_reports() ->> 'total')::int = 0);
select t.fails('삭제 사유 필수', format('select remove_link(%s, %L)', pg_temp.id('yt'), ' '), '삭제 사유를 적어');
select remove_link(pg_temp.id('yt'), '광고 링크');
select remove_link(pg_temp.id('bl'), '도박 사이트 안내');
select t.fails('없는 링크 삭제', format('select remove_link(%s, %L)', pg_temp.id('yt'), 'x'), '링크를 찾지 못했습니다');
reset role;
select t.ok('삭제: 링크와 그 신고 줄이 사라짐', not exists (select 1 from ext_links where id in (pg_temp.id('yt'), pg_temp.id('bl')))
  and not exists (select 1 from link_reports where link_id = pg_temp.id('yt')));
select t.ok('올린 장인에게 link_removed (프로필/빌드 문장, 사유)',
  exists (select 1 from notifications where user_id = :'U' and kind = 'link_removed' and build_id is null
           and message = '프로필에 올린 링크가 운영 원칙에 따라 삭제됐습니다. 사유: 광고 링크')
  and exists (select 1 from notifications where user_id = :'U' and kind = 'link_removed' and build_id = pg_temp.id('b1')
           and message = '빌드에 올린 링크가 운영 원칙에 따라 삭제됐습니다. 사유: 도박 사이트 안내'));
select t.ok('처리 기록: 기각 1 + 삭제 2 (주소가 메모에)', (select count(*) = 1 from moderation_log where action = 'dismiss_reports' and target_kind = 'link')
  and (select count(*) = 2 from moderation_log where action = 'remove_link' and target_kind = 'link' and target_nickname = '장인유저')
  and exists (select 1 from moderation_log where action = 'remove_link' and note like 'https://www.youtube.com/@faker%광고 링크'));

-- ===== 8. 운영자: 허용 사이트 더하기/빼기 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('더하기: 주소 모양을 정리', admin_add_link_domain('Https://www.Example.com/', '예시') = 'example.com');
select t.fails('이미 있음', $$select admin_add_link_domain('example.com', '예시')$$, '이미 허용된 사이트');
select t.fails('모양 틀림', $$select admin_add_link_domain('exa mple', '예시')$$, '도메인 모양이 올바르지');
select t.fails('이름 필수', $$select admin_add_link_domain('foo.com', ' ')$$, '사이트 이름을 적어');
select t.fails('빼기 사유 필수', $$select admin_remove_link_domain('twitch.tv', '')$$, '빼는 사유를 적어');
select t.fails('없는 사이트 빼기', $$select admin_remove_link_domain('nope.com', 'x')$$, '허용 목록에 없는 사이트');
select t.ok('트위치를 빼면 트위치 링크 1개가 숨겨짐 (지우지 않음)', admin_remove_link_domain('twitch.tv', '정책 변경') = 1
  and exists (select 1 from ext_links where id = pg_temp.id('tw')));
select t.ok('숨긴 링크는 공개 프로필에서 빠지고 내 링크에는 visible false',
  jsonb_array_length(public_profile(:'U') -> 'links') = 0);
set request.jwt.claim.sub = :'U';
select t.ok('내 링크: 숨김 표시', (my_links() -> 'profile' -> 0 ->> 'visible')::boolean = false);
select t.fails('빠진 사이트로 새로 올리기 불가', $$select set_profile_links(array['https://twitch.tv/new'])$$, '허용된 사이트의 주소만');
set request.jwt.claim.sub = :'V';
select t.fails('숨긴 링크는 신고 불가', format('select report_link(%s, %L)', pg_temp.id('tw'), 'spam'), '신고할 수 없는 링크');
set request.jwt.claim.sub = :'OP';
select admin_add_link_domain('twitch.tv', '트위치');
select t.ok('다시 더하면 다시 보임', jsonb_array_length(public_profile(:'U') -> 'links') = 1);
reset role;
select t.ok('처리 기록: 사이트 더하기 2 / 빼기 1', (select count(*) = 2 from moderation_log where action = 'add_link_domain')
  and (select count(*) = 1 from moderation_log where action = 'remove_link_domain' and note like '정책 변경%숨겨진 링크 1개'));

-- ===== 9. 인증 해제 / 탈퇴 / 닉네임 바꾸기 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select set_build_link(pg_temp.id('b1'), 'https://youtu.be/again');
set request.jwt.claim.sub = :'OP';
select admin_set_nickname(:'U', '장인새이름', '요청');
reset role;
select t.ok('운영자가 닉네임을 바꿔도 링크는 그대로', (select count(*) = 2 from ext_links where owner_id = :'U'));
update ids set v = (select id from ext_links where build_id = pg_temp.id('b1')) where k = 'bl';
set role authenticated;
set request.jwt.claim.sub = :'V';
select report_link(pg_temp.id('bl'), 'spam');
set request.jwt.claim.sub = :'OP';
select revoke_influencer(:'U', '기준 미달');
reset role;
select t.ok('인증 해제: 그 장인의 링크(프로필/빌드)와 신고 줄을 바로 지움', not exists (select 1 from ext_links where owner_id = :'U')
  and not exists (select 1 from link_reports));
select t.ok('해제 뒤 공개 프로필은 null', public_profile(:'U') is null);
select t.ok('다른 장인 링크는 그대로', (select count(*) = 1 from ext_links where owner_id = :'W'));
delete from auth.users where id = :'W';
select t.ok('탈퇴: 링크가 함께 지워짐', not exists (select 1 from ext_links));
