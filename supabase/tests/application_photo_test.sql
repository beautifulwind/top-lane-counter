-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 064: 장인 인증 신청 사진 - 올리기 권한(심사 중인 회원), 신청 사진 정하기·바꾸기·지우기, 보기(본인·운영자만), 경로가 공개되지 않음,
--      지우기 규칙, 하루 횟수(장인 사진과 함께), 정리 목록에서 제외, 승인(사진 포함·제외·본 사진과 다르면 거부·옛 승인 함수),
--      반려·취소·만료·탈퇴 때 대기열, 다시 신청하면 사진 없이 시작, 권한
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set B   '00000000-0000-0000-0000-000000000021'
\set C   '00000000-0000-0000-0000-000000000022'
\set D   '00000000-0000-0000-0000-000000000023'
\set E   '00000000-0000-0000-0000-000000000024'
\set F   '00000000-0000-0000-0000-000000000025'
\set H   '00000000-0000-0000-0000-000000000026'
\set N   '00000000-0000-0000-0000-000000000027'
\set G   '00000000-0000-0000-0000-0000000000a1'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'B', 'b@x.com'), (:'C', 'c@x.com'),
  (:'D', 'd@x.com'), (:'E', 'e@x.com'), (:'F', 'f@x.com'), (:'H', 'h@x.com'), (:'N', 'n@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '비회원1' where id = :'B';
update public.profiles set nickname = '씨회원1' where id = :'C';
update public.profiles set nickname = '디회원1' where id = :'D';
update public.profiles set nickname = '이회원1' where id = :'E';
update public.profiles set nickname = '에프회원' where id = :'F';
update public.profiles set nickname = '에이치회원' where id = :'H';
update public.profiles set nickname = '보통회원' where id = :'N';
update public.profiles set nickname = '손님' where id = :'G';

create function pg_temp.up(p_name text, p_mime text default 'image/webp', p_kb integer default 60) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('profile-photos', p_name, auth.uid(), auth.uid()::text, jsonb_build_object('mimetype', p_mime, 'size', p_kb * 1024));
$$;
create function pg_temp.apply(n text, ch text) returns bigint language sql as $$
  select apply_influencer('creator', n, 'https://youtube.com/@' || ch, ch || '@mail.com') $$;
create function pg_temp.app(u uuid) returns public.influencer_applications language sql security definer as $$
  select * from public.influencer_applications where user_id = u order by id desc limit 1 $$;
create function pg_temp.app_photo(u uuid) returns text language sql security definer as $$
  select photo_path from public.influencer_applications where user_id = u order by id desc limit 1 $$;
create function pg_temp.photo(u uuid) returns text language sql security definer as $$
  select photo_path from public.profiles where id = u $$;
create function pg_temp.trash(p text) returns text language sql security definer as $$
  select reason from public.profile_photo_trash where path = p $$;
create function pg_temp.seen(p text) returns integer language sql as $$
  select count(*)::integer from storage.objects where bucket_id = 'profile-photos' and name = p $$;
create function pg_temp.exists_obj(p text) returns boolean language sql security definer as $$
  select exists (select 1 from storage.objects where bucket_id = 'profile-photos' and name = p) $$;
create function pg_temp.msg(u uuid, k text) returns text language sql security definer as $$
  select message from public.notifications where user_id = u and kind = k order by id desc limit 1 $$;
create function pg_temp.changes(u uuid) returns integer language sql security definer as $$
  select count(*)::integer from public.profile_photo_changes where user_id = u $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

-- ===================================================================
-- 0. 모양 / 권한
-- ===================================================================
select t.ok('신청 표 새 칸 2개 + 검사 2개', (select count(*) from information_schema.columns where table_schema = 'public'
    and table_name = 'influencer_applications' and column_name in ('photo_path', 'photo_updated_at')) = 2
  and (select count(*) from pg_constraint where conrelid = 'public.influencer_applications'::regclass
    and conname in ('influencer_applications_photo_pair', 'influencer_applications_photo_pending')) = 2);
select t.ok('신청 표는 여전히 로그인 사람 읽기만 (쓰기 권한 없음)', not has_table_privilege('authenticated', 'public.influencer_applications', 'update')
  and not has_table_privilege('authenticated', 'public.influencer_applications', 'insert'));
select t.ok('로그인 사람: 신청 사진 정하기·지우기·새 승인 부를 수 있음', has_function_privilege('authenticated', 'public.set_application_photo(text)', 'execute')
  and has_function_privilege('authenticated', 'public.clear_application_photo()', 'execute')
  and has_function_privilege('authenticated', 'public.approve_influencer(bigint,text,text,boolean)', 'execute'));
select t.ok('비로그인: 못 부름', not has_function_privilege('anon', 'public.set_application_photo(text)', 'execute')
  and not has_function_privilege('anon', 'public.clear_application_photo()', 'execute')
  and not has_function_privilege('anon', 'public.approve_influencer(bigint,text,text,boolean)', 'execute'));
select t.ok('안쪽·트리거 함수는 아무도 못 부름', not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('approve_influencer_unchecked', 'application_photo_clear_on_end', 'application_photo_after_change')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
select t.ok('옛 승인 함수(신청, 메모)도 그대로 있음', has_function_privilege('authenticated', 'public.approve_influencer(bigint,text)', 'execute'));

-- ===================================================================
-- 1. 올리기 권한: 장인 또는 심사 중인 회원만
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'N';
select t.ok('신청 안 한 회원: 올릴 수 없는 이유', profile_photo_upload_problem() = '인증된 장인이나 장인 인증을 신청한 회원만 프로필 사진을 올릴 수 있습니다.');
select t.fails('신청 안 한 회원은 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'N'), 'row-level security');
select t.fails('신청 안 한 회원은 신청 사진도 못 정함', format($$select set_application_photo('%s/a.webp')$$, :'N'), '심사 중인 장인 인증 신청이 없습니다');
set request.jwt.claim.sub = :'G';
select t.fails('비회원은 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'G'), 'row-level security');
set request.jwt.claim.sub = :'B';
select t.fails('신청 전에는 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'B'), 'row-level security');
select pg_temp.apply('비장인', 'bbb');
select t.ok('신청 뒤: 올릴 수 있음', profile_photo_upload_problem() is null);
select t.fails('남의 폴더에는 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'C'), 'row-level security');
select pg_temp.up(:'B' || '/p1.webp');
select pg_temp.up(:'B' || '/p2.webp');
select pg_temp.up(:'B' || '/bad.png', 'image/png');
select pg_temp.up(:'B' || '/huge.webp', 'image/webp', 1100);

-- ===================================================================
-- 2. 신청 사진 정하기
-- ===================================================================
select t.fails('모양이 틀린 경로 거부', $$select set_application_photo('../x.webp')$$, '사진을 다시 골라 주세요');
select t.fails('남의 폴더 경로 거부', format($$select set_application_photo('%s/p1.webp')$$, :'C'), '사진을 다시 골라 주세요');
select t.fails('없는 파일 거부', format($$select set_application_photo('%s/none.webp')$$, :'B'), '올린 사진을 찾지 못했습니다');
select t.fails('PNG 거부', format($$select set_application_photo('%s/bad.png')$$, :'B'), '사진을 다시 골라 주세요');
select t.fails('1MB 넘는 파일 거부', format($$select set_application_photo('%s/huge.webp')$$, :'B'), '형식이나 크기');
select t.fails('신청 중이어도 장인 사진(set_profile_photo)은 못 정함', format($$select set_profile_photo('%s/p1.webp')$$, :'B'), '인증된 장인만');
select set_application_photo(:'B' || '/p1.webp');
select t.ok('신청에 사진이 붙음', pg_temp.app_photo(:'B') = :'B' || '/p1.webp' and (pg_temp.app(:'B')).photo_updated_at is not null);
select t.ok('내 장인 상태: photo_ready + 신청 사진 경로', (my_influencer_status() ->> 'photo_ready')::boolean
  and my_influencer_status() -> 'application' ->> 'photo_path' = :'B' || '/p1.webp');
select t.ok('하루 횟수 기록 1', pg_temp.changes(:'B') = 1);
select set_application_photo(:'B' || '/p1.webp');
select t.ok('같은 사진 다시 정하면 그대로 (횟수 안 셈)', pg_temp.changes(:'B') = 1);

-- ===================================================================
-- 3. 공개되지 않음 / 보기 규칙
-- ===================================================================
select t.ok('본인은 신청 사진 파일을 봄', pg_temp.seen(:'B' || '/p1.webp') = 1);
select t.ok('프로필 칸에는 없음 (누구나 읽는 칸)', pg_temp.photo(:'B') is null);
set request.jwt.claim.sub = :'C';
select t.ok('다른 회원: 파일 못 봄', pg_temp.seen(:'B' || '/p1.webp') = 0);
select t.ok('다른 회원: 신청 표에서 남의 신청(사진 경로)을 못 읽음', (select count(*) from public.influencer_applications where user_id = :'B') = 0);
select t.ok('다른 회원: 프로필 표에서 경로가 안 보임', (select photo_path from public.profiles where id = :'B') is null);
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관: 파일 못 봄', pg_temp.seen(:'B' || '/p1.webp') = 0);
set request.jwt.claim.sub = :'OP';
select t.ok('운영자: 파일 봄 (심사용)', pg_temp.seen(:'B' || '/p1.webp') = 1);
select t.ok('운영자: 안 쓴 파일(신청 사진 아님)은 못 봄', pg_temp.seen(:'B' || '/p2.webp') = 0);
select t.ok('운영자 신청 목록에 사진 경로', (select i ->> 'photo_path' from jsonb_array_elements(admin_influencer_applications('pending') -> 'items') i
  where (i -> 'user' ->> 'id')::uuid = :'B') = :'B' || '/p1.webp');
reset role;
update public.profiles set operator_mode = false where id = :'OP';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자 모드를 끄면 못 봄', pg_temp.seen(:'B' || '/p1.webp') = 0);
reset role;
update public.profiles set operator_mode = true where id = :'OP';
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인: 파일 못 봄', pg_temp.seen(:'B' || '/p1.webp') = 0);
select t.ok('비로그인: 공개 프로필 없음 (장인 아님)', public_profile(:'B') is null);
reset role;

-- ===================================================================
-- 4. 지우기 규칙 / 바꾸기 / 하루 횟수 / 지우기
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
delete from storage.objects where bucket_id = 'profile-photos' and name = :'B' || '/p1.webp';
select t.ok('심사 중 신청 사진은 지우기 규칙으로 못 지움', pg_temp.exists_obj(:'B' || '/p1.webp'));
select set_application_photo(:'B' || '/p2.webp');
select t.ok('바꾸면 옛 사진은 대기열 (replaced)', pg_temp.app_photo(:'B') = :'B' || '/p2.webp' and pg_temp.trash(:'B' || '/p1.webp') = 'replaced');
delete from storage.objects where bucket_id = 'profile-photos' and name = :'B' || '/p1.webp';
select t.ok('바꾼 뒤 옛 파일은 지울 수 있음', not pg_temp.exists_obj(:'B' || '/p1.webp'));
select pg_temp.up(:'B' || '/p3.webp');
reset role;
update public.xp_rules set value = 2 where key = 'profile_photo_daily_max';
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.fails('하루 횟수 (장인 사진과 같은 기록)', format($$select set_application_photo('%s/p3.webp')$$, :'B'), '하루에 2번까지');
select t.ok('하루 횟수가 차면 올릴 수 없는 이유도 안내', profile_photo_upload_problem() like '프로필 사진은 하루에 2번까지%');
reset role;
update public.xp_rules set value = 10 where key = 'profile_photo_daily_max';
set role authenticated;
set request.jwt.claim.sub = :'B';
select clear_application_photo();
select t.ok('지우기: 신청 사진 비움 + 대기열 (cleared)', pg_temp.app_photo(:'B') is null and pg_temp.trash(:'B' || '/p2.webp') = 'cleared');
select set_application_photo(:'B' || '/p3.webp');
select t.ok('다시 정함', pg_temp.app_photo(:'B') = :'B' || '/p3.webp');
reset role;

-- ===================================================================
-- 5. 정리 목록: 심사 중 신청 사진은 24시간이 지나도 안 지움
-- ===================================================================
update storage.objects set created_at = now() - interval '3 days' where bucket_id = 'profile-photos';
set role service_role;
select t.ok('정리 목록: 신청 사진 제외, 바꾼 사진·안 쓴 파일 포함',
  not (:'B' || '/p3.webp') = any(profile_photo_cleanup_list(1000))
  and (:'B' || '/p2.webp') = any(profile_photo_cleanup_list(1000))
  and (:'B' || '/huge.webp') = any(profile_photo_cleanup_list(1000)));
reset role;
insert into public.profile_photo_trash (path, reason) values (:'B' || '/p3.webp', 'test');
set role service_role;
select t.ok('대기열에 있어도 신청 사진이면 목록·완료 처리에서 빠짐', not (:'B' || '/p3.webp') = any(profile_photo_cleanup_list(1000))
  and profile_photo_cleanup_done(array[:'B' || '/p3.webp']) = 0);
reset role;
delete from public.profile_photo_trash where path = :'B' || '/p3.webp';

-- ===================================================================
-- 6. 승인
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('옛 승인(사진을 못 본 화면): 신청 사진이 있으면 거부', format($$select approve_influencer(%s, '확인')$$, (pg_temp.app(:'B')).id),
  '신청 사진을 확인해야 승인할 수 있습니다');
select t.fails('운영자가 본 사진과 다르면 거부', format($$select approve_influencer(%s, '확인', '%s/p2.webp', true)$$, (pg_temp.app(:'B')).id, :'B'),
  '신청자가 프로필 사진을 바꿨습니다');
select t.fails('사진을 못 봤는데(null) 지금 사진이 있으면 거부', format($$select approve_influencer(%s, '확인', null, true)$$, (pg_temp.app(:'B')).id),
  '신청자가 프로필 사진을 바꿨습니다');
select t.fails('사진을 빼도 본 사진과 다르면 거부', format($$select approve_influencer(%s, '확인', '%s/p2.webp', false)$$, (pg_temp.app(:'B')).id, :'B'),
  '신청자가 프로필 사진을 바꿨습니다');
select t.fails('승인 메모 필수', format($$select approve_influencer(%s, ' ', '%s/p3.webp', true)$$, (pg_temp.app(:'B')).id, :'B'), '승인 메모를 적어 주세요');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관은 승인 불가', format($$select approve_influencer(%s, '확인', '%s/p3.webp', true)$$, (pg_temp.app(:'B')).id, :'B'), '운영자만');
set request.jwt.claim.sub = :'B';
select t.fails('본인은 승인 불가', format($$select approve_influencer(%s, '확인', '%s/p3.webp', true)$$, (pg_temp.app(:'B')).id, :'B'), '운영자만');
set request.jwt.claim.sub = :'OP';
select approve_influencer((pg_temp.app(:'B')).id, '이메일 회신 확인', :'B' || '/p3.webp', true);
select t.ok('사진 포함 승인: 장인 사진이 됨 (파일 이동 없음)', pg_temp.photo(:'B') = :'B' || '/p3.webp'
  and (pg_temp.app(:'B')).status = 'approved' and pg_temp.app_photo(:'B') is null);
select t.ok('사진 포함 승인: 대기열에 없음', pg_temp.trash(:'B' || '/p3.webp') is null);
select t.ok('사진 포함 승인: 알림 문장', pg_temp.msg(:'B', 'influencer_approved') = '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다. 신청 때 고른 프로필 사진도 등록됐습니다.');
select t.ok('처리 기록 메모는 그대로', exists (select 1 from moderation_log where action = 'approve_influencer' and note = '이메일 회신 확인'));
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.ok('승인 뒤 누구나 봄 + 공개 프로필에 경로', pg_temp.seen(:'B' || '/p3.webp') = 1 and public_profile(:'B') ->> 'photo_path' = :'B' || '/p3.webp');
reset role;
set role service_role;
select t.ok('승인된 사진은 정리 목록에 없음', not (:'B' || '/p3.webp') = any(profile_photo_cleanup_list(1000)));
reset role;

-- 사진 빼고 승인
set role authenticated;
set request.jwt.claim.sub = :'C';
select pg_temp.apply('씨장인', 'ccc');
select pg_temp.up(:'C' || '/c1.webp');
select set_application_photo(:'C' || '/c1.webp');
set request.jwt.claim.sub = :'OP';
select approve_influencer((pg_temp.app(:'C')).id, '확인함', :'C' || '/c1.webp', false);
select t.ok('사진 빼고 승인: 장인이 되고 사진은 없음, 파일은 대기열', pg_temp.photo(:'C') is null
  and (select influencer from profiles where id = :'C') = 'creator' and pg_temp.trash(:'C' || '/c1.webp') = 'application_approved');
select t.ok('사진 빼고 승인: 알림 끝에 안내', pg_temp.msg(:'C', 'influencer_approved') like '%프로필 사진은 운영 원칙에 따라 등록하지 않았습니다.');
select t.ok('사진 빼고 승인: 처리 기록 메모', exists (select 1 from moderation_log where action = 'approve_influencer' and note = E'확인함 \u00B7 신청 사진 제외'));
reset role;
set role anon;
select t.ok('뺀 사진은 아무도 못 봄', pg_temp.seen(:'C' || '/c1.webp') = 0);
reset role;

-- 사진 없는 신청: 옛 승인·새 승인 모두 그대로
set role authenticated;
set request.jwt.claim.sub = :'D';
select pg_temp.apply('디장인', 'ddd');
set request.jwt.claim.sub = :'OP';
select approve_influencer((pg_temp.app(:'D')).id, '확인');
select t.ok('사진 없는 신청은 옛 승인 그대로 + 알림 문장 그대로', (select influencer from profiles where id = :'D') = 'creator'
  and pg_temp.msg(:'D', 'influencer_approved') = '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.');
set request.jwt.claim.sub = :'E';
select pg_temp.apply('이장인', 'eee');
set request.jwt.claim.sub = :'OP';
select approve_influencer((pg_temp.app(:'E')).id, '확인', null, true);
select t.ok('사진 없는 신청 + 새 승인(본 사진 null)', (select influencer from profiles where id = :'E') = 'creator' and pg_temp.photo(:'E') is null);
reset role;

-- ===================================================================
-- 7. 반려 / 다시 신청 / 취소 / 만료 / 탈퇴
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'F';
select pg_temp.apply('에프장인', 'fff');
select pg_temp.up(:'F' || '/f1.webp');
select set_application_photo(:'F' || '/f1.webp');
set request.jwt.claim.sub = :'OP';
select reject_influencer((pg_temp.app(:'F')).id, '확인 메일 회신 없음', false, true);
select t.ok('반려: 사진 칸 비움 + 대기열', pg_temp.app_photo(:'F') is null and pg_temp.trash(:'F' || '/f1.webp') = 'application_rejected');
set request.jwt.claim.sub = :'F';
select t.ok('반려 뒤: 올릴 수 없음', profile_photo_upload_problem() like '인증된 장인이나%');
select pg_temp.apply('에프장인', 'fff');
select t.ok('다시 신청: 사진 없이 시작', pg_temp.app_photo(:'F') is null and (pg_temp.app(:'F')).status = 'pending');
select pg_temp.up(:'F' || '/f2.webp');
select set_application_photo(:'F' || '/f2.webp');
select cancel_influencer_application((pg_temp.app(:'F')).id);
select t.ok('취소: 사진 칸 비움 + 대기열', pg_temp.app_photo(:'F') is null and pg_temp.trash(:'F' || '/f2.webp') = 'application_cancelled');
select t.ok('취소한 신청의 사진은 상태에 없음', my_influencer_status() -> 'application' ->> 'photo_path' is null);

set request.jwt.claim.sub = :'H';
select pg_temp.apply('에이치장인', 'hhh');
select pg_temp.up(:'H' || '/h1.webp');
select set_application_photo(:'H' || '/h1.webp');
reset role;
update public.influencer_applications set expires_at = now() - interval '1 minute' where user_id = :'H' and status = 'pending';
select influencer_daily();
select t.ok('만료: 사진 칸 비움 + 대기열', (pg_temp.app(:'H')).status = 'expired' and pg_temp.app_photo(:'H') is null
  and pg_temp.trash(:'H' || '/h1.webp') = 'application_expired');

set role authenticated;
set request.jwt.claim.sub = :'H';
select pg_temp.apply('에이치장인', 'hhh');
select pg_temp.up(:'H' || '/h2.webp');
select set_application_photo(:'H' || '/h2.webp');
reset role;
select t.ok('탈퇴 전: 심사 중 + 사진', pg_temp.app_photo(:'H') = :'H' || '/h2.webp');
delete from auth.users where id = :'H';
select t.ok('탈퇴: 신청은 withdrawn, 사진 칸 비움 + 대기열',
  (select count(*) from influencer_applications where user_id is null and status = 'withdrawn' and photo_path is null) >= 1
  and pg_temp.trash(:'H' || '/h2.webp') = 'application_withdrawn');

-- ===================================================================
-- 8. 표 검사: 끝난 신청에는 사진을 둘 수 없음
-- ===================================================================
select t.fails('끝난 신청에 사진 경로 직접 넣기 거부 (트리거가 비움 -> 짝 검사)',
  format($$update influencer_applications set photo_updated_at = now() where id = %s$$, (pg_temp.app(:'F')).id), 'influencer_applications_photo_pair');
set role authenticated;
set request.jwt.claim.sub = :'N';
select pg_temp.apply('엔장인', 'nnn');
reset role;
select t.fails('남의 폴더 경로는 표 검사로 거부',
  format($$update influencer_applications set photo_path = '%s/x.webp', photo_updated_at = now() where user_id = '%s' and status = 'pending'$$, :'B', :'N'),
  'influencer_applications_photo_pending');
