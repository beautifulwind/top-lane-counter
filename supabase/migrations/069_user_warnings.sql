-- =====================================================================
-- 069: 운영자 경고 (2026-11-23, SPEC 6-86) - 새 표 1개, 새 함수 6개, 새 트리거 1개(알림 읽음), 기존 함수 1개(push_group)·제약 2개 고침.
--
-- 1. 운영자(admin, 운영자 모드 켬)만 warn_user(대상, 내용 1~500자)로 보낸다. 자기 자신·운영자에게는 못 보낸다(감독관·일반 회원·비회원은 됨).
--    활동 제한(068)과는 따로다. 보낼 때 그 사람에게 활동 제한이 걸려 있으면(함께 처리한 것) 그 제한 번호를 restriction_id에 남긴다.
-- 2. 기록 표 user_warnings: 내용은 본인과 운영자만 읽는다(RLS, 감독관 제외). 직접 쓰기 권한 없음(함수로만). 탈퇴하면 함께 지워진다.
--    처리 기록(moderation_log)에는 내용을 남기지 않는다(활동 제한과 함께면 「활동 제한과 함께」만).
-- 3. 본인은 화면 위 안내 상자 「운영자 경고를 받았습니다」 + 내용 + [확인했습니다] → ack_warning(번호)이 확인 시각을 남긴다.
--    본인 것만, 이미 확인했으면 그대로 성공, 활동 제한 중에도 된다(068 허용 목록에 이유와 함께 추가). 확인하면 그 알림도 읽음이 된다.
--    안 본 경고는 my_warnings()가 돌려준다(오래된 것부터).
-- 4. 알림 warning_received 「운영자 경고를 받았습니다. 화면 위 안내에서 내용을 확인해 주세요.」 - 내용(메모)은 넣지 않는다(잠금 화면에도 보이므로).
--    휴대폰 알림 묶음은 「내 처리 결과」(my_results). 옛 앱(1.1 이하)은 모르는 종류라 종 아이콘 + 이 문장만 보인다(오류 없음).
--    알림을 읽으면(알림 화면 열기 등) 트리거가 그 시각을 경고 기록(notice_read_at)에도 남긴다 → 알림이 90일 뒤 지워져도 상태가 남는다.
-- 5. 운영자 화면 상태: 확인함(acked_at) / 알림만 읽음(notice_read_at) / 아직. admin_member_warnings(회원)가 돌려준다.
--
-- 실행 전 supabase/scripts/check_warnings_before.sql, 실행 뒤 check_warnings_after.sql (함수 본문은 줄바꿈 CR을 뺀 값으로 비교).
-- 068까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 그 뒤에 새 화면을 배포(푸시)한다.
-- (먼저 배포해도 화면은 죽지 않는다: 069 전 DB면 경고 안내 상자는 안 뜨고 운영자 칸은 「준비 중」으로 보인다.)
-- 기존 빌드·추천·수정 기록·알림·북마크·활동 제한·처리 기록 등 데이터는 바꾸지 않는다(실행 전후 확인이 줄 수·가장 큰 id·내용 지문을 비교).
-- 068의 check_restrictions_after.sql을 069 뒤에 다시 돌리면 허용 목록이 69 → 71(함수 2개 추가)로 나오는 것이 정상이다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 068 상태로 돌아간다.
--    069가 만든 경고 기록·경고 알림(warning_received)·처리 기록 warn_user 줄은 지워진다(종류 목록에서 빠지므로).
--    push_group은 067 내용 그대로 돌아간다.
--     begin;
--     -- 1) 경고 알림 읽음 트리거·함수
--     drop trigger notifications_warning_read on public.notifications;
--     drop function public.admin_member_warnings(uuid);
--     drop function public.my_warnings();
--     drop function public.ack_warning(bigint);
--     drop function public.warn_user(uuid, text);
--     drop function public.warning_notice_message();
--     drop function public.warning_notice_read();
--     -- 2) 허용 목록·처리 기록 종류를 068 모양으로
--     delete from public.restriction_exemptions where kind = 'function' and name in ('warn_user(uuid, text)', 'ack_warning(bigint)');
--     delete from public.moderation_log where action = 'warn_user';
--     alter table public.moderation_log drop constraint moderation_log_action_check;
--     alter table public.moderation_log add constraint moderation_log_action_check check (action in (
--       'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
--       'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report',
--       'dismiss_report', 'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
--       'remove_link', 'add_link_domain', 'remove_link_domain', 'grant_influencer', 'grant_title', 'revoke_title',
--       'remove_profile_photo',
--       'restrict_user', 'lift_restriction'));
--     -- 3) 경고 기록 표 (알림보다 먼저 - 알림을 가리킨다)
--     drop table public.user_warnings;
--     -- 4) 알림 종류·휴대폰 알림 묶음을 067 모양으로 (069가 만든 경고 알림은 종류 목록에서 빠지므로 먼저 지움)
--     delete from public.notifications where kind = 'warning_received';
--     alter table public.notifications drop constraint notifications_kind_check;
--     alter table public.notifications add constraint notifications_kind_check check (kind in (
--       'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved',
--       'build_rejected', 'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
--       'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment',
--       'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked', 'inquiry_answered',
--       'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored', 'matchup_created',
--       'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created', 'error_reported',
--       'error_report_handled', 'report_received', 'influencer_applied', 'influencer_received', 'influencer_expiring',
--       'influencer_approved', 'influencer_rejected', 'influencer_expired', 'influencer_revoked',
--       'nickname_reset_soon', 'nickname_reset', 'link_removed', 'followed_build_created', 'notice_posted',
--       'new_followers', 'comment_reply', 'profile_photo_removed',
--       'build_edited'));
--     create or replace function public.push_group(p_kind text)
--     returns text language sql immutable set search_path = ''
--     as $$
--       select case
--         when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
--                         'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
--         when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--                         'revision_request', 'counter_restored', 'build_restored',
--                         'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--                         'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
--                         'profile_photo_removed') then 'my_results'  -- 062: 링크 삭제와 같은 묶음
--         when p_kind in ('followed_build_created') then 'follow_builds'
--         when p_kind in ('notice_posted') then 'notice'
--         when p_kind in ('new_followers') then 'new_followers'
--         when p_kind in ('build_edited') then 'build_edits'  -- 067 빌드 수정 알림
--       end;
--     $$;
--     commit;
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 경고 기록 표 (탈퇴하면 함께 지워진다 - 2026-11-22 결정, 068 활동 제한과 같음)
-- ---------------------------------------------------------------------
create table public.user_warnings (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references public.profiles (id) on delete cascade,        -- 경고 받는 사람 (탈퇴 → 기록 삭제)
  memo            text not null check (char_length(btrim(memo)) between 1 and 500),        -- 경고 내용 (본인에게 그대로 보인다)
  created_at      timestamptz not null default now(),
  created_by      uuid references public.profiles (id) on delete set null,                -- 보낸 운영자
  restriction_id  bigint references public.user_restrictions (id) on delete set null,     -- 보낼 때 걸려 있던 활동 제한 (함께 처리한 것)
  notification_id bigint references public.notifications (id) on delete set null,         -- 보낸 알림 (90일 뒤 알림이 지워지면 null)
  notice_read_at  timestamptz,                                                            -- 알림을 읽은 시각 (알림이 지워져도 남는다)
  acked_at        timestamptz                                                             -- 본인이 [확인했습니다]를 누른 시각
);
comment on table public.user_warnings is '069 운영자 경고. 운영자만 보낸다(warn_user). 본인·운영자만 읽는다. 본인이 ack_warning으로 확인한다. 탈퇴하면 지워진다';
create index user_warnings_user_idx on public.user_warnings (user_id, id desc);
create index user_warnings_unacked_idx on public.user_warnings (user_id) where acked_at is null;
create index user_warnings_created_by_idx on public.user_warnings (created_by);
create index user_warnings_restriction_idx on public.user_warnings (restriction_id);
create index user_warnings_notification_idx on public.user_warnings (notification_id);
alter table public.user_warnings enable row level security;
revoke all on public.user_warnings from public, anon, authenticated;
grant select on public.user_warnings to authenticated;
create policy "user_warnings: 본인·운영자 읽기" on public.user_warnings
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());

-- ---------------------------------------------------------------------
-- 2. 알림 종류 warning_received + 휴대폰 알림 묶음 (내 처리 결과 my_results)
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in (
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved',
  'build_rejected', 'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment',
  'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked', 'inquiry_answered',
  'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored', 'matchup_created',
  'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created', 'error_reported',
  'error_report_handled', 'report_received', 'influencer_applied', 'influencer_received', 'influencer_expiring',
  'influencer_approved', 'influencer_rejected', 'influencer_expired', 'influencer_revoked',
  'nickname_reset_soon', 'nickname_reset', 'link_removed', 'followed_build_created', 'notice_posted',
  'new_followers', 'comment_reply', 'profile_photo_removed',
  'build_edited',
  'warning_received'));  -- 069 운영자 경고

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored',
                    'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
                    'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
                    'profile_photo_removed',
                    'warning_received') then 'my_results'  -- 062: 링크 삭제와 같은 묶음, 069: 운영자 경고도
    when p_kind in ('followed_build_created') then 'follow_builds'
    when p_kind in ('notice_posted') then 'notice'
    when p_kind in ('new_followers') then 'new_followers'
    when p_kind in ('build_edited') then 'build_edits'  -- 067 빌드 수정 알림
  end;
$$;

-- 경고 알림을 읽으면(알림 화면을 열거나 [확인했습니다]) 그 시각을 경고 기록에도 남긴다 (알림은 90일 뒤 지워지므로)
create function public.warning_notice_read()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update public.user_warnings set notice_read_at = new.read_at
   where notification_id = new.id and notice_read_at is null;
  return null;
end;
$$;
create trigger notifications_warning_read after update of read_at on public.notifications
  for each row when (new.kind = 'warning_received' and old.read_at is null and new.read_at is not null)
  execute function public.warning_notice_read();

-- ---------------------------------------------------------------------
-- 3. 운영자: 경고 보내기 · 기록 보기 / 본인: 안 본 경고 · [확인했습니다]
-- ---------------------------------------------------------------------
-- 알림 문장 (메모는 넣지 않는다 - 휴대폰 잠금 화면에도 보이므로. 내용은 화면 위 안내 상자에서 본인만 본다)
create function public.warning_notice_message()
returns text language sql immutable set search_path = ''
as $$
  select '운영자 경고를 받았습니다. 화면 위 안내에서 내용을 확인해 주세요.'::text;
$$;

create function public.warn_user(p_user uuid, p_memo text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  memo text := btrim(coalesce(p_memo, ''), E' \t\r\n');
  u public.profiles%rowtype;
  w public.user_warnings%rowtype;
  nid bigint;
begin
  perform public.require_operator();
  if memo = '' then
    raise exception '경고 내용을 적어 주세요.' using errcode = '22023';
  end if;
  if char_length(memo) > 500 then
    raise exception '경고 내용은 500자까지 적을 수 있습니다.' using errcode = '22023';
  end if;
  select * into u from public.profiles where id = p_user;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if u.id = me then
    raise exception '자기 자신에게는 경고를 보낼 수 없습니다.' using errcode = '42501';
  end if;
  if u.role = 'admin' then
    raise exception '운영자에게는 경고를 보낼 수 없습니다.' using errcode = '42501';
  end if;
  -- 활동 제한과는 따로다. 지금 제한이 걸려 있으면(함께 처리한 것) 그 번호를 남긴다
  insert into public.notifications (user_id, kind, message)
  values (u.id, 'warning_received', public.warning_notice_message())
  returning id into nid;
  insert into public.user_warnings (user_id, memo, created_by, restriction_id, notification_id)
  values (u.id, memo, me, public.active_restriction_id(u.id), nid)
  returning * into w;
  -- 처리 기록에는 내용을 남기지 않는다 (내용은 탈퇴 때 함께 지워지도록 경고 기록에만 둔다)
  perform public.log_moderation('warn_user', 'user', u.id::text,
    case when w.restriction_id is not null then '활동 제한과 함께' end, u.nickname);
  return jsonb_build_object('id', w.id, 'restriction_id', w.restriction_id);
end;
$$;

-- 본인: [확인했습니다]. 이미 확인했으면 그대로 성공. 활동 제한 중에도 된다(허용 목록)
create function public.ack_warning(p_id bigint)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  w public.user_warnings%rowtype;
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  select * into w from public.user_warnings where id = p_id and user_id = me for update;
  if not found then
    raise exception '경고를 찾지 못했습니다.' using errcode = 'P0002';  -- 남의 경고도 같은 문장 (있는지 알려 주지 않음)
  end if;
  if w.acked_at is null then
    update public.user_warnings set acked_at = now() where id = w.id returning * into w;
    update public.notifications set read_at = now() where id = w.notification_id and read_at is null;  -- 알림도 읽음으로
  end if;
  return jsonb_build_object('id', w.id, 'acked_at', w.acked_at);
end;
$$;

-- 화면 안내 상자: 아직 확인하지 않은 내 경고 (오래된 것부터) [{ id, memo, created_at }]
create function public.my_warnings()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'memo', w.memo, 'created_at', w.created_at) order by w.id), '[]'::jsonb)
    from public.user_warnings w
   where w.user_id = (select auth.uid()) and w.acked_at is null;
$$;

-- 회원 관리 화면: 그 회원이 받은 경고 (최근 것부터). state = acked(확인함) / read(알림만 읽음) / unread(아직)
create function public.admin_member_warnings(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', w.id, 'memo', w.memo, 'created_at', w.created_at, 'created_by', c.nickname,
             'restriction_id', w.restriction_id, 'notice_read_at', w.notice_read_at, 'acked_at', w.acked_at,
             'state', case when w.acked_at is not null then 'acked' when w.notice_read_at is not null then 'read' else 'unread' end)
           order by w.id desc)
      from public.user_warnings w
      left join public.profiles c on c.id = w.created_by
     where w.user_id = p_user), '[]'::jsonb);
end;
$$;

alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action in (
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report',
  'dismiss_report', 'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
  'remove_link', 'add_link_domain', 'remove_link_domain', 'grant_influencer', 'grant_title', 'revoke_title',
  'remove_profile_photo',
  'restrict_user', 'lift_restriction',
  'warn_user'));  -- 069

-- ---------------------------------------------------------------------
-- 4. 068 빠뜨림 방지 허용 목록: 새 쓰기 함수 2개는 제한 검사를 하지 않는 이유와 함께
-- ---------------------------------------------------------------------
insert into public.restriction_exemptions (kind, name, reason) values
  ('function', 'warn_user(uuid, text)', '069 운영자 전용 (require_operator)'),
  ('function', 'ack_warning(bigint)', '069 받은 경고 확인 - 활동 제한 중에도 할 수 있어야 함');

-- ---------------------------------------------------------------------
-- 5. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.warning_notice_read() from public, anon, authenticated;
revoke execute on function public.warning_notice_message() from public, anon, authenticated;
revoke execute on function public.warn_user(uuid, text) from public, anon;
grant execute on function public.warn_user(uuid, text) to authenticated;                    -- 안에서 운영자 확인
revoke execute on function public.ack_warning(bigint) from public, anon;
grant execute on function public.ack_warning(bigint) to authenticated;
revoke execute on function public.my_warnings() from public, anon;
grant execute on function public.my_warnings() to authenticated;
revoke execute on function public.admin_member_warnings(uuid) from public, anon;
grant execute on function public.admin_member_warnings(uuid) to authenticated;

commit;
