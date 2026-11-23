-- =====================================================================
-- 068(활동 제한) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 068을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~7번: [지금 값]이 [정상 값]과 모두 맞으면 068을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 8~17번은 "적어 둘 값"이다. 068 실행 뒤 check_restrictions_after.sql의 같은 이름 줄과 비교한다(같아야 한다 - 068은 기존 데이터를 바꾸지 않는다).
--     (그 사이 사이트에서 누가 글을 쓰거나 추천하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
--   - 18번은 다시 정의하는 기존 함수 29개의 본문·설정 지문이다(본문의 줄바꿈 CR은 빼고 계산 - 붙여 넣기 방식과 무관하게 같은 값). 068 뒤 "검사 한 줄을 뺀 본문" 지문과 같아야 한다(그 한 줄만 바뀜).
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '067 실행됨 (짝 표 build_edit_notices 있음)' as what,
    coalesce(to_regclass('public.build_edit_notices')::text, '없음') as now_value, 'build_edit_notices' as ok_value, '없음이면 067부터 실행' as memo
  union all select 2, '068 아직 안 함 (표 user_restrictions·restriction_exemptions 없음 / 함수 assert_can_write 없음 / a_restriction 트리거 0)',
    coalesce(to_regclass('public.user_restrictions')::text, '없음') || ' / ' || coalesce(to_regclass('public.restriction_exemptions')::text, '없음')
      || ' / ' || coalesce(to_regprocedure('public.assert_can_write()')::text, '없음')
      || ' / ' || (select count(*) from pg_trigger where tgname in ('a_restriction', 'a_restriction_edit')),
    '없음 / 없음 / 없음 / 0', '하나라도 있으면 068을 이미 실행한 것 - 다시 실행하지 말고 알려 주세요'
  union all select 3, '068이 다시 정의할 함수 37개가 모두 있음 (이름 수)',
    (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in (
      'apply_influencer','begin_edit','create_build','create_comment','create_doc_comment','create_matchup','create_post',
      'edit_build','edit_comment','edit_doc_comment','edit_my_build','edit_my_proposal','edit_post','follow_influencer',
      'report_comment','report_doc_comment','report_link','report_post','report_profile_photo','report_wiki',
      'resubmit_build','resubmit_proposal','save_build','set_application_photo','set_build_link','set_profile_links',
      'set_profile_photo','vote_build','vote_post',
      'media_upload_problem','profile_photo_upload_problem','set_moderator','create_inquiry','set_inquiry_category',
      'inquiry_category_label','answer_inquiry','notify_staff_new_inquiry'))::text
    || ' / 같은 이름 두 벌: ' || (select count(*) from (select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('apply_influencer','begin_edit','create_build','create_comment','create_doc_comment','create_matchup',
           'create_post','edit_build','edit_comment','edit_doc_comment','edit_my_build','edit_my_proposal','edit_post','follow_influencer','report_comment',
           'report_doc_comment','report_link','report_post','report_profile_photo','report_wiki','resubmit_build','resubmit_proposal','save_build',
           'set_application_photo','set_build_link','set_profile_links','set_profile_photo','vote_build','vote_post')
         group by p.proname having count(*) > 1) d),
    '37 / 같은 이름 두 벌: 0', null
  union all select 4, '고칠 정책 3개 / 제약 2개 / 트리거 1개가 있음',
    (select count(*) from pg_policies where (tablename, policyname) in (('builds', 'builds: 본인 이름으로 대기 빌드 등록'),
       ('edit_proposals', 'edit_proposals: 본인 이름으로 대기 제안 작성'), ('inquiries', 'inquiries: 본인·운영진 읽기')))
    || ' / ' || (select count(*) from pg_constraint where conname in ('moderation_log_action_check', 'inquiries_category_check'))
    || ' / ' || (select count(*) from pg_trigger where tgname = 'inquiries_notify_staff_move'),
    '3 / 2 / 1', null
  union all select 5, '문의 분류별 수 (이의 제기 appeal은 아직 없음)',
    coalesce((select string_agg(category || ':' || n, ', ' order by category) from (select category, count(*) n from public.inquiries group by category) x), '문의 없음'),
    'appeal 없음', null
  union all select 6, '운영자(admin) 수 / 감독관 수',
    (select count(*) filter (where role = 'admin') || ' / ' || count(*) filter (where role = 'moderator') from public.profiles),
    '1 / (몇 명이든)', '감독관에게는 제한을 걸 수 없다'
  union all select 7, '일반 사용자가 부를 수 있는 쓰기 함수 수 (volatile, 트리거 아님)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
        and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))::text,
    '96', '068 뒤에는 운영자 함수 2개(restrict_user·lift_restriction)가 늘어 98. 다르면(누가 함수를 더했으면) 알려 주세요'
  union all select 8, '적어 둘 값: 빌드 (줄 수 / 가장 큰 id / 추천 수 합계 / 비추천 수 합계 / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || coalesce(sum(up_count), 0) || ' / ' || coalesce(sum(down_count), 0)
       || ' / ' || md5(coalesce(string_agg(b::text, '|' order by b.id), '')) from public.builds b),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 9, '적어 둘 값: 빌드 추천·비추천 (줄 수 / 추천 줄 / 비추천 줄 / 내용 지문)',
    (select count(*) || ' / ' || count(*) filter (where value = 1) || ' / ' || count(*) filter (where value = -1)
       || ' / ' || md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')) from public.build_votes v),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 10, '적어 둘 값: 빌드 수정 기록 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.build_revisions r),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 11, '적어 둘 값: 알림 (줄 수 / 가장 큰 id / 내용 지문 - 읽음 표시는 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / '
       || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), ''))
       from public.notifications n),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 12, '적어 둘 값: 빌드 저장(북마크) (줄 수 / 내용 지문)',
    (select count(*) || ' / ' || md5(coalesce(string_agg(k::text, '|' order by k.user_id::text, k.build_id), '')) from public.build_bookmarks k),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 13, '적어 둘 값: 글 / 댓글 / 문서 댓글 (줄 수 · 가장 큰 id · 내용 지문)',
    (select count(*) || '·' || coalesce(max(id), 0) || '·' || left(md5(coalesce(string_agg(p::text, '|' order by p.id), '')), 12) from public.posts p)
      || ' / ' || (select count(*) || '·' || coalesce(max(id), 0) || '·' || left(md5(coalesce(string_agg(c::text, '|' order by c.id), '')), 12) from public.post_comments c)
      || ' / ' || (select count(*) || '·' || coalesce(max(id), 0) || '·' || left(md5(coalesce(string_agg(d::text, '|' order by d.id), '')), 12) from public.doc_comments d),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 14, '적어 둘 값: 상대법 / 제안 / 팔로우 / 신고 (줄 수)',
    (select count(*) from public.counters) || ' / ' || (select count(*) from public.edit_proposals) || ' / ' || (select count(*) from public.influencer_follows)
      || ' / ' || (select count(*) from public.reports) || '+' || (select count(*) from public.wiki_reports) || '+' || (select count(*) from public.link_reports)
      || '+' || (select count(*) from public.profile_photo_reports),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 15, '적어 둘 값: 문의 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(i::text, '|' order by i.id), '')) from public.inquiries i),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 16, '적어 둘 값: 처리 기록 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(m::text, '|' order by m.id), '')) from public.moderation_log m),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 17, '적어 둘 값: 프로필 (줄 수 / 내용 지문 - 마지막 접속 시각은 빼고)',
    (select count(*) || ' / ' || md5(coalesce(string_agg((to_jsonb(p) - 'last_seen_at')::text, '|' order by p.id), '')) from public.profiles p),
    '(이 값을 적어 둠)', '068 뒤 같아야 함'
  union all select 18, '적어 둘 값: 다시 정의할 기존 함수 29개 (본문·보안·search_path·권한 지문)',
    (select count(*) || ' / ' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || replace(p.prosrc, E'\r', '') || p.prosecdef::text
                                              || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(p.proacl::text, ''), '|' order by p.proname))
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in (
      'apply_influencer','begin_edit','create_build','create_comment','create_doc_comment','create_matchup','create_post',
      'edit_build','edit_comment','edit_doc_comment','edit_my_build','edit_my_proposal','edit_post','follow_influencer',
      'report_comment','report_doc_comment','report_link','report_post','report_profile_photo','report_wiki',
      'resubmit_build','resubmit_proposal','save_build','set_application_photo','set_build_link','set_profile_links',
      'set_profile_photo','vote_build','vote_post')),
    '29 / (이 값을 적어 둠)', '068 뒤 after 18번(검사 한 줄을 뺀 본문)과 같아야 함'
) x
order by ord;
