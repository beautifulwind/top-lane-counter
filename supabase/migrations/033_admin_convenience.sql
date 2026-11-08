-- =====================================================================
-- 033: 관리자 편의 개선 (2026-11-08, SPEC 6-20)
-- 1. 새 제안·새 빌드·새 문의가 들어오면 운영진에게 알림 (기존 notifications 재사용)
--    - 알림 종류 proposal_submitted · build_submitted · inquiry_received 추가
--    - 운영자: 모든 새 제안·빌드·문의. 감독관: 자기가 처리할 수 있는 것만
--      (다른 일반 회원의 새 카운터 제안, "계정·탈퇴"가 아닌 문의 — 030·032와 같은 규칙)
--    - 제안·빌드를 낸 사람이 운영진 본인이면 본인에게는 보내지 않는다 (notify 도우미가 거른다)
--    - 만드는 곳은 표 트리거라서 화면·함수 어느 쪽으로 들어와도 빠지지 않는다
--    - 알림 문장은 그 자체로 읽히는 완성 문장 (옛 화면은 모르는 종류를 문장 그대로 보여 준다)
-- 2. 관리 메뉴 처리 대기 건수: admin_pending_counts() — 운영진만, 역할에 맞는 건수만 센다
-- 3. 감독관도 제안 내용을 고쳐서 승인할 수 있다 (030의 "고쳐서 승인 불가" 제한을 푼다)
--    - 감독관은 원래부터 처리할 수 있는 제안(다른 일반 회원의 새 카운터)만 고칠 수 있다
--    - 고쳤으면 moderation_log에 edit_proposal 한 줄: 누가(처리자) · 어느 제안 · 어느 칸을 고쳤는지
--      (원래 제안과 고친 내용 전체는 edit_proposals.content ↔ approved_content·approved_build에 이미 남는다)
--    - 031 "검토 중" 표시(proposal_reviewing)와 version 확인은 그대로: 고치는 동안 표시는 화면이 갱신하고,
--      제안자가 먼저 고쳤거나 다른 분이 먼저 처리했으면 승인이 거부된다 (내용을 덮어쓰지 않는다)
--
-- 하위 호환: 있던 표·함수의 모양은 바꾸지 않는다 (알림·처리 기록 종류 목록을 넓히고, 승인 함수에서 제한 한 줄만 바꾼다).
-- 지금 배포된 화면과 그대로 동작한다. 순서: 이 파일 실행 → supabase/scripts/check_admin_convenience.sql로 확인 → 새 코드 push.
-- 032까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 알림 종류, 처리 기록 종류
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in ('revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected', 'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked', 'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked', 'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received'));

alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action in (
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal'));

-- ---------------------------------------------------------------------
-- 2. 운영진에게 알림 보내기 (트리거가 부르는 안쪽 함수 — 아무도 직접 못 부른다)
--    p_moderators = 감독관에게도 보낼지. 운영자는 항상. 지금 처리하는 본인(auth.uid())은 뺀다.
-- ---------------------------------------------------------------------
create function public.notify_staff(p_kind text, p_message text, p_proposal bigint, p_build bigint, p_moderators boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.notifications (user_id, kind, message, proposal_id, build_id)
  select u.id, p_kind, p_message, p_proposal, p_build
    from public.profiles u
   where (u.role = 'admin' or (p_moderators and u.role = 'moderator'))
     and u.id is distinct from (select auth.uid());
end;
$$;

-- 새 제안 (또는 재검토 뒤 다시 낸 제안)
create function public.notify_staff_new_proposal()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  again boolean := tg_op = 'UPDATE';
  msg text;
  mod_ok boolean;
begin
  if again then
    msg := '재검토 후 다시 낸 제안이 들어왔습니다.';
  elsif new.type = 'new_counter' then
    msg := '새 카운터 제안이 들어왔습니다.';
  else
    msg := '문서 수정 제안이 들어왔습니다.';
  end if;
  -- 감독관이 처리할 수 있는 제안: 새 카운터(숨긴 카운터 재검토 제외), 제안자가 일반 회원 (require_review_allowed와 같은 규칙)
  mod_ok := new.type = 'new_counter' and new.counter_id is null
            and exists (select 1 from public.profiles where id = new.proposer_id and role = 'user');
  perform public.notify_staff('proposal_submitted', msg, new.id, null, mod_ok);
  return null;
end;
$$;
create trigger edit_proposals_notify_staff_insert
  after insert on public.edit_proposals
  for each row when (new.status = 'pending')
  execute function public.notify_staff_new_proposal();
create trigger edit_proposals_notify_staff_resubmit
  after update of status on public.edit_proposals
  for each row when (old.status = 'revision_requested' and new.status = 'pending'
                     and new.resubmitted_at is distinct from old.resubmitted_at)
  execute function public.notify_staff_new_proposal();

-- 새 빌드 (또는 재검토 뒤 다시 낸 빌드): 빌드 처리는 운영자만 한다 (감독관 권한 없음)
create function public.notify_staff_new_build()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.notify_staff('build_submitted',
    case when tg_op = 'UPDATE' then '재검토 후 다시 낸 빌드가 들어왔습니다.' else '새 빌드 제안이 들어왔습니다.' end,
    null, new.id, false);
  return null;
end;
$$;
create trigger builds_notify_staff_insert
  after insert on public.builds
  for each row when (new.status = 'pending')
  execute function public.notify_staff_new_build();
create trigger builds_notify_staff_resubmit
  after update of status on public.builds
  for each row when (old.status = 'revision_requested' and new.status = 'pending'
                     and new.resubmitted_at is distinct from old.resubmitted_at)
  execute function public.notify_staff_new_build();

-- 새 문의: 운영자는 전부, 감독관은 "계정·탈퇴"가 아닌 것만 (032의 읽기 규칙과 같다)
create function public.notify_staff_new_inquiry()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    -- 운영자가 분류를 옮겨서 감독관에게 보이게 됐을 때 (계정·탈퇴 → 다른 분류), 아직 답이 없을 때만
    if new.answer is not null or old.category <> 'account' or new.category = 'account' then
      return null;
    end if;
    insert into public.notifications (user_id, kind, message)
    select u.id, 'inquiry_received',
           format('새 문의가 들어왔습니다. (분류: %s)', public.inquiry_category_label(new.category))
      from public.profiles u
     where u.role = 'moderator' and u.id is distinct from new.user_id;
    return null;
  end if;
  insert into public.notifications (user_id, kind, message)
  select u.id, 'inquiry_received',
         format('새 문의가 들어왔습니다. (분류: %s)', public.inquiry_category_label(new.category))
    from public.profiles u
   where (u.role = 'admin' or (u.role = 'moderator' and new.category <> 'account'))
     and u.id is distinct from new.user_id;
  return null;
end;
$$;
create trigger inquiries_notify_staff_insert
  after insert on public.inquiries
  for each row execute function public.notify_staff_new_inquiry();
create trigger inquiries_notify_staff_move
  after update of category on public.inquiries
  for each row when (old.category = 'account' and new.category <> 'account')
  execute function public.notify_staff_new_inquiry();

-- ---------------------------------------------------------------------
-- 3. 관리 메뉴 처리 대기 건수 (운영진만, 역할에 맞는 건수만)
--    운영자: 승인 대기 제안 · 승인 대기 빌드 · 답변 대기 문의(내가 보낸 것 제외)
--    감독관: 다른 일반 회원의 새 카운터 제안 · 빌드는 0 · "계정·탈퇴"가 아닌 답변 대기 문의(내가 보낸 것 제외)
-- ---------------------------------------------------------------------
create function public.admin_pending_counts()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  perform public.require_staff();
  if public.is_admin() then
    return jsonb_build_object(
      'proposals', (select count(*) from public.edit_proposals where status = 'pending'),
      'builds', (select count(*) from public.builds where status = 'pending'),
      'inquiries', (select count(*) from public.inquiries where answer is null and user_id <> me));
  end if;
  return jsonb_build_object(
    'proposals', (select count(*) from public.edit_proposals
                   where status = 'pending' and type = 'new_counter' and counter_id is null
                     and proposer_id <> me and public.moderatable_author(proposer_id)),
    'builds', 0,
    'inquiries', (select count(*) from public.inquiries where answer is null and user_id <> me and category <> 'account'));
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 고친 곳 설명 (처리 기록용): "한 줄 요약, 3·6레벨 딜교법, 특이사항, 룬, 핵심 템트리"
-- ---------------------------------------------------------------------
create function public.describe_proposal_edit(o_doc jsonb, n_doc jsonb, o_build jsonb, n_build jsonb)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  parts text[] := '{}';
  lv text;
begin
  if (o_doc ->> 'summary') is distinct from (n_doc ->> 'summary') then
    parts := array_append(parts, '한 줄 요약');
  end if;
  select string_agg(k.key, '·' order by k.key::integer) into lv
    from (
      select key from jsonb_object_keys(coalesce(o_doc -> 'level_notes', '{}'::jsonb)) as key
      union
      select key from jsonb_object_keys(coalesce(n_doc -> 'level_notes', '{}'::jsonb)) as key
    ) k
   where (o_doc -> 'level_notes' -> k.key) is distinct from (n_doc -> 'level_notes' -> k.key);
  if lv is not null then
    parts := array_append(parts, lv || '레벨 딜교법');
  end if;
  if (o_doc ->> 'lane_cautions') is distinct from (n_doc ->> 'lane_cautions') then
    parts := array_append(parts, '특이사항');
  end if;
  if o_build is not null and n_build is not null then
    if (o_build -> 'runes') is distinct from (n_build -> 'runes') then parts := array_append(parts, '룬'); end if;
    if (o_build -> 'summoner_spells') is distinct from (n_build -> 'summoner_spells') then parts := array_append(parts, '소환사 주문'); end if;
    if (o_build -> 'starting_items') is distinct from (n_build -> 'starting_items') then parts := array_append(parts, '시작 아이템'); end if;
    if (o_build -> 'core_items') is distinct from (n_build -> 'core_items') then parts := array_append(parts, '핵심 템트리'); end if;
    if (o_build -> 'max_skill') is distinct from (n_build -> 'max_skill') then parts := array_append(parts, '선마'); end if;
  end if;
  return array_to_string(parts, ', ');
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 감독관도 고쳐서 승인: 승인 함수 안의 제한 한 곳을 "처리 기록 남기기"로 바꾼다
--    (긴 함수를 통째로 다시 쓰지 않고, 지금 DB에 있는 정의에서 그 부분만 바꾼다 — 031과 같은 방식)
--    기록은 승인과 같은 처리 안에서 남으므로, 승인이 실패해 되돌려지면 기록도 함께 사라진다.
-- ---------------------------------------------------------------------
do $$
declare
  f oid;
  old_def text;
  new_def text;
begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'approve_proposal_unchecked';
  old_def := pg_get_functiondef(f);
  new_def := replace(old_def,
$s$  -- 감독관은 고쳐서 승인할 수 없다 (그대로 승인 또는 반려)
  if public.is_moderator() and (new_doc is distinct from orig_doc or new_build is distinct from orig_build) then
    raise exception '감독관은 내용을 고쳐서 승인할 수 없습니다.' using errcode = '42501';
  end if;
$s$,
$s$  -- 운영자·감독관이 고쳤으면 누가 무엇을 고쳤는지 처리 기록에 남긴다 (033)
  if new_doc is distinct from orig_doc or new_build is distinct from orig_build then
    perform public.log_moderation('edit_proposal', 'proposal', p.id::text,
      '고친 곳: ' || public.describe_proposal_edit(orig_doc, new_doc, orig_build, new_build));
  end if;
$s$);
  if new_def = old_def then
    raise exception 'approve_proposal_unchecked에서 바꿀 부분을 찾지 못했습니다. (이미 033을 실행했거나, 030 이후 정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.notify_staff(text, text, bigint, bigint, boolean) from public, anon, authenticated;
revoke execute on function public.notify_staff_new_proposal() from public, anon, authenticated;
revoke execute on function public.notify_staff_new_build() from public, anon, authenticated;
revoke execute on function public.notify_staff_new_inquiry() from public, anon, authenticated;
revoke execute on function public.describe_proposal_edit(jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
revoke execute on function public.admin_pending_counts() from public, anon;
grant execute on function public.admin_pending_counts() to authenticated;  -- 운영진인지는 함수 안에서 DB가 검사

commit;

-- 확인 (실행 뒤): supabase/scripts/check_admin_convenience.sql
