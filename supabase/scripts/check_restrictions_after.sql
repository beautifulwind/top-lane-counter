-- =====================================================================
-- 068(활동 제한) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다). 운영 DB에서 언제 다시 실행해도 된다.
-- 068을 실행한 "직후" SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~12번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요. (웹 push는 그다음)
--     5·6번은 빠뜨림 방지 검사다(로컬 tests/restriction_coverage_test.sql과 같은 규칙): 일반 사용자가 부를 수 있는 쓰기 함수·쓰기 정책을
--     DB에서 전부 뽑아, 제한 검사가 있거나 허용 목록(restriction_exemptions)에 있어야 통과. 통과하지 못한 것의 이름이 [지금 값]에 나온다.
--     나중에 새 마이그레이션 뒤에도 이 파일을 다시 실행해 5·6번이 "없음"인지 보면 된다.
--   - 13~22번: 실행 전 check_restrictions_before.sql의 8~17번에 적어 둔 값과 같아야 한다 (068은 기존 데이터를 바꾸지 않는다).
--   - 23번: 실행 전 18번과 같아야 한다 (기존 함수 29개는 검사 한 줄만 더해졌다 - 그 줄을 빼고 계산).
-- =====================================================================
with fn as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         case
           when p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);' then 'checked'
           when p.prosrc like '%assert_can_write%' then 'NOT_FIRST'
           when to_regclass('public.restriction_exemptions') is not null and exists (
             select 1 from jsonb_array_elements(coalesce((xpath('/row/j/text()', query_to_xml(
               'select json_agg(name) as j from public.restriction_exemptions where kind = ''function''', false, true, '')))[1]::text, '[]')::jsonb) e
              where e #>> '{}' = p.proname || '(' || oidvectortypes(p.proargtypes) || ')') then 'exempt'
           else 'MISSING'
         end as state
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
), ex_pol as (
  select e #>> '{}' as name from jsonb_array_elements(coalesce(case when to_regclass('public.restriction_exemptions') is not null then
    (xpath('/row/j/text()', query_to_xml('select json_agg(name) as j from public.restriction_exemptions where kind = ''policy''', false, true, '')))[1]::text end, '[]')::jsonb) e
), pol as (
  select pp.schemaname || '.' || pp.tablename || ': ' || pp.policyname as name, pp.cmd,
         case
           when exists (select 1 from ex_pol x where x.name = pp.schemaname || '.' || pp.tablename || ': ' || pp.policyname) then 'exempt'
           when pp.cmd in ('INSERT', 'UPDATE')
            and coalesce(pp.qual, '') || ' ' || coalesce(pp.with_check, '') ~ '(can_write|media_upload_problem|profile_photo_upload_problem)\(\)' then 'checked'
           when pp.cmd in ('INSERT', 'UPDATE') and to_regprocedure('public.restriction_guard()') is not null and exists (
             select 1 from pg_trigger tg
              where tg.tgrelid = format('%I.%I', pp.schemaname, pp.tablename)::regclass and not tg.tgisinternal and tg.tgenabled <> 'D'
                and tg.tgfoid = to_regprocedure('public.restriction_guard()') and (tg.tgtype & 2) <> 0
                and (tg.tgtype & case pp.cmd when 'INSERT' then 4 else 16 end) <> 0) then 'trigger'
           else 'MISSING'
         end as state
    from pg_policies pp
   where pp.cmd <> 'SELECT' and pp.schemaname in ('public', 'storage') and pp.roles && array['authenticated', 'anon', 'public']::name[]
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '새 표 user_restrictions (칸)' as what,
    coalesce((select string_agg(column_name || ':' || data_type, ', ' order by ordinal_position) from information_schema.columns
               where table_schema = 'public' and table_name = 'user_restrictions'), '없음') as now_value,
    'id:bigint, user_id:uuid, reason:text, days:integer, starts_at:timestamp with time zone, ends_at:timestamp with time zone, created_by:uuid, lifted_at:timestamp with time zone, lifted_by:uuid, lift_note:text' as ok_value, null as memo
  union all select 2, '제한 기록: 탈퇴하면 삭제(cascade 1) / 운영자 칸 set null 2 / RLS 켬 / 정책 수 / 로그인 읽기·쓰기 / 비로그인 읽기',
    case when to_regclass('public.user_restrictions') is null then '없음' else
      (select count(*) filter (where confdeltype = 'c') || ' / ' || count(*) filter (where confdeltype = 'n') from pg_constraint where conrelid = 'public.user_restrictions'::regclass and contype = 'f')
      || ' / ' || (select relrowsecurity::text from pg_class where oid = 'public.user_restrictions'::regclass)
      || ' / ' || (select count(*) from pg_policy where polrelid = 'public.user_restrictions'::regclass)
      || ' / ' || has_table_privilege('authenticated', 'public.user_restrictions', 'select')::text
      || '·' || (has_table_privilege('authenticated', 'public.user_restrictions', 'insert') or has_table_privilege('authenticated', 'public.user_restrictions', 'update')
                 or has_table_privilege('authenticated', 'public.user_restrictions', 'delete'))::text
      || ' / ' || has_table_privilege('anon', 'public.user_restrictions', 'select')::text end,
    '1 / 2 / true / 1 / true·false / false', '본인·운영자만 읽고, 쓰기는 함수로만'
  union all select 3, '허용 목록 restriction_exemptions (함수 줄 / 정책 줄 / RLS 켬 / 로그인·비로그인 읽기)',
    case when to_regclass('public.restriction_exemptions') is null then '없음' else
      (xpath('/row/c/text()', query_to_xml('select count(*) filter (where kind = ''function'') || '' / '' || count(*) filter (where kind = ''policy'') as c from public.restriction_exemptions', false, true, '')))[1]::text
      || ' / ' || (select relrowsecurity::text from pg_class where oid = 'public.restriction_exemptions'::regclass)
      || ' / ' || (has_table_privilege('authenticated', 'public.restriction_exemptions', 'select') or has_table_privilege('anon', 'public.restriction_exemptions', 'select'))::text end,
    '69 / 8 / true / false', null
  union all select 4, '새 함수 9개 (로그인이 부를 수 있는 것: can_write·my_restriction·restrict_user·lift_restriction·admin_member_restrictions)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
       ('active_restriction_id', 'restriction_message', 'assert_can_write', 'can_write', 'my_restriction', 'restrict_user', 'lift_restriction',
        'admin_member_restrictions', 'restriction_guard'))
    || ' / 로그인 ' || (select string_agg(p.proname, '·' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('active_restriction_id', 'restriction_message', 'assert_can_write', 'can_write', 'my_restriction',
          'restrict_user', 'lift_restriction', 'admin_member_restrictions', 'restriction_guard') and has_function_privilege('authenticated', p.oid, 'execute'))
    || ' / 비로그인 ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('active_restriction_id', 'restriction_message', 'assert_can_write', 'can_write', 'my_restriction',
          'restrict_user', 'lift_restriction', 'admin_member_restrictions', 'restriction_guard') and has_function_privilege('anon', p.oid, 'execute')),
    '9 / 로그인 admin_member_restrictions·can_write·lift_restriction·my_restriction·restrict_user / 비로그인 0', null
  union all select 5, '빠뜨림 방지: 쓰기 함수 (검사 / 허용 목록 / 통과 못 한 것)',
    (select count(*) filter (where state = 'checked') || ' / ' || count(*) filter (where state = 'exempt') || ' / '
            || coalesce(string_agg(sig || ' ' || state, ', ') filter (where state not in ('checked', 'exempt')), '없음') from fn),
    '29 / 69 / 없음', '"없음"이 아니면 그 함수가 제한 검사도 허용 목록도 없다는 뜻 - 알려 주세요'
  union all select 6, '빠뜨림 방지: 쓰기 정책 (검사 / 트리거 / 허용 목록 / 통과 못 한 것)',
    (select count(*) filter (where state = 'checked') || ' / ' || count(*) filter (where state = 'trigger') || ' / ' || count(*) filter (where state = 'exempt')
            || ' / ' || coalesce(string_agg(name || ' ' || cmd, ', ') filter (where state = 'MISSING'), '없음') from pol),
    '4 / 1 / 8 / 없음', null
  union all select 7, '표 트리거 a_restriction (모두 / 새 줄을 막는 표 / 지우기를 막는 것 / 꺼진 것)',
    (select count(*) || ' / ' || count(distinct tgrelid) filter (where (tgtype & 4) <> 0) || ' / ' || count(*) filter (where (tgtype & 8) <> 0)
            || ' / ' || count(*) filter (where tgenabled <> 'O')
       from pg_trigger where tgfoid = to_regprocedure('public.restriction_guard()') and not tgisinternal),
    '29 / 19 / 0 / 0', null
  union all select 8, '고친 정책: 직접 넣기 2개에 can_write() / 문의 읽기 정책에 appeal',
    (select count(*) from pg_policies where policyname in ('builds: 본인 이름으로 대기 빌드 등록', 'edit_proposals: 본인 이름으로 대기 제안 작성')
       and with_check like '%can_write()%')
    || ' / ' || (select (qual like '%appeal%')::text from pg_policies where tablename = 'inquiries' and policyname = 'inquiries: 본인·운영진 읽기'),
    '2 / true', null
  union all select 9, '문의 분류 목록에 appeal / 이름 / 처리 기록 종류에 restrict_user·lift_restriction',
    (pg_get_constraintdef((select oid from pg_constraint where conname = 'inquiries_category_check')) like '%appeal%')::text
    || ' / ' || public.inquiry_category_label('appeal')
    || ' / ' || (pg_get_constraintdef((select oid from pg_constraint where conname = 'moderation_log_action_check')) like '%restrict_user%lift_restriction%')::text,
    'true / 이의 제기 / true', null
  union all select 10, '다시 정의한 함수에 고친 내용 (감독관 지정 거절 / 사진 올리기 사전 검사 2개 / 문의 함수 4개에 appeal)',
    (select count(*) from pg_proc where proname = 'set_moderator' and prosrc like '%active_restriction_id(u.id)%')
    || ' / ' || (select count(*) from pg_proc where proname in ('media_upload_problem', 'profile_photo_upload_problem') and prosrc like '%restriction_message(me)%')
    || ' / ' || (select count(*) from pg_proc where proname in ('create_inquiry', 'set_inquiry_category', 'answer_inquiry', 'notify_staff_new_inquiry')
                   and prosrc like '%appeal%'),
    '1 / 2 / 4', null
  union all select 11, '지금 제한 중인 사람 수 / 제한 기록 수',
    case when to_regclass('public.user_restrictions') is null then '없음' else
      (xpath('/row/c/text()', query_to_xml('select count(distinct user_id) filter (where lifted_at is null and ends_at > now()) || '' / '' || count(*) as c from public.user_restrictions', false, true, '')))[1]::text end,
    '0 / 0', '실행 직후 기준. 그 뒤 운영자가 걸면 늘어나는 것이 정상'
  union all select 12, '일반 사용자가 부를 수 있는 쓰기 함수 수',
    (select count(*) from fn)::text, '98', '실행 전 7번(96) + 운영자 함수 2개'
  union all select 13, '적어 둘 값: 빌드 (줄 수 / 가장 큰 id / 추천 수 합계 / 비추천 수 합계 / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || coalesce(sum(up_count), 0) || ' / ' || coalesce(sum(down_count), 0)
       || ' / ' || md5(coalesce(string_agg(b::text, '|' order by b.id), '')) from public.builds b),
    '실행 전 8번과 같음', null
  union all select 14, '적어 둘 값: 빌드 추천·비추천 (줄 수 / 추천 줄 / 비추천 줄 / 내용 지문)',
    (select count(*) || ' / ' || count(*) filter (where value = 1) || ' / ' || count(*) filter (where value = -1)
       || ' / ' || md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')) from public.build_votes v),
    '실행 전 9번과 같음', null
  union all select 15, '적어 둘 값: 빌드 수정 기록 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.build_revisions r),
    '실행 전 10번과 같음', null
  union all select 16, '적어 둘 값: 알림 (줄 수 / 가장 큰 id / 내용 지문 - 읽음 표시는 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / '
       || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), ''))
       from public.notifications n),
    '실행 전 11번과 같음', '그 사이 사이트 활동으로 알림이 생겼다면 늘어난 것이 정상'
  union all select 17, '적어 둘 값: 빌드 저장(북마크) (줄 수 / 내용 지문)',
    (select count(*) || ' / ' || md5(coalesce(string_agg(k::text, '|' order by k.user_id::text, k.build_id), '')) from public.build_bookmarks k),
    '실행 전 12번과 같음', null
  union all select 18, '적어 둘 값: 글 / 댓글 / 문서 댓글 (줄 수 · 가장 큰 id · 내용 지문)',
    (select count(*) || '·' || coalesce(max(id), 0) || '·' || left(md5(coalesce(string_agg(p::text, '|' order by p.id), '')), 12) from public.posts p)
      || ' / ' || (select count(*) || '·' || coalesce(max(id), 0) || '·' || left(md5(coalesce(string_agg(c::text, '|' order by c.id), '')), 12) from public.post_comments c)
      || ' / ' || (select count(*) || '·' || coalesce(max(id), 0) || '·' || left(md5(coalesce(string_agg(d::text, '|' order by d.id), '')), 12) from public.doc_comments d),
    '실행 전 13번과 같음', null
  union all select 19, '적어 둘 값: 상대법 / 제안 / 팔로우 / 신고 (줄 수)',
    (select count(*) from public.counters) || ' / ' || (select count(*) from public.edit_proposals) || ' / ' || (select count(*) from public.influencer_follows)
      || ' / ' || (select count(*) from public.reports) || '+' || (select count(*) from public.wiki_reports) || '+' || (select count(*) from public.link_reports)
      || '+' || (select count(*) from public.profile_photo_reports),
    '실행 전 14번과 같음', null
  union all select 20, '적어 둘 값: 문의 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(i::text, '|' order by i.id), '')) from public.inquiries i),
    '실행 전 15번과 같음', null
  union all select 21, '적어 둘 값: 처리 기록 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(m::text, '|' order by m.id), '')) from public.moderation_log m),
    '실행 전 16번과 같음', '그 뒤 운영자가 제한을 걸거나 풀면 늘어나는 것이 정상'
  union all select 22, '적어 둘 값: 프로필 (줄 수 / 내용 지문 - 마지막 접속 시각은 빼고)',
    (select count(*) || ' / ' || md5(coalesce(string_agg((to_jsonb(p) - 'last_seen_at')::text, '|' order by p.id), '')) from public.profiles p),
    '실행 전 17번과 같음', null
  union all select 23, '기존 함수 29개: 검사 한 줄을 뺀 본문·보안·search_path·권한 지문',
    (select count(*) || ' / ' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')'
            || replace(p.prosrc, E'\n  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)', '')
            || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(p.proacl::text, ''), '|' order by p.proname))
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in (
      'apply_influencer','begin_edit','create_build','create_comment','create_doc_comment','create_matchup','create_post',
      'edit_build','edit_comment','edit_doc_comment','edit_my_build','edit_my_proposal','edit_post','follow_influencer',
      'report_comment','report_doc_comment','report_link','report_post','report_profile_photo','report_wiki',
      'resubmit_build','resubmit_proposal','save_build','set_application_photo','set_build_link','set_profile_links',
      'set_profile_photo','vote_build','vote_post')),
    '실행 전 18번과 같음', '다르면 검사 한 줄 말고 다른 것이 바뀐 것 - 알려 주세요'
) x
order by ord;
