-- =====================================================================
-- 045: 게시판 신고(글·댓글·문서 댓글) → 운영진 알림 (2026-11-11, SPEC 6-31)
-- (044는 탈퇴 처리용으로 비워 둔다. 이 파일은 043까지 실행한 DB에서 044 없이 실행해도 된다.)
--
-- 1. 새 알림 종류 report_received: reports 표에 신고 줄이 생기면(트리거 — report_post·report_comment·report_doc_comment 어느 길이든 빠지지 않음)
--    운영진에게 한 줄. 문장 「새 신고가 들어왔습니다. (글)」·「(댓글)」·「(문서 댓글)」 — 이유는 문장에 넣지 않는다(처음 신고의 이유만 보여 주면 오해하므로 신고 화면에서 본다).
--    - 받는 사람: 운영자 + 감독관, 신고자 본인 제외. 오류 신고 error_reported(043)와 같은 규칙.
--      단 감독관에게는 감독관이 처리할 수 있는 대상(글·댓글 작성자가 일반 회원이거나 탈퇴한 사람)일 때만 보낸다
--      (운영진이 쓴 글의 신고는 감독관이 처리할 수 없고 신고 목록에도 안 나온다 — 030 moderatable_author와 같은 기준).
--    - "같은 대상에 처리 전 신고가 처음 생길 때만": 그 글·댓글·문서 댓글에 처리 전(open) 신고가 이미 있으면 보내지 않는다.
--      숨김·삭제·기각으로 신고가 모두 처리된 뒤 새 신고가 생기면 다시 보낸다. 같은 대상 동시 신고는 대상별 잠금으로 한 번만.
--    - 알림에는 글·댓글이면 post_id, 문서 댓글이면 counter_id (둘째 줄 매치업 표시용). 누르면 /admin/reports ("글·댓글 신고" 탭, 기본 탭).
-- 2. 운영자 모드를 끄면 목록·빨간 점·[모두 읽음]에서 빠지고 푸시도 안 간다 (읽기 정책·mark_all_notifications_read에 새 종류를 더함 — 034·038·042·043과 같은 규칙).
-- 3. 푸시 묶음 staff_new (push_group). 푸시 설정 화면의 "운영진 알림" 하나로 함께 켜고 끈다. 보낼 대상·기기는 있던 notify 트리거·push_on_notification·push_targets 그대로
--    (push_targets는 post_id를 이미 돌려줌 — 042).
--
-- 예외 처리(조사 결과):
--  - 신고자가 자기 글·댓글을 신고: report_*가 이미 거부한다(23514). 신고 줄이 안 생기므로 알림도 없다. 바꾸지 않음.
--  - 같은 사람이 같은 대상을 다시 신고: reports의 unique 인덱스가 거부(처리 뒤에도 — 이미 있는 동작). 알림 없음. 바꾸지 않음.
--  - 이미 처리된(숨김·기각·삭제) 대상에 새 신고: 숨기거나 지운 글·댓글은 report_*가 거부(P0002). 기각된 글이나 숨겼다가 다시 공개한 글에
--    "다른 사람"이 새로 신고하면 처리 전 신고가 0건이므로 새 "처음 신고"로 보고 알림을 보낸다.
--  - 운영진이 신고자: 알림은 신고자 본인만 빼고 나머지 운영진에게 간다(운영자가 신고하면 감독관에게, 감독관이 신고하면 운영자에게).
--  - 운영자가 쓴 글을 신고: 운영자에게는 간다(운영자는 자기 글 신고도 처리할 수 있어 막지 않음), 감독관에게는 안 간다.
--  - 신고자가 탈퇴: reports.reporter_id가 on delete cascade라 신고 줄이 사라진다. 이미 보낸 알림은 남고(90일 뒤 정리), 누르면 신고 목록으로 갈 뿐이다.
--  - 글쓴이가 신고된 글을 스스로 지움: 처리 전 신고가 기각 처리되고(015) 알림은 읽지 않은 채 남는다. 신고 목록에 없을 뿐 해롭지 않다.
--  - 비회원(손님): reports_no_guest 트리거가 이미 막는다. 알림 없음.
--  pg_cron은 필요 없다: 새 표·오래된 기록 정리가 없고, 알림 정리(90일)는 종류와 상관없이 있던 일정이 한다.
--
-- 하위 호환: 있던 표·함수의 이름·인자·반환은 그대로 (알림 종류 제약·읽기 정책·mark_all_notifications_read·push_group을 같은 모양으로 다시 만듦).
--   새 알림 종류·새 트리거 함수만 더한다. 지금 배포된 화면과 그대로 동작한다
--   (옛 화면은 모르는 알림 종류를 종 모양 + 문장으로 보여 주고 누르면 아무 데도 안 간다).
-- 순서: 이 파일 실행 → supabase/scripts/check_report_received.sql로 확인 → web-push Edge Function 재배포 → 새 화면 push.
--   Edge Function은 045 전·후 어느 쪽이든 안전하다 (모르는 종류는 알림 목록으로 간다).
-- 043까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.wiki_reports') is null then
    raise exception '043이 아직 실행되지 않았습니다. 043_wiki_reports_revert.sql을 먼저 실행해 주세요.';
  end if;
  if exists (select 1 from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
                and pg_get_constraintdef(oid) like '%report_received%') then
    raise exception '045를 이미 실행했습니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 알림 종류 · 운영자 모드 읽기 규칙 · 푸시 묶음
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
  'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
  'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
  'matchup_created', 'build_created',
  'post_deleted', 'comment_deleted', 'doc_comment_deleted',
  'post_created',
  'error_reported', 'error_report_handled',
  'report_received'  -- 045: 새 게시판 신고 (운영진)
]));

drop policy "notifications: 본인 읽기" on public.notifications;
create policy "notifications: 본인 읽기" on public.notifications
  for select using (
    user_id = (select auth.uid())
    and not (kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                      'error_reported', 'report_received')
             and public.operator_mode_off())
  );

do $$
declare
  f oid := 'public.mark_all_notifications_read'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
    $s$kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created', 'error_reported')$s$,
    $s$kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created', 'error_reported', 'report_received')$s$);
  if new_def = old_def then
    raise exception 'mark_all_notifications_read에서 바꿀 부분을 찾지 못했습니다. (이미 045를 실행했거나 정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored') then 'my_results'
  end;
$$;

-- ---------------------------------------------------------------------
-- 2. 새 신고 → 운영진 알림 (처음 생긴 처리 전 신고만, 신고자 본인 제외)
-- ---------------------------------------------------------------------
create function public.notify_staff_new_report()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  target_key text := case when new.post_id is not null then 'post:' || new.post_id
                          when new.comment_id is not null then 'comment:' || new.comment_id
                          else 'doc_comment:' || new.doc_comment_id end;
  kind_label text := case when new.post_id is not null then '글'
                          when new.comment_id is not null then '댓글'
                          else '문서 댓글' end;
  n_post bigint;
  n_counter bigint;
  author uuid;
begin
  if new.status <> 'open' then
    return null;
  end if;
  -- 같은 대상 동시 신고가 서로의 처리 전 신고를 못 봐서 둘 다 "처음"이 되지 않게 (잠금이 풀린 뒤 다음 조회가 새 줄을 본다)
  perform pg_advisory_xact_lock(hashtext('report_received:' || target_key));
  if exists (
    select 1 from public.reports r
     where r.status = 'open' and r.id <> new.id
       and r.post_id is not distinct from new.post_id
       and r.comment_id is not distinct from new.comment_id
       and r.doc_comment_id is not distinct from new.doc_comment_id) then
    return null;
  end if;

  if new.post_id is not null then
    n_post := new.post_id;
    select p.author_id into author from public.posts p where p.id = new.post_id;
  elsif new.comment_id is not null then
    select c.post_id, c.author_id into n_post, author from public.post_comments c where c.id = new.comment_id;
  else
    select d.counter_id, d.author_id into n_counter, author from public.doc_comments d where d.id = new.doc_comment_id;
  end if;

  insert into public.notifications (user_id, kind, message, post_id, counter_id)
  select u.id, 'report_received', format('새 신고가 들어왔습니다. (%s)', kind_label), n_post, n_counter
    from public.profiles u
   where u.id is distinct from new.reporter_id
     and (u.role = 'admin'
          or (u.role = 'moderator'
              -- 감독관이 처리할 수 있는 대상만 (030 moderatable_author: 작성자가 일반 회원이거나 탈퇴)
              and (author is null or exists (select 1 from public.profiles a where a.id = author and a.role = 'user'))
              and u.id is distinct from author));
  return null;
end;
$$;
create trigger reports_notify_staff
  after insert on public.reports
  for each row execute function public.notify_staff_new_report();

revoke execute on function public.notify_staff_new_report() from public, anon, authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_report_received.sql
