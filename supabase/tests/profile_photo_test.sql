-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 062: 장인 프로필 사진 - 버킷·표 권한, 올리기 규칙(장인만·내 폴더·파일 수·하루 횟수), 정하기·바꾸기·지우기,
--      보기 규칙(지금 사진만), 지우기 규칙(지금 사진은 못 지움), 신고(정식 회원·남의 사진·한 번), 운영자 목록·기각·삭제(알림·기록),
--      사진이 바뀌면 신고 저절로 닫힘, 인증 해제·탈퇴 정리, 정리 목록(대기열 + 안 쓴 파일), 공개 프로필, 차단과 무관
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set M '00000000-0000-0000-0000-00000000000d'
\set W '00000000-0000-0000-0000-000000000012'
\set X '00000000-0000-0000-0000-000000000013'
\set G '00000000-0000-0000-0000-0000000000a1'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'M', 'm@x.com'), (:'W', 'w@x.com'), (:'X', 'x@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'M';
update public.profiles set nickname = 'Faker', influencer = 'pro', influencer_at = now() where id = :'W';
update public.profiles set nickname = '장인둘', influencer = 'creator', influencer_at = now() where id = :'X';
update public.profiles set nickname = '손님' where id = :'G';

-- 화면이 Storage API로 올리는 것 흉내: 지금 로그인한 사람 권한으로 파일 줄을 넣는다 (규칙 검사를 받는다)
create function pg_temp.up(p_name text, p_mime text default 'image/webp', p_kb integer default 60) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('profile-photos', p_name, auth.uid(), auth.uid()::text, jsonb_build_object('mimetype', p_mime, 'size', p_kb * 1024));
$$;
create function pg_temp.photo(u uuid) returns text language sql security definer as $$
  select photo_path from public.profiles where id = u $$;
create function pg_temp.trash() returns text[] language sql security definer as $$
  select coalesce(array_agg(path order by path), '{}') from public.profile_photo_trash $$;
create function pg_temp.seen(p text) returns integer language sql as $$
  select count(*)::integer from storage.objects where bucket_id = 'profile-photos' and name = p $$;
create function pg_temp.exists_obj(p text) returns boolean language sql security definer as $$
  select exists (select 1 from storage.objects where bucket_id = 'profile-photos' and name = p) $$;
create function pg_temp.notes(u uuid, k text) returns integer language sql security definer as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
create function pg_temp.msg(u uuid, k text) returns text language sql security definer as $$
  select message from public.notifications where user_id = u and kind = k order by id desc limit 1 $$;
create function pg_temp.rstatus(p text) returns text language sql security definer as $$
  select string_agg(status, ',' order by id) from public.profile_photo_reports where photo_path = p $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

-- ===================================================================
-- 0. 버킷 / 표 / 권한
-- ===================================================================
select t.ok('버킷 profile-photos: 비공개, 1MB, webp·jpeg',
  (select not public and file_size_limit = 1048576 and allowed_mime_types = array['image/webp', 'image/jpeg']
   from storage.buckets where id = 'profile-photos'));
select t.ok('새 표 3개: RLS 켜짐 + 로그인·비로그인 직접 권한 없음', not exists (
  select 1 from unnest(array['public.profile_photo_reports', 'public.profile_photo_trash', 'public.profile_photo_changes']) tb,
                unnest(array['select', 'insert', 'update', 'delete']) pr, unnest(array['anon', 'authenticated']) r
   where has_table_privilege(r, tb, pr))
  and (select bool_and(relrowsecurity) from pg_class where oid in ('public.profile_photo_reports'::regclass,
       'public.profile_photo_trash'::regclass, 'public.profile_photo_changes'::regclass)));
select t.ok('사진 칸은 사용자가 직접 못 고침', not has_column_privilege('authenticated', 'public.profiles', 'photo_path', 'update')
  and not has_column_privilege('authenticated', 'public.profiles', 'photo_updated_at', 'update'));
select t.ok('비로그인은 정하기·신고·운영자 함수 못 부름', not has_function_privilege('anon', 'public.set_profile_photo(text)', 'execute')
  and not has_function_privilege('anon', 'public.report_profile_photo(uuid,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.remove_profile_photo(uuid,text)', 'execute'));
select t.ok('정리 함수는 service_role만', has_function_privilege('service_role', 'public.profile_photo_cleanup_list(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.profile_photo_cleanup_list(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.profile_photo_cleanup_done(text[])', 'execute'));
select t.ok('트리거 함수는 아무도 못 부름', not has_function_privilege('authenticated', 'public.profile_photo_after_change()', 'execute')
  and not has_function_privilege('authenticated', 'public.notify_staff_new_photo_report()', 'execute'));
select t.ok('알림 묶음: 사진 삭제는 링크 삭제와 같은 my_results', push_group('profile_photo_removed') = 'my_results'
  and push_group('link_removed') = 'my_results');

-- ===================================================================
-- 1. 올리기 규칙
-- ===================================================================
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인은 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'W'), 'row-level security');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.ok('장인 아님(신청도 없음): 올릴 수 없는 이유 (064 문구)', profile_photo_upload_problem() = '인증된 장인이나 장인 인증을 신청한 회원만 프로필 사진을 올릴 수 있습니다.');
select t.fails('장인 아니면 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'B'), 'row-level security');
set request.jwt.claim.sub = :'G';
select t.fails('비회원은 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'G'), 'row-level security');
set request.jwt.claim.sub = :'W';
select t.ok('장인: 올릴 수 있음', profile_photo_upload_problem() is null);
select t.fails('남의 폴더에는 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'X'), 'row-level security');
select t.fails('board-media 규칙으로는 profile-photos에 못 올림 (폴더가 맞아도 장인 규칙)',
  format($$insert into storage.objects (bucket_id, name, owner_id, metadata) values ('profile-photos', '%s/z.webp', '%s', '{}')$$, :'B', :'B'),
  'row-level security');
select pg_temp.up(:'W' || '/p1.webp');
select pg_temp.up(:'W' || '/p2.webp');
select pg_temp.up(:'W' || '/bad.png', 'image/png');
select pg_temp.up(:'W' || '/huge.webp', 'image/webp', 1100);
select pg_temp.up(:'W' || '/p3.jpg', 'image/jpeg');
select t.ok('폴더에 5개면 더 못 올림 (이유 안내)', profile_photo_upload_problem() like '올려 두고 쓰지 않은 사진이 많습니다%');
select t.fails('6번째 파일 거부', format($$select pg_temp.up('%s/p6.webp')$$, :'W'), 'row-level security');

-- ===================================================================
-- 2. 정하기
-- ===================================================================
select t.fails('모양이 틀린 경로 거부', $$select set_profile_photo('../x.webp')$$, '사진을 다시 골라 주세요');
select t.fails('남의 폴더 경로 거부', format($$select set_profile_photo('%s/p1.webp')$$, :'X'), '사진을 다시 골라 주세요');
select t.fails('없는 파일 거부', format($$select set_profile_photo('%s/none.webp')$$, :'W'), '올린 사진을 찾지 못했습니다');
select t.fails('PNG 그대로는 거부 (화면이 webp·jpeg로 바꿔 올림)', format($$select set_profile_photo('%s/bad.png')$$, :'W'), '사진을 다시 골라 주세요');
select t.fails('1MB 넘는 파일 거부', format($$select set_profile_photo('%s/huge.webp')$$, :'W'), '형식이나 크기');
select set_profile_photo(:'W' || '/p1.webp');
select t.ok('사진 정해짐 + 시각', pg_temp.photo(:'W') = :'W' || '/p1.webp'
  and (select photo_updated_at > now() - interval '1 minute' from profiles where id = :'W'));
select t.ok('공개 프로필에 사진 경로', (public_profile(:'W') ->> 'photo_path') = :'W' || '/p1.webp');
select set_profile_photo(:'W' || '/p1.webp');
select t.ok('같은 사진을 다시 정하면 그대로 (대기열 없음)', pg_temp.photo(:'W') = :'W' || '/p1.webp'
  and cardinality(pg_temp.trash()) = 0);
set request.jwt.claim.sub = :'B';
select t.fails('장인 아니면 정하기 거부', format($$select set_profile_photo('%s/a.webp')$$, :'B'), '인증된 장인만');
set request.jwt.claim.sub = :'X';
select t.fails('다른 장인 파일을 내 사진으로 못 정함 (내 폴더가 아님)', format($$select set_profile_photo('%s/p2.webp')$$, :'W'), '사진을 다시 골라 주세요');

-- ===================================================================
-- 3. 보기 규칙: 지금 사진만 누구나
-- ===================================================================
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인: 지금 사진은 보임', pg_temp.seen(:'W' || '/p1.webp') = 1);
select t.ok('비로그인: 안 쓰는 파일은 안 보임', pg_temp.seen(:'W' || '/p2.webp') = 0);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.ok('다른 회원: 지금 사진만 보임', pg_temp.seen(:'W' || '/p1.webp') = 1 and pg_temp.seen(:'W' || '/p2.webp') = 0);
set request.jwt.claim.sub = :'W';
select t.ok('본인: 내 폴더 파일은 다 보임', pg_temp.seen(:'W' || '/p2.webp') = 1);

-- ===================================================================
-- 4. 바꾸기 / 지우기 규칙
-- ===================================================================
delete from storage.objects where bucket_id = 'profile-photos' and name = :'W' || '/p1.webp';
select t.ok('지금 사진 파일은 본인도 못 지움', pg_temp.exists_obj(:'W' || '/p1.webp'));
select set_profile_photo(:'W' || '/p2.webp');
select t.ok('바꾸면 옛 경로가 지울 파일 대기열에', pg_temp.trash() = array[:'W' || '/p1.webp']);
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.ok('바꾼 뒤 옛 사진은 바로 안 보이고 새 사진이 보임', pg_temp.seen(:'W' || '/p1.webp') = 0 and pg_temp.seen(:'W' || '/p2.webp') = 1);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'B';
delete from storage.objects where bucket_id = 'profile-photos' and name like :'W' || '/%';
select t.ok('남은 내 파일을 못 지움', pg_temp.exists_obj(:'W' || '/p1.webp') and pg_temp.exists_obj(:'W' || '/bad.png'));
set request.jwt.claim.sub = :'W';
delete from storage.objects where bucket_id = 'profile-photos' and name in (:'W' || '/p1.webp', :'W' || '/bad.png', :'W' || '/huge.webp');
select t.ok('본인은 지금 사진이 아닌 파일을 바로 지움', not pg_temp.exists_obj(:'W' || '/p1.webp') and not pg_temp.exists_obj(:'W' || '/bad.png')
  and pg_temp.exists_obj(:'W' || '/p2.webp'));
select t.fails('고치기(update) 거부', format($$update storage.objects set name = '%s/q.webp' where name = '%s/p2.webp'$$, :'W', :'W'), 'permission denied');

-- 하루 횟수
reset role;
update public.xp_rules set value = 3 where key = 'profile_photo_daily_max';
set role authenticated;
set request.jwt.claim.sub = :'W';
select set_profile_photo(:'W' || '/p3.jpg');
select t.ok('jpeg도 됨', pg_temp.photo(:'W') = :'W' || '/p3.jpg');
select t.ok('24시간에 3번 바꿨으면 이유 안내', profile_photo_upload_problem() = '프로필 사진은 하루에 3번까지 바꿀 수 있습니다. 내일 다시 해 주세요.');
select t.fails('4번째 바꾸기 거부', format($$select set_profile_photo('%s/p2.webp')$$, :'W'), '하루에 3번까지');
reset role;
update public.profile_photo_changes set created_at = now() - interval '3 days' where user_id = :'W';
update public.xp_rules set value = 10 where key = 'profile_photo_daily_max';
set role authenticated;
set request.jwt.claim.sub = :'W';
select set_profile_photo(:'W' || '/p2.webp');
select t.ok('하루가 지나면 다시 바꿀 수 있고 오래된 기록은 지워짐',
  pg_temp.photo(:'W') = :'W' || '/p2.webp' and cardinality(pg_temp.trash()) >= 2);

-- 본인 삭제
select pg_temp.up(:'W' || '/p4.webp');
select set_profile_photo(:'W' || '/p4.webp');
select clear_profile_photo();
select t.ok('본인 삭제: 사진 비움 + 대기열', pg_temp.photo(:'W') is null and :'W' || '/p4.webp' = any(pg_temp.trash())
  and (public_profile(:'W') -> 'photo_path') = 'null'::jsonb);
select clear_profile_photo();  -- 없을 때 다시 눌러도 오류 없음
select set_profile_photo(:'W' || '/p4.webp');
select t.ok('대기열에 있던 내 파일을 다시 쓰면 대기열에서 빠짐', pg_temp.photo(:'W') = :'W' || '/p4.webp'
  and not (:'W' || '/p4.webp' = any(pg_temp.trash())));

-- ===================================================================
-- 5. 신고
-- ===================================================================
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인은 신고 못 함', format($$select report_profile_photo('%s', 'spam')$$, :'W'), 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'G';
select t.fails('비회원은 신고 못 함', format($$select report_profile_photo('%s', 'spam')$$, :'W'), '비회원은 신고할 수 없습니다');
set request.jwt.claim.sub = :'W';
select t.fails('내 사진은 신고 못 함', format($$select report_profile_photo('%s', 'spam')$$, :'W'), '내 사진은 신고할 수 없습니다');
set request.jwt.claim.sub = :'B';
select t.fails('이유 없으면 거부', format($$select report_profile_photo('%s', 'bad')$$, :'W'), '신고 이유를 골라 주세요');
select t.fails('기타는 내용 필수', format($$select report_profile_photo('%s', 'other', '  ')$$, :'W'), '기타 이유를 적어 주세요');
select t.fails('사진 없는 장인은 신고 못 함', format($$select report_profile_photo('%s', 'spam')$$, :'X'), '신고할 수 없는 사진입니다');
select report_profile_photo(:'W', 'obscene', '선정적');
select t.fails('같은 사진은 한 번만', format($$select report_profile_photo('%s', 'spam')$$, :'W'), '이미 신고한 사진입니다');
select t.ok('운영자에게 report_received (프로필 사진)', pg_temp.notes(:'A', 'report_received') = 1
  and pg_temp.msg(:'A', 'report_received') = '새 신고가 들어왔습니다. (프로필 사진)');
set request.jwt.claim.sub = :'M';
select report_profile_photo(:'W', 'impersonation');
select t.ok('같은 사진의 두 번째 신고는 운영자 알림을 더 만들지 않음', pg_temp.notes(:'A', 'report_received') = 1);

-- ===================================================================
-- 6. 운영자: 목록 / 기각 / 삭제 (감독관 불가)
-- ===================================================================
select t.fails('감독관은 목록 못 봄', 'select admin_profile_photo_reports()', '운영자만');
select t.fails('감독관은 삭제 못 함', format($$select remove_profile_photo('%s', '부적절')$$, :'W'), '운영자만');
select t.fails('감독관은 기각 못 함', format($$select dismiss_profile_photo_reports('%s')$$, :'W'), '운영자만');
set request.jwt.claim.sub = :'B';
select t.fails('회원은 삭제 못 함', format($$select remove_profile_photo('%s', '부적절')$$, :'W'), '운영자만');
set request.jwt.claim.sub = :'A';
select t.ok('운영자 목록: 사진 1개에 신고 2건, 지금 사진',
  (select (r ->> 'total')::int = 1 and r -> 'photos' -> 0 ->> 'photo_path' = :'W' || '/p4.webp'
      and (r -> 'photos' -> 0 ->> 'current')::boolean and jsonb_array_length(r -> 'photos' -> 0 -> 'reports') = 2
      and r -> 'photos' -> 0 -> 'owner' ->> 'nickname' = 'Faker'
      and r -> 'photos' -> 0 -> 'reports' -> 0 ->> 'reason' = 'obscene'
   from (select admin_profile_photo_reports() r) x));
select t.ok('운영자는 신고된 사진 파일을 봄', pg_temp.seen(:'W' || '/p4.webp') = 1);
create temp table got as select dismiss_profile_photo_reports(:'W', '문제 없음') as n;
select t.ok('기각: 2건 닫음 + 처리 기록', (select n from got) = 2
  and pg_temp.rstatus(:'W' || '/p4.webp') = 'dismissed,dismissed'
  and exists (select 1 from moderation_log where action = 'dismiss_reports' and target_kind = 'user' and target_id = :'W'
                and note = '프로필 사진 · 문제 없음' and target_nickname = 'Faker'));
select t.fails('닫을 신고가 없으면 오류', format($$select dismiss_profile_photo_reports('%s')$$, :'W'), '처리할 신고가 없습니다');
select t.ok('기각해도 사진은 그대로', pg_temp.photo(:'W') = :'W' || '/p4.webp');

-- 다시 신고 -> 운영자 삭제
reset role;
delete from public.profile_photo_reports;
set role authenticated;
set request.jwt.claim.sub = :'B';
select report_profile_photo(:'W', 'hate');
set request.jwt.claim.sub = :'A';
select t.fails('삭제 사유 필수', format($$select remove_profile_photo('%s', '  ')$$, :'W'), '삭제 사유를 적어 주세요');
select remove_profile_photo(:'W', '혐오 표현');
select t.ok('운영자 삭제: 사진 비움 + 대기열', pg_temp.photo(:'W') is null and :'W' || '/p4.webp' = any(pg_temp.trash()));
select t.ok('운영자 삭제: 신고는 처리됨(resolved)', pg_temp.rstatus(:'W' || '/p4.webp') = 'resolved');
select t.ok('운영자 삭제: 장인에게 알림 (사유 포함)', pg_temp.notes(:'W', 'profile_photo_removed') = 1
  and pg_temp.msg(:'W', 'profile_photo_removed')
      = '프로필 사진이 운영 원칙에 따라 삭제됐습니다. 사유: 혐오 표현');
select t.ok('운영자 삭제: 처리 기록', exists (select 1 from moderation_log where action = 'remove_profile_photo' and target_kind = 'user'
  and target_id = :'W' and note = '처리 전 신고 1건 · 혐오 표현' and target_nickname = 'Faker' and actor_role = 'admin'));
select t.fails('사진이 없으면 삭제 오류', format($$select remove_profile_photo('%s', '다시')$$, :'W'), '지울 프로필 사진이 없습니다');
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.ok('지운 사진은 바로 안 보임', pg_temp.seen(:'W' || '/p4.webp') = 0);
reset role;

-- ===================================================================
-- 7. 사진을 바꾸면 처리 전 신고가 저절로 닫힘
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'W';
select set_profile_photo(:'W' || '/p2.webp');
set request.jwt.claim.sub = :'B';
select report_profile_photo(:'W', 'spam');
set request.jwt.claim.sub = :'W';
select set_profile_photo(:'W' || '/p3.jpg');
select t.ok('바꾸면 옛 사진 신고는 기각으로 닫힘', pg_temp.rstatus(:'W' || '/p2.webp') = 'dismissed');
set request.jwt.claim.sub = :'A';
select t.ok('운영자 목록에서 빠짐', (admin_profile_photo_reports() ->> 'total')::int = 0);
set request.jwt.claim.sub = :'B';
select report_profile_photo(:'W', 'spam');
select t.ok('새 사진은 다시 신고할 수 있음', pg_temp.rstatus(:'W' || '/p3.jpg') = 'open');

-- ===================================================================
-- 8. 차단(061)과 무관: 차단해도 신고·보기 규칙은 그대로, 차단당한 장인도 사진을 바꿀 수 있음
-- ===================================================================
insert into user_blocks (blocker_id, blocked_id) values (:'B', :'W');
select t.ok('차단해도 공개 프로필 데이터는 그대로 (화면이 거른다)', (public_profile(:'W') ->> 'photo_path') = :'W' || '/p3.jpg');
set request.jwt.claim.sub = :'W';
select set_profile_photo(:'W' || '/p2.webp');
select t.ok('차단당한 장인도 사진을 바꿀 수 있음', pg_temp.photo(:'W') = :'W' || '/p2.webp');
reset role;

-- ===================================================================
-- 9. 인증 해제 / 탈퇴
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'X';
select pg_temp.up(:'X' || '/x1.webp');
select set_profile_photo(:'X' || '/x1.webp');
reset role;
update public.profiles set influencer = null, influencer_at = null where id = :'W';
select t.ok('인증 해제: 사진 바로 비움 + 대기열', pg_temp.photo(:'W') is null and :'W' || '/p2.webp' = any(pg_temp.trash()));
select t.ok('인증 해제 뒤 공개 프로필 없음', public_profile(:'W') is null);
select t.fails('사진 칸은 장인만 (검사)', format($$update public.profiles set photo_path = '%s/p3.jpg', photo_updated_at = now() where id = '%s'$$, :'W', :'W'),
  'profiles_photo_influencer');
delete from auth.users where id = :'X';
select t.ok('탈퇴: 사진 경로가 대기열에', :'X' || '/x1.webp' = any(pg_temp.trash()));

-- ===================================================================
-- 10. 정리 목록 (service_role)
-- ===================================================================
update public.profiles set influencer = 'pro', influencer_at = now() where id = :'W';
set role authenticated;
set request.jwt.claim.sub = :'W';
select set_profile_photo(:'W' || '/p3.jpg');
select pg_temp.up(:'W' || '/fresh.webp');
reset role;
update storage.objects set created_at = now() - interval '25 hours' where bucket_id = 'profile-photos';
update storage.objects set created_at = now() where name = :'W' || '/fresh.webp';
set role service_role;
select t.ok('정리 목록: 대기열 + 24시간 지난 안 쓴 파일, 지금 사진·새 파일은 빼고',
  (select :'W' || '/p2.webp' = any(l) and :'X' || '/x1.webp' = any(l) and :'W' || '/p4.webp' = any(l)
      and not (:'W' || '/p3.jpg' = any(l)) and not (:'W' || '/fresh.webp' = any(l))
   from (select profile_photo_cleanup_list(100) l) x));
create temp table done_n as select profile_photo_cleanup_done(array[:'W' || '/p2.webp', :'X' || '/x1.webp', :'W' || '/p3.jpg']) as n;
select t.ok('지운 경로를 대기열에서 뺌 (지금 사진 경로는 남김)', (select n from done_n) = 2
  and not (:'W' || '/p2.webp' = any(pg_temp.trash())));
select t.ok('board-media 정리 목록에는 섞이지 않음', not exists (
  select 1 from unnest(media_cleanup_list(1000)) p where p like :'W' || '/%' or p like :'X' || '/%'));
reset role;
