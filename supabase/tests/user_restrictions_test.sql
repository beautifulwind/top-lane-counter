-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 068 활동 제한: 걸기 규칙(운영자만·자기 자신/운영자/감독관 불가·기간·사유·중복), 문장, 본인·운영자만 읽기,
--   제한 중 쓰기 함수 전부 거절(사유·풀리는 시각 문장) + 직접 넣기·사진 올리기·표 트리거(둘째 겹),
--   제한 중에도 되는 일(문의·지우기·팔로우 취소·저장 해제·차단·알림·설정·탈퇴), 남의 일(추천·운영자 숨김·남의 수정)은 막지 않음,
--   해제·기간 만료 뒤 다시 됨, 감독관 지정 거절, 문의 분류 「이의 제기」(운영자만), 탈퇴하면 기록 삭제, 거절된 시도는 데이터를 바꾸지 않음
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-00000000000a'
\set M  '00000000-0000-0000-0000-00000000000b'
\set R  '00000000-0000-0000-0000-00000000000d'
\set V  '00000000-0000-0000-0000-00000000000c'
\set W  '00000000-0000-0000-0000-00000000000e'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'M', 'm@x.com'), (:'R', 'r@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'M';
update public.profiles set nickname = '제한맨', influencer = 'pro', influencer_at = now() where id = :'R';
update public.profiles set nickname = '브이', influencer = 'creator', influencer_at = now() where id = :'V';
update public.profiles set nickname = '더블유' where id = :'W';
update public.xp_rules set value = 0 where key in ('wiki_create_interval', 'build_edit_interval', 'post_interval', 'comment_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
select format('create function pg_temp.doc() returns jsonb language sql immutable as %L', format('select %L::jsonb', :'doc')) as mkdoc \gset
:mkdoc;
-- 문장을 돌려받는 실행 (성공이면 'OK')
create function pg_temp.err(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'OK';
exception when others then
  return sqlerrm;
end $$;
-- 제한 검사가 들어 있는 함수 전부를 null 인자로 부른다 → {함수: 결과 문장}
create function pg_temp.call_all() returns jsonb language plpgsql as $$
declare
  f record;
  res jsonb := '{}';
begin
  for f in
    select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
           format('select public.%I(%s)', p.proname,
             coalesce((select string_agg('null::' || format_type(t, null), ', ' order by o) from unnest(p.proargtypes) with ordinality u(t, o)), '')) as q
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosrc like '%public.assert_can_write()%'
       and has_function_privilege('authenticated', p.oid, 'execute')
  loop
    res := res || jsonb_build_object(f.sig, pg_temp.err(f.q));
  end loop;
  return res;
end $$;
-- 기존 데이터 지문 (빌드·추천·수정 기록·알림·북마크·글·댓글·문서 댓글·팔로우·신고)
create function pg_temp.fp() returns text language sql stable as $$
  select (select count(*) || '/' || coalesce(max(id), 0) || '/' || coalesce(sum(up_count), 0) || '/' || md5(coalesce(string_agg(b::text, '|' order by b.id), '')) from public.builds b)
    || '#' || (select count(*) || '/' || md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')) from public.build_votes v)
    || '#' || (select count(*) || '/' || coalesce(max(id), 0) || '/' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.build_revisions r)
    || '#' || (select count(*) || '/' || coalesce(max(id), 0) || '/' || md5(coalesce(string_agg(n::text, '|' order by n.id), '')) from public.notifications n)
    || '#' || (select count(*) || '/' || md5(coalesce(string_agg(k::text, '|' order by k.user_id::text, k.build_id), '')) from public.build_bookmarks k)
    || '#' || (select count(*) || '/' || md5(coalesce(string_agg(p::text, '|' order by p.id), '')) from public.posts p)
    || '#' || (select count(*) || '/' || md5(coalesce(string_agg(c::text, '|' order by c.id), '')) from public.post_comments c)
    || '#' || (select count(*) || '/' || md5(coalesce(string_agg(d::text, '|' order by d.id), '')) from public.doc_comments d)
    || '#' || (select count(*) from public.influencer_follows) || '#' || (select count(*) from public.reports)
    || '#' || (select count(*) from public.wiki_reports) || '#' || (select count(*) from public.edit_proposals)
    || '#' || (select md5(string_agg(p::text, '|' order by p.id)) from public.profiles p where p.id <> '00000000-0000-0000-0000-00000000000d') $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== 1. 표 / RLS / 권한 =====
select t.ok('표 2개 RLS 켬, 제한 기록은 본인·운영자 읽기 정책 하나, 허용 목록은 정책 없음',
  (select relrowsecurity from pg_class where oid = 'public.user_restrictions'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.restriction_exemptions'::regclass)
  and (select count(*) from pg_policy where polrelid = 'public.user_restrictions'::regclass) = 1
  and (select polcmd from pg_policy where polrelid = 'public.user_restrictions'::regclass) = 'r'
  and (select count(*) from pg_policy where polrelid = 'public.restriction_exemptions'::regclass) = 0);
select t.ok('로그인: 제한 기록은 읽기만, 허용 목록은 아무 권한 없음',
  has_table_privilege('authenticated', 'public.user_restrictions', 'select')
  and not exists (select 1 from unnest(array['insert', 'update', 'delete']) p where has_table_privilege('authenticated', 'public.user_restrictions', p))
  and not exists (select 1 from unnest(array['select', 'insert', 'update', 'delete']) p
                   where has_table_privilege('authenticated', 'public.restriction_exemptions', p) or has_table_privilege('anon', 'public.restriction_exemptions', p))
  and not exists (select 1 from unnest(array['select', 'insert', 'update', 'delete']) p where has_table_privilege('anon', 'public.user_restrictions', p)));
select t.ok('함수 권한: 내부 함수는 아무도, 화면 함수는 로그인만',
  not has_function_privilege('authenticated', 'public.assert_can_write()', 'execute')
  and not has_function_privilege('authenticated', 'public.active_restriction_id(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.restriction_message(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.restriction_guard()', 'execute')
  and has_function_privilege('authenticated', 'public.can_write()', 'execute')
  and has_function_privilege('authenticated', 'public.my_restriction()', 'execute')
  and has_function_privilege('authenticated', 'public.restrict_user(uuid,integer,text)', 'execute')
  and has_function_privilege('authenticated', 'public.lift_restriction(bigint,text)', 'execute')
  and has_function_privilege('authenticated', 'public.admin_member_restrictions(uuid)', 'execute')
  and not exists (select 1 from unnest(array['public.can_write()', 'public.my_restriction()', 'public.restrict_user(uuid,integer,text)',
                    'public.lift_restriction(bigint,text)', 'public.admin_member_restrictions(uuid)']) f
                   where has_function_privilege('anon', f::regprocedure, 'execute')));
select t.ok('탈퇴하면 기록 삭제 (대상 cascade), 건·푼 운영자는 set null',
  (select confdeltype from pg_constraint where conrelid = 'public.user_restrictions'::regclass and contype = 'f'
     and conkey = array[(select attnum from pg_attribute where attrelid = 'public.user_restrictions'::regclass and attname = 'user_id')]) = 'c'
  and (select count(*) from pg_constraint where conrelid = 'public.user_restrictions'::regclass and contype = 'f' and confdeltype = 'n') = 2);

-- ===== 2. 준비: 제한 전에 R·V가 쓴 것 =====
set role authenticated;
set request.jwt.claim.sub = :'R';
select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc()) as m \gset
insert into ids values ('m1', (:'m'::jsonb ->> 'counter_id')::bigint), ('bR', (:'m'::jsonb ->> 'build_id')::bigint);
insert into ids values ('pR', create_post('제한맨 글', '본문'));
insert into ids values ('pR2', create_post('제한맨 둘째 글', '본문'));
set request.jwt.claim.sub = :'V';
insert into ids values ('bV', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3071']) || pg_temp.doc()));
insert into ids values ('pV', create_post('브이 글', '본문'));
insert into ids values ('cV', create_comment(pg_temp.id('pV'), '브이 댓글'));
insert into ids values ('dV', create_doc_comment(pg_temp.id('m1'), '브이 문서 댓글'));
set request.jwt.claim.sub = :'R';
insert into ids values ('cR', create_comment(pg_temp.id('pV'), '제한맨 댓글'));
insert into ids values ('dR', create_doc_comment(pg_temp.id('m1'), '제한맨 문서 댓글'));
select follow_influencer(:'V') \gset
select save_build(pg_temp.id('bV')) \gset
insert into ids values ('q0', create_inquiry('bug', '제한 전에 보낸 문의입니다.'));
reset role;

-- ===== 3. 걸기 규칙 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails('운영자가 아니면 못 건다', format($$select restrict_user(%L, 7, '사유')$$, :'R'), '운영자만 할 수 있습니다');
select t.fails('운영자가 아니면 기록도 못 본다', format($$select admin_member_restrictions(%L)$$, :'R'), '운영자만 할 수 있습니다');
select t.fails('표에 직접 넣기 불가', format($$insert into user_restrictions (user_id, reason, days, ends_at) values (%L, 'x', 1, now() + interval '1 day')$$, :'R'), 'permission denied');
set request.jwt.claim.sub = :'OP';
select t.fails('자기 자신 불가', format($$select restrict_user(%L, 7, '사유')$$, :'OP'), '자기 자신에게는 활동 제한을 걸 수 없습니다');
select t.fails('감독관 불가', format($$select restrict_user(%L, 7, '사유')$$, :'M'), '감독관에게는 활동 제한을 걸 수 없습니다');
select t.fails('없는 회원', $$select restrict_user('00000000-0000-0000-0000-0000000000ff', 7, '사유')$$, '회원을 찾지 못했습니다');
select t.fails('0일 불가', format($$select restrict_user(%L, 0, '사유')$$, :'R'), '기간은 1일부터 365일까지');
select t.fails('366일 불가', format($$select restrict_user(%L, 366, '사유')$$, :'R'), '기간은 1일부터 365일까지');
select t.fails('기간 없음 불가', format($$select restrict_user(%L, null, '사유')$$, :'R'), '기간은 1일부터 365일까지');
select t.fails('사유 없음 불가', format($$select restrict_user(%L, 7, '   ')$$, :'R'), '제한 사유를 적어 주세요');
select t.fails('사유 501자 불가', format($$select restrict_user(%L, 7, repeat('가', 501))$$, :'R'), '500자까지');
select restrict_user(:'R', 7, '  욕설 반복  ') as rs \gset
insert into ids values ('r1', (:'rs'::jsonb ->> 'id')::bigint);
select t.fails('이미 걸려 있으면 새로 못 건다', format($$select restrict_user(%L, 3, '또')$$, :'R'), '이미 활동 제한 중입니다');
select t.fails('제한 중인 사람은 감독관 지정 불가', format($$select set_moderator(%L, true, '메모')$$, :'R'), '활동이 제한된 회원은 감독관으로 지정할 수 없습니다');
reset role;
select t.ok('기록: 사유 앞뒤 공백 지움, 7일, 풀리는 시각 = 시작 + 7일을 분 단위로 올림, 건 사람 = 운영자',
  (select reason = '욕설 반복' and days = 7 and created_by = :'OP' and lifted_at is null
          and ends_at = date_trunc('minute', starts_at + interval '7 days') + interval '1 minute'
     from public.user_restrictions where id = pg_temp.id('r1')));
select t.ok('처리 기록에는 기간만 (사유 없음)', exists (select 1 from public.moderation_log
  where action = 'restrict_user' and target_id = :'R' and note = '7일' and target_nickname = '제한맨'));
select t.ok('R은 감독관이 되지 않았다', (select role from public.profiles where id = :'R') = 'user');
select pg_temp.fp() as fp0 \gset

-- ===== 4. 본인·운영자만 읽기, 문장 =====
set role authenticated;
set request.jwt.claim.sub = :'R';
select to_char(ends_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') as until from user_restrictions where id = pg_temp.id('r1') \gset
select t.ok('본인은 자기 기록을 읽는다', (select count(*) from user_restrictions) = 1);
select t.ok('내 제한 문장', my_restriction() ->> 'message' = '활동이 제한된 상태입니다. ' || :'until' || '에 풀립니다. 사유: 욕설 반복'
  and my_restriction() ->> 'reason' = '욕설 반복' and (my_restriction() ->> 'id')::bigint = pg_temp.id('r1'));
select t.ok('can_write() = false', not can_write());
set request.jwt.claim.sub = :'V';
select t.ok('다른 사람은 못 읽음', (select count(*) from user_restrictions) = 0 and my_restriction() is null and can_write());
set request.jwt.claim.sub = :'M';
select t.ok('감독관도 못 읽음', (select count(*) from user_restrictions) = 0);
set request.jwt.claim.sub = :'OP';
select t.ok('운영자는 읽음 + 회원 기록 목록', (select count(*) from user_restrictions) = 1
  and admin_member_restrictions(:'R') -> 0 @> jsonb_build_object('id', pg_temp.id('r1'), 'reason', '욕설 반복', 'days', 7, 'created_by', '영자', 'state', 'active'));
reset role;

-- ===== 5. 제한 중: 쓰기 함수 전부 거절 (검사가 든 함수를 DB에서 뽑아 null 인자로 - 입력 검사보다 먼저 막히는지) =====
set role authenticated;
set request.jwt.claim.sub = :'R';
select pg_temp.call_all() as all1 \gset
reset role;
select t.ok('검사가 든 쓰기 함수 29개', (select count(*) from jsonb_object_keys(:'all1'::jsonb)) = 29);
select t.ok('29개 모두 「활동이 제한된 상태입니다. …에 풀립니다. 사유: 욕설 반복」으로 거절',
  not exists (select 1 from jsonb_each_text(:'all1'::jsonb) e
               where e.value <> '활동이 제한된 상태입니다. ' || :'until' || '에 풀립니다. 사유: 욕설 반복'));
-- 올바른 입력으로도
set role authenticated;
set request.jwt.claim.sub = :'R';
select t.fails('글쓰기', $$select create_post('제목', '본문')$$, '활동이 제한된 상태입니다');
select t.fails('댓글', format($$select create_comment(%s, '댓글')$$, pg_temp.id('pV')), '활동이 제한된 상태입니다');
select t.fails('답글', format($$select create_comment(%s, '답글', null, %s)$$, pg_temp.id('pV'), pg_temp.id('cV')), '활동이 제한된 상태입니다');
select t.fails('문서 댓글', format($$select create_doc_comment(%s, '댓글')$$, pg_temp.id('m1')), '활동이 제한된 상태입니다');
select t.fails('글 고치기', format($$select edit_post(%s, '새 제목', '새 본문')$$, pg_temp.id('pR')), '활동이 제한된 상태입니다');
select t.fails('댓글 고치기', format($$select edit_comment(%s, '고침')$$, pg_temp.id('cR')), '활동이 제한된 상태입니다');
select t.fails('문서 댓글 고치기', format($$select edit_doc_comment(%s, '고침')$$, pg_temp.id('dR')), '활동이 제한된 상태입니다');
select t.fails('빌드 등록', format($$select create_build(%s, %L::jsonb)$$, pg_temp.id('m1'), t.build(array['6631','3047','3075']) || pg_temp.doc()), '활동이 제한된 상태입니다');
select t.fails('상대법 등록', format($$select create_matchup('Darius', 'Teemo', %L::jsonb)$$, t.build() || pg_temp.doc()), '활동이 제한된 상태입니다');
select t.fails('내 빌드 수정', format($$select edit_build(%s, %s, %L::jsonb)$$, pg_temp.id('bR'), t.bv(pg_temp.id('bR')), t.build(array['6631','3047','3068']) || pg_temp.doc()), '활동이 제한된 상태입니다');
select t.fails('남의 빌드 수정', format($$select edit_build(%s, %s, %L::jsonb)$$, pg_temp.id('bV'), t.bv(pg_temp.id('bV')), t.build(array['6631','3047','3068']) || pg_temp.doc()), '활동이 제한된 상태입니다');
select t.fails('빌드 추천', format($$select vote_build(%s, 1::smallint)$$, pg_temp.id('bV')), '활동이 제한된 상태입니다');
select t.fails('글 추천', format($$select vote_post(%s)$$, pg_temp.id('pV')), '활동이 제한된 상태입니다');
select t.fails('글 신고', format($$select report_post(%s, 'spam')$$, pg_temp.id('pV')), '활동이 제한된 상태입니다');
select t.fails('댓글 신고', format($$select report_comment(%s, 'spam')$$, pg_temp.id('cV')), '활동이 제한된 상태입니다');
select t.fails('문서 댓글 신고', format($$select report_doc_comment(%s, 'spam')$$, pg_temp.id('dV')), '활동이 제한된 상태입니다');
select t.fails('오류 신고', format($$select report_wiki(%s, %s, 'wrong')$$, pg_temp.id('m1'), pg_temp.id('bV')), '활동이 제한된 상태입니다');
select t.fails('팔로우', format($$select follow_influencer(%L)$$, :'V'), '활동이 제한된 상태입니다');
select t.fails('빌드 저장', format($$select save_build(%s)$$, pg_temp.id('bR')), '활동이 제한된 상태입니다');
select t.fails('장인 링크', format($$select set_build_link(%s, 'https://youtube.com/@r')$$, pg_temp.id('bR')), '활동이 제한된 상태입니다');
select t.fails('장인 프로필 링크', $$select set_profile_links(array['https://youtube.com/@r'])$$, '활동이 제한된 상태입니다');
select t.fails('프로필 사진', format($$select set_profile_photo(%L)$$, :'R' || '/p.webp'), '활동이 제한된 상태입니다');
-- 직접 넣기·고치기 (RLS 정책 경로) - 표 트리거가 한국어 문장으로 먼저 막는다
select t.fails('제안 직접 넣기', format($$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content)
  values ('new_counter', 'Darius', 'Teemo', %L, '{}'::jsonb)$$, :'R'), '활동이 제한된 상태입니다');
select t.fails('빌드 직접 넣기', format($$insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, patch)
  select counter_id, %L, runes, summoner_spells, starting_items, core_items, patch from builds where id = %s$$, :'R', pg_temp.id('bR')), '활동이 제한된 상태입니다');
select t.fails('닉네임 바꾸기 (직접 고치기)', $$update profiles set nickname = '새이름' where id = auth.uid()$$, '활동이 제한된 상태입니다');
select t.ok('사진 올리기 사전 검사 2개가 제한 문장', media_upload_problem() = '활동이 제한된 상태입니다. ' || :'until' || '에 풀립니다. 사유: 욕설 반복'
  and profile_photo_upload_problem() = '활동이 제한된 상태입니다. ' || :'until' || '에 풀립니다. 사유: 욕설 반복');
select t.fails('Storage 올리기도 정책이 막음 (게시판 사진)',
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata) values ('board-media', '%s/a.webp', '%s', '{}')$$, :'R', :'R'), 'row-level security');
select t.fails('Storage 올리기도 정책이 막음 (프로필 사진)',
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata) values ('profile-photos', '%s/a.webp', '%s', '{}')$$, :'R', :'R'), 'row-level security');
reset role;
select t.ok('거절된 시도는 데이터를 하나도 바꾸지 않음 (빌드·추천·수정 기록·알림·북마크·글·댓글·문서 댓글·팔로우·신고·제안·프로필)', pg_temp.fp() = :'fp0');

-- 둘째 겹: 검사를 빠뜨린 함수가 있어도 표 트리거가 막는다 (검사용 가짜 함수)
create function pg_temp.leak_post() returns void language sql security definer as $$
  insert into public.posts (author_id, title, body) values (auth.uid(), '샌 글', '본문') $$;
create function pg_temp.leak_vote(p bigint) returns void language sql security definer as $$
  insert into public.build_votes (build_id, user_id, value) values (p, auth.uid(), 1) $$;
create function pg_temp.leak_follow(p uuid) returns void language sql security definer as $$
  insert into public.influencer_follows (follower_id, influencer_id) values (auth.uid(), p) $$;
create function pg_temp.leak_edit(p bigint) returns void language sql security definer as $$
  update public.posts set body = '몰래 고침' where id = p $$;
grant execute on all functions in schema pg_temp to authenticated;
set role authenticated;
set request.jwt.claim.sub = :'R';
select t.fails('둘째 겹: 글 넣기', 'select pg_temp.leak_post()', '활동이 제한된 상태입니다');
select t.fails('둘째 겹: 추천 넣기', format('select pg_temp.leak_vote(%s)', pg_temp.id('bV')), '활동이 제한된 상태입니다');
select t.fails('둘째 겹: 팔로우 넣기', format('select pg_temp.leak_follow(%L)', :'W'), '활동이 제한된 상태입니다');
select t.fails('둘째 겹: 글 내용 고치기', format('select pg_temp.leak_edit(%s)', pg_temp.id('pR')), '활동이 제한된 상태입니다');
reset role;

-- ===== 6. 제한 중에도 되는 일 =====
set role authenticated;
set request.jwt.claim.sub = :'R';
select t.ok('읽기 (게시판 목록)', (board_page(null, 1, 20) ->> 'total')::int >= 1);
select t.ok('로그인 시각 기록', pg_temp.err('select touch_last_seen()') = 'OK');
insert into ids values ('qA', create_inquiry('appeal', '제한 사유에 이의가 있습니다.'));
select t.ok('문의하기 보내기 (이의 제기 분류)', (select category from inquiries where id = pg_temp.id('qA')) = 'appeal');
select t.ok('내 문의 지우기', pg_temp.err(format('select delete_my_inquiry(%s)', pg_temp.id('q0'))) = 'OK');
select t.ok('내 글 지우기', pg_temp.err(format('select delete_my_post(%s)', pg_temp.id('pR2'))) = 'OK');
select t.ok('내 댓글 지우기', pg_temp.err(format('select delete_my_comment(%s)', pg_temp.id('cR'))) = 'OK');
select t.ok('내 문서 댓글 지우기', pg_temp.err(format('select delete_my_doc_comment(%s)', pg_temp.id('dR'))) = 'OK');
select t.ok('팔로우 취소', pg_temp.err(format('select unfollow_influencer(%L)', :'V')) = 'OK');
select t.ok('팔로우 취소됨', follow_status(array[:'V'::uuid]) = jsonb_build_object(:'V', false));
select t.ok('빌드 저장 해제', (unsave_build(pg_temp.id('bV')) ->> 'saved')::boolean = false);
select t.ok('차단', pg_temp.err(format('insert into user_blocks (blocker_id, blocked_id) values (%L, %L)', :'R', :'W')) = 'OK');
select t.ok('차단 해제', pg_temp.err(format('delete from user_blocks where blocker_id = %L and blocked_id = %L', :'R', :'W')) = 'OK'
);
select t.ok('차단 해제됨', not exists (select 1 from user_blocks));
select t.ok('알림 모두 읽음', pg_temp.err('select mark_all_notifications_read(null)') = 'OK');
select t.ok('알림 설정 저장', pg_temp.err(format('insert into push_settings (user_id, my_results) values (%L, false)', :'R')) = 'OK');
select t.ok('대표 칭호 빼기 (비우는 것은 됨)', pg_temp.err('update profiles set main_title = null where id = auth.uid()') = 'OK');
select t.ok('사진 지우기', pg_temp.err('select clear_profile_photo()') = 'OK');
reset role;

-- ===== 7. 남의 일은 막지 않는다 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.ok('다른 사람이 제한된 사람의 빌드에 추천', (vote_build(pg_temp.id('bR'), 1::smallint) ->> 'up')::int = 1);
select t.ok('다른 사람이 제한된 사람의 빌드를 수정', pg_temp.err(format($$select edit_build(%s, %s, %L::jsonb)$$, pg_temp.id('bR'), t.bv(pg_temp.id('bR')),
  t.build(array['6631','3047','3068']) || pg_temp.doc())) = 'OK');
select t.ok('다른 사람이 제한된 사람의 글에 댓글', pg_temp.err(format($$select create_comment(%s, '댓글')$$, pg_temp.id('pR'))) = 'OK');
set request.jwt.claim.sub = :'OP';
select t.ok('운영자가 제한된 사람의 빌드를 숨김', pg_temp.err(format($$select hide_build(%s, '검사')$$, pg_temp.id('bR'))) = 'OK');
select t.ok('운영자가 제한된 사람의 빌드를 다시 공개', pg_temp.err(format($$select restore_build(%s, '검사')$$, pg_temp.id('bR'))) = 'OK');
select t.ok('운영자가 제한된 사람의 글을 숨김', pg_temp.err(format($$select hide_post(%s, '검사')$$, pg_temp.id('pR'))) = 'OK');
reset role;
select t.ok('추천 받은 제한된 작성자의 빌드 점수도 올라감', (select up_count from builds where id = pg_temp.id('bR')) = 1);

-- ===== 8. 문의 분류 「이의 제기」: 운영자만 =====
select t.ok('운영자에게만 새 문의 알림 (감독관 없음)',
  exists (select 1 from public.notifications where user_id = :'OP' and kind = 'inquiry_received' and message = '새 문의가 들어왔습니다. (분류: 이의 제기)')
  and not exists (select 1 from public.notifications where user_id = :'M' and message like '%이의 제기%'));
set role authenticated;
set request.jwt.claim.sub = :'M';
select t.ok('감독관은 이의 제기 문의를 못 읽음', not exists (select 1 from inquiries where id = pg_temp.id('qA')));
select t.fails('감독관은 이의 제기에 답변 불가', format($$select answer_inquiry(%s, '답')$$, pg_temp.id('qA')), '"이의 제기" 문의는 운영자만 답변할 수 있습니다');
set request.jwt.claim.sub = :'OP';
select t.ok('운영자는 읽고 답변', exists (select 1 from inquiries where id = pg_temp.id('qA'))
  and pg_temp.err(format($$select answer_inquiry(%s, '확인했습니다.')$$, pg_temp.id('qA'))) = 'OK');
set request.jwt.claim.sub = :'W';
insert into ids values ('qW', create_inquiry('other', '분류를 옮길 문의입니다.'));
set request.jwt.claim.sub = :'OP';
select t.ok('운영자는 다른 분류 → 이의 제기로 옮길 수 있음', pg_temp.err(format($$select set_inquiry_category(%s, 'appeal')$$, pg_temp.id('qW'))) = 'OK');
select t.ok('이의 제기 → 다른 분류로 옮기면 감독관에게 알림', pg_temp.err(format($$select set_inquiry_category(%s, 'bug')$$, pg_temp.id('qW'))) = 'OK');
reset role;
select t.ok('답변 알림 문장에 분류 이름', exists (select 1 from public.notifications where user_id = :'R' and message = '"이의 제기" 문의에 답변이 도착했습니다.'));
select t.ok('감독관 알림: 기타로 들어올 때 1 + 이의 제기에서 오류 신고로 옮길 때 1 (제한 전 문의 1 포함 3), 이의 제기 알림은 없음',
  (select count(*) from public.notifications where user_id = :'M' and kind = 'inquiry_received') = 3
  and (select count(*) from public.notifications where user_id = :'M' and message = '새 문의가 들어왔습니다. (분류: 오류 신고)') = 2
  and not exists (select 1 from public.notifications where user_id = :'M' and message like '%이의 제기%'));
select t.fails('없는 분류는 거부', format($$select create_inquiry('nope', '내용입니다 다섯자')$$), '분류');

-- ===== 9. 운영자 해제 → 다시 됨 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails('운영자가 아니면 해제 불가', format($$select lift_restriction(%s, null)$$, pg_temp.id('r1')), '운영자만 할 수 있습니다');
set request.jwt.claim.sub = :'OP';
select t.fails('해제 메모 501자 불가', format($$select lift_restriction(%s, repeat('가', 501))$$, pg_temp.id('r1')), '500자까지');
select t.ok('해제', pg_temp.err(format($$select lift_restriction(%s, '이의 제기 받아들임')$$, pg_temp.id('r1'))) = 'OK');
select t.fails('다시 해제 불가', format($$select lift_restriction(%s, null)$$, pg_temp.id('r1')), '이미 해제된 제한입니다');
select t.fails('없는 기록', 'select lift_restriction(999999, null)', '제한 기록을 찾지 못했습니다');
select t.ok('기록: 푼 사람·메모·상태 lifted', admin_member_restrictions(:'R') -> 0
  @> '{"state":"lifted","lifted_by":"영자","lift_note":"이의 제기 받아들임"}'::jsonb);
reset role;
select t.ok('해제 처리 기록', exists (select 1 from public.moderation_log where action = 'lift_restriction' and target_id = :'R' and note is null));
set role authenticated;
set request.jwt.claim.sub = :'R';
select pg_temp.call_all() as all2 \gset
select t.ok('해제 뒤: 29개 모두 제한 문장 없음 (다음 검사로 넘어감)', not exists (select 1 from jsonb_each_text(:'all2'::jsonb) e where e.value like '%활동이 제한된%'));
select t.ok('해제 뒤 my_restriction() = null, can_write()', my_restriction() is null and can_write());
select t.ok('해제 뒤 글쓰기', pg_temp.err($$select create_post('다시 쓴 글', '본문')$$) = 'OK');
select t.ok('해제 뒤 문서 댓글', pg_temp.err(format($$select create_doc_comment(%s, '다시 쓴 댓글')$$, pg_temp.id('m1'))) = 'OK');
select t.ok('해제 뒤 빌드 추천', (vote_build(pg_temp.id('bV'), 1::smallint) ->> 'up')::int = 1);
select t.ok('해제 뒤 빌드 수정', pg_temp.err(format($$select edit_build(%s, %s, %L::jsonb)$$, pg_temp.id('bR'), t.bv(pg_temp.id('bR')),
  t.build(array['6631','3047','3075']) || pg_temp.doc())) = 'OK');
select t.ok('해제 뒤 저장', (save_build(pg_temp.id('bV')) ->> 'saved')::boolean);
select t.ok('해제 뒤 팔로우', pg_temp.err(format('select follow_influencer(%L)', :'V')) = 'OK');
select t.ok('해제 뒤 신고', pg_temp.err(format($$select report_post(%s, 'spam')$$, pg_temp.id('pV'))) = 'OK');
select t.ok('해제 뒤 장인 링크', pg_temp.err($$select set_profile_links(array['https://youtube.com/@r'])$$) = 'OK');
select t.ok('해제 뒤 제안 직접 넣기 (정책 can_write)', pg_temp.err(format($$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content)
  values ('new_counter', 'Kennen', 'Teemo', %L, '{"summary":"s","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'::jsonb)$$, :'R')) not like '%제한%');
select t.ok('해제 뒤 사진 올리기 검사 통과', media_upload_problem() is null);
reset role;

-- ===== 10. 기간이 지나면 저절로 풀림 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select (restrict_user(:'R', 1, '두 번째') ->> 'id')::bigint as r2 \gset
reset role;
set role authenticated;
set request.jwt.claim.sub = :'R';
select t.fails('다시 걸면 다시 막힘', $$select create_post('제목', '본문')$$, '사유: 두 번째');
reset role;
update public.user_restrictions set starts_at = now() - interval '1 day', ends_at = now() - interval '1 second' where id = :r2;  -- 시간이 흐른 셈
set role authenticated;
set request.jwt.claim.sub = :'R';
select pg_temp.call_all() as all3 \gset
select t.ok('기간이 지나면 29개 모두 제한 문장 없음', not exists (select 1 from jsonb_each_text(:'all3'::jsonb) e where e.value like '%활동이 제한된%'));
select t.ok('기간이 지나면 글쓰기', pg_temp.err($$select create_post('만료 뒤 글', '본문')$$) = 'OK');
set request.jwt.claim.sub = :'OP';
select t.fails('기간이 지난 제한은 해제할 것이 없음', format('select lift_restriction(%s, null)', :r2), '이미 기간이 끝나 풀린 제한입니다');
select t.ok('기록 상태 ended, 최근 것부터', admin_member_restrictions(:'R') -> 0 ->> 'state' = 'ended'
  and admin_member_restrictions(:'R') -> 1 ->> 'state' = 'lifted' and jsonb_array_length(admin_member_restrictions(:'R')) = 2);
select t.ok('기간이 지나면 새로 걸 수 있음', pg_temp.err(format($$select restrict_user(%L, 30, '세 번째')$$, :'R')) = 'OK');
select t.ok('제한이 없는 사람은 감독관 지정 (W)', pg_temp.err(format($$select set_moderator(%L, true, '메모')$$, :'W')) = 'OK');
select t.ok('감독관 해제 (W)', pg_temp.err(format($$select set_moderator(%L, false, '메모')$$, :'W')) = 'OK');
reset role;

-- ===== 11. 탈퇴: 제한 중에도 되고, 기록이 지워진다 =====
select t.ok('탈퇴 전 R의 기록 3개', (select count(*) from public.user_restrictions where user_id = :'R') = 3);
set role authenticated;
set request.jwt.claim.sub = :'R';
select t.ok('제한 중에도 탈퇴(계정 삭제) 가능', pg_temp.err($$select delete_my_account('제한맨')$$) not like '%제한%');
reset role;
select t.ok('탈퇴됨', not exists (select 1 from public.profiles where id = :'R'));
select t.ok('탈퇴하면 제한 기록 삭제', (select count(*) from public.user_restrictions where user_id = :'R') = 0
  and (select count(*) from public.user_restrictions) = 0);
select t.ok('처리 기록은 대상 칸만 비움 (055 규칙 그대로)', not exists (select 1 from public.moderation_log where target_id = :'R')
  and (select count(*) from public.moderation_log where action in ('restrict_user', 'lift_restriction') and target_nickname = '탈퇴한 이용자') = 4);
