-- =====================================================================
-- 036: 운영자 회원 현황·검색 + 감독관 재검토 요청 (2026-11-10, SPEC 6-23)
--
-- 1. 가입자 수 (운영자 전용): admin_member_stats()
--    총 가입자(프로필 수, 비회원 포함), 정식 회원, 비회원, 구글·카카오 연결 수(둘 다 연결한 회원은 양쪽에 센다),
--    최근 7일 신규(전체 / 정식 회원). 숫자만 돌려준다.
-- 2. 닉네임 검색과 회원 정보 (운영자 전용)
--    admin_search_members(검색어): 닉네임 부분 일치(대소문자 무시), 최대 10명, 닉네임 1글자 이상, 더 불러오는 방법 없음.
--    admin_member_info(회원): 가입일, 가입 방식(구글·카카오·비회원), 레벨·대표 칭호·얻은 칭호, 활동 수(제안·글·빌드·댓글).
--    이메일·로그인 ID(provider_id)·이름·프로필 사진·접속 기록은 읽지도 돌려주지도 않는다 (auth.identities에서는 provider 이름만).
--    권한은 require_operator() = is_admin(): 운영자만. 감독관과 일반 회원은 오류, 운영자 모드를 끈 운영자도 오류.
-- 3. 감독관의 재검토 요청
--    감독관이 지금 하는 일은 승인(고쳐서 승인 포함)·반려·글/댓글 숨김과 다시 공개·신고 처리·문의 답변(계정 분류 제외)이고,
--    새 카운터 제안(대기 중, 일반 회원, 숨긴 카운터 제안 제외)에서 빠진 것은 "재검토 요청" 하나였다 → 추가한다.
--    - request_proposal_revision(·_unchecked): require_operator → require_staff + require_review_allowed
--      (승인·반려와 같은 범위 검사: 본인·운영진 제안, 문서 수정 제안, 숨긴 카운터 제안, 이미 처리된 제안은 거부)
--    - 감독관이 하면 revision_requested_by를 비운다 (승인·반려의 reviewed_by와 같은 방식: 누가 했는지는 처리 기록에만)
--    - 처리 기록: 새 종류 request_revision (운영자가 해도 남는다)
--    - 그대로인 것: 제안자 알림(notify), 알림 문장, 검토 잠금(제안이 대기를 벗어나면 트리거가 표시를 지움),
--      재검토 요청 취소·문서 수정 제안·빌드 처리는 운영자만 (감독관은 재검토 중인 제안을 읽지도 못한다)
--
-- 하위 호환: 있던 함수의 이름·인자·반환은 그대로, 새 함수만 더한다. 운영자의 동작도 같다 (처리 기록 한 줄이 더 남는 것만 다름).
-- 지금 배포된 화면과 그대로 동작한다. 순서: 이 파일 실행 → supabase/scripts/check_member_info.sql로 확인 → 새 코드 push.
-- 035까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 가입자 수
-- ---------------------------------------------------------------------
create function public.admin_member_stats()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  perform public.require_operator();
  with ids as (
    select user_id, bool_or(provider = 'google') as g, bool_or(provider = 'kakao') as k
    from auth.identities group by user_id
  )
  select jsonb_build_object(
    'total', count(*),
    'members', count(*) filter (where not p.is_guest),
    'guests', count(*) filter (where p.is_guest),
    'google', count(*) filter (where not p.is_guest and coalesce(i.g, false)),
    'kakao', count(*) filter (where not p.is_guest and coalesce(i.k, false)),
    'both', count(*) filter (where not p.is_guest and coalesce(i.g, false) and coalesce(i.k, false)),
    'new_7d', count(*) filter (where p.created_at >= now() - interval '7 days'),
    'new_7d_members', count(*) filter (where p.created_at >= now() - interval '7 days' and not p.is_guest)
  ) into result
  from public.profiles p left join ids i on i.user_id = p.id;
  return result;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. 닉네임 검색, 회원 정보
-- ---------------------------------------------------------------------
create function public.admin_search_members(p_query text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  q text := btrim(coalesce(p_query, ''));
begin
  perform public.require_operator();
  if q = '' then
    raise exception '찾을 닉네임을 적어 주세요.' using errcode = '22023';
  end if;
  if char_length(q) > 20 then
    raise exception '닉네임은 20자까지입니다.' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', x.id, 'nickname', x.nickname, 'role', x.role, 'level', x.level,
             'main_title', x.main_title, 'is_guest', x.is_guest, 'created_at', x.created_at)
           order by x.nickname)
    from (
      select id, nickname, role, level, main_title, is_guest, created_at
        from public.profiles
       where nickname is not null
         and nickname ilike '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%' escape '\'
       order by nickname
       limit 10
    ) x
  ), '[]'::jsonb);
end;
$$;

create function public.admin_member_info(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  u public.profiles%rowtype;
begin
  perform public.require_operator();
  select * into u from public.profiles where id = p_user;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'id', u.id, 'nickname', u.nickname, 'role', u.role, 'level', u.level, 'main_title', u.main_title,
    'is_guest', u.is_guest, 'created_at', u.created_at,
    -- 가입 방식: provider 이름만 (구글·카카오). 로그인 ID·이메일은 읽지 않는다
    'providers', coalesce((
      select jsonb_agg(provider order by provider)
        from (select distinct provider from auth.identities where user_id = u.id and provider in ('google', 'kakao')) s
    ), '[]'::jsonb),
    'titles', coalesce((select jsonb_agg(title_key order by title_key) from public.user_titles where user_id = u.id), '[]'::jsonb),
    'proposals', (select count(*) from public.edit_proposals where proposer_id = u.id),
    'posts', (select count(*) from public.posts where author_id = u.id and deleted_at is null),
    'builds', (select count(*) from public.builds where author_id = u.id),
    'comments', (select count(*) from public.post_comments where author_id = u.id)
              + (select count(*) from public.doc_comments where author_id = u.id)
  );
end;
$$;

revoke execute on function public.admin_member_stats() from public, anon;
revoke execute on function public.admin_search_members(text) from public, anon;
revoke execute on function public.admin_member_info(uuid) from public, anon;
grant execute on function public.admin_member_stats() to authenticated;       -- 운영자인지는 함수 안에서 검사
grant execute on function public.admin_search_members(text) to authenticated;
grant execute on function public.admin_member_info(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. 감독관 재검토 요청
-- ---------------------------------------------------------------------
alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action in (
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision'));

-- 긴 함수를 통째로 다시 쓰지 않고, 지금 DB에 있는 정의에서 그 부분만 바꾼다 (031·034와 같은 방식)
do $$
declare
  f oid;
  old_def text;
  new_def text;
begin
  -- 바깥 함수(화면이 부르는 것): 운영자 → 운영진
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'request_proposal_revision' and p.pronargs = 3;
  old_def := pg_get_functiondef(f);
  new_def := replace(old_def, 'perform public.require_operator();', 'perform public.require_staff();');
  if new_def = old_def then
    raise exception 'request_proposal_revision에서 바꿀 부분을 찾지 못했습니다. (이미 036을 실행했거나 정의가 달라졌습니다)';
  end if;
  execute new_def;

  -- 안쪽 함수
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'request_proposal_revision_unchecked';
  old_def := pg_get_functiondef(f);
  new_def := replace(old_def, 'perform public.require_operator();', 'perform public.require_staff();');
  if new_def = old_def then
    raise exception 'request_proposal_revision_unchecked: 권한 줄을 찾지 못했습니다.';
  end if;
  -- 감독관은 승인·반려와 같은 범위(대기 중인 일반 회원의 새 카운터 제안)만. 운영자는 그대로 통과
  old_def := new_def;
  new_def := replace(old_def,
$s$  if p.status = 'revision_requested' then
    raise exception '이미 재검토를 요청했습니다.$s$,
$s$  perform public.require_review_allowed(p);
  if p.status = 'revision_requested' then
    raise exception '이미 재검토를 요청했습니다.$s$);
  if new_def = old_def then
    raise exception 'request_proposal_revision_unchecked: 상태 검사 줄을 찾지 못했습니다.';
  end if;
  -- 감독관이 하면 읽을 수 있는 칸에 처리자를 남기지 않는다 (누가 했는지는 처리 기록에만)
  old_def := new_def;
  new_def := replace(old_def,
$s$revision_requested_by = (select auth.uid()), revision_requested_at = now()
   where id = p.id;$s$,
$s$revision_requested_by = case when public.is_moderator() then null else (select auth.uid()) end, revision_requested_at = now()
   where id = p.id;$s$);
  if new_def = old_def then
    raise exception 'request_proposal_revision_unchecked: 갱신 줄을 찾지 못했습니다.';
  end if;
  -- 처리 기록
  old_def := new_def;
  new_def := replace(old_def,
$s$  perform public.notify(p.proposer_id, 'revision_request', note, p.id, null);
end;$s$,
$s$  perform public.notify(p.proposer_id, 'revision_request', note, p.id, null);
  perform public.log_moderation('request_revision', 'proposal', p.id::text, note);
end;$s$);
  if new_def = old_def then
    raise exception 'request_proposal_revision_unchecked: 알림 줄을 찾지 못했습니다.';
  end if;
  execute new_def;
end;
$$;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_member_info.sql
