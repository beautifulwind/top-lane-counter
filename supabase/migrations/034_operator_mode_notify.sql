-- =====================================================================
-- 034: 제안자 알림 보강 + 운영자 모드 켜기/끄기 (2026-11-08, SPEC 6-21)
--
-- 1. 제안자 알림 보강 (기존 notifications·notify 도우미 재사용, 있던 알림은 그대로)
--    조사 결과 (033까지):
--    - 승인(approve_proposal_unchecked)·반려(reject_proposal_unchecked)·대기 중 제안 재검토 요청
--      (request_proposal_revision_unchecked)·재검토 요청 취소, 빌드 승인·거절·재검토 요청: 모두 notify()로 보낸다.
--      notify()는 받는 사람이 처리한 본인이면 보내지 않는다 → 그대로 둔다.
--    - 빠진 곳 1: 숨긴 카운터 재검토 요청(request_revision)은 notify()를 거치지 않고 알림을 직접 넣어서
--      운영자가 자기 제안에 재검토를 요청하면 본인에게 알림이 갔다 → notify()로 바꾼다 (문장·종류는 같음).
--    - 빠진 곳 2: 숨긴 카운터 [다시 공개](restore_counter)는 그 카운터를 만든 제안을 다시 "승인됨"으로 바꾸고
--      진행 중이던 재검토 요청을 끝내는데, 제안자에게 아무 알림이 없었다
--      → 새 종류 counter_restored "숨겨졌던 내 카운터가 다시 공개됐습니다" (메모 함께, 누르면 내 제안 화면).
--
-- 2. 운영자 모드 (profiles.operator_mode, 기본 켜짐)
--    - 운영자(role = 'admin') 본인만 set_operator_mode(켜기/끄기)로 바꾼다. 다른 사람은 오류
--      (profiles는 nickname·main_title만 직접 고칠 수 있어서 이 칸은 함수로만 바뀐다).
--    - 끄면 is_admin()·is_staff()가 false → RLS·require_operator·require_staff·운영자 전용 함수가 모두
--      일반 회원과 같은 길로 동작한다 (관리 화면·숨긴 것 읽기·승인 등 불가, 내 제안·문의만 보임).
--    - 끄고 있는 동안 운영진 알림(새 제안·새 빌드·새 문의)은 알림 목록·안 읽은 개수에서 빠지고 읽음 처리도 안 된다.
--      알림 자체는 계속 쌓이므로 다시 켜면 그대로 보인다.
--    - 운영자가 아닌 사람은 이 칸이 켜져 있어도 아무 권한이 없다 (is_admin은 role과 모드를 함께 본다).
--    - 그대로인 것: 닉네임 (운) 표시, Lv.0·경험치 없음, 탈퇴 불가, 감독관이 운영자 글을 처리할 수 없음.
--
-- 하위 호환: 있던 표·함수의 모양(인자·반환)은 바꾸지 않는다. 새 칸은 기본값이 "켜짐"이라 실행 직후 동작이 같다.
-- 지금 배포된 화면과 그대로 동작한다. 순서: 이 파일 실행 → supabase/scripts/check_operator_mode.sql로 확인 → 새 코드 push.
-- 033까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 알림 종류: counter_restored 추가
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in ('revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected', 'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked', 'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked', 'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored'));

-- ---------------------------------------------------------------------
-- 2. 숨긴 카운터 재검토 요청: 알림을 notify()로 (처리한 본인에게는 안 감)
--    (긴 함수를 통째로 다시 쓰지 않고, 지금 DB에 있는 정의에서 그 부분만 바꾼다 — 031·033과 같은 방식)
-- ---------------------------------------------------------------------
do $$
declare
  f oid;
  old_def text;
  new_def text;
begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'request_revision';
  old_def := pg_get_functiondef(f);
  new_def := replace(old_def,
$s$  insert into public.notifications (user_id, kind, proposal_id, message)
  values (who, 'revision_request', pid, note);
$s$,
$s$  perform public.notify(who, 'revision_request', note, pid, null);  -- 처리한 본인에게는 안 감 (034)
$s$);
  if new_def = old_def then
    raise exception 'request_revision에서 바꿀 부분을 찾지 못했습니다. (이미 034를 실행했거나, 009 이후 정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 숨긴 카운터 [다시 공개]: 그 카운터를 만든 제안이 다시 "승인됨"이 되면 제안자에게 알림
-- ---------------------------------------------------------------------
do $$
declare
  f oid;
  old_def text;
  new_def text;
begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'restore_counter';
  old_def := pg_get_functiondef(f);
  new_def := replace(old_def,
$s$  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'restore', note, pid, (select auth.uid()));
$s$,
$s$  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'restore', note, pid, (select auth.uid()));
  -- 제안자에게 알림 (처리한 본인에게는 안 감) (034)
  if pid is not null then
    perform public.notify((select proposer_id from public.edit_proposals where id = pid), 'counter_restored', note, pid, null);
  end if;
$s$);
  if new_def = old_def then
    raise exception 'restore_counter에서 바꿀 부분을 찾지 못했습니다. (이미 034를 실행했거나, 009 이후 정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 운영자 모드 칸 (기본 켜짐). 직접 고치기 권한(grant update)은 주지 않는다 → set_operator_mode로만
-- ---------------------------------------------------------------------
alter table public.profiles add column operator_mode boolean not null default true;
comment on column public.profiles.operator_mode is
  '운영자 모드 (034). 운영자(role = admin)가 끄면 is_admin()·is_staff()가 false — 일반 회원과 같은 길로 동작. 운영자가 아니면 의미 없음';

-- ---------------------------------------------------------------------
-- 5. 권한 판정: role과 모드를 함께 본다 (RLS·require_operator·require_staff가 모두 이 두 함수를 쓴다)
--    모양(인자·반환·security definer)은 그대로라 기존 권한·정책은 손대지 않는다
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles where id = (select auth.uid()) and role = 'admin' and operator_mode
  );
$$;
comment on function public.is_admin() is '지금 로그인한 사람이 운영자(role = admin, 1명)이고 운영자 모드가 켜져 있는가 (034)';

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
     where id = (select auth.uid()) and (role = 'moderator' or (role = 'admin' and operator_mode))
  );
$$;
comment on function public.is_staff() is '지금 로그인한 사람이 감독관이거나, 운영자 모드가 켜진 운영자인가 (034)';

-- 운영자인데 운영자 모드를 끈 상태인가 (알림 숨김용)
create function public.operator_mode_off()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles where id = (select auth.uid()) and role = 'admin' and not operator_mode
  );
$$;

-- ---------------------------------------------------------------------
-- 6. 켜기/끄기: 본인 계정만, 운영자만 (모드를 꺼도 role은 그대로라 같은 자리에서 다시 켤 수 있다)
-- ---------------------------------------------------------------------
create function public.set_operator_mode(p_on boolean)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  r text;
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  if p_on is null then
    raise exception '켜기/끄기를 골라 주세요.' using errcode = '22023';
  end if;
  select role into r from public.profiles where id = me for update;
  if r is distinct from 'admin' then
    raise exception '운영자 계정만 운영자 모드를 바꿀 수 있습니다.' using errcode = '42501';
  end if;
  update public.profiles set operator_mode = p_on where id = me;
  return p_on;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 모드를 끈 동안: 운영진 알림은 목록·개수에서 빠지고, [모두 읽음]도 건드리지 않는다
-- ---------------------------------------------------------------------
drop policy "notifications: 본인 읽기" on public.notifications;
create policy "notifications: 본인 읽기" on public.notifications
  for select to authenticated using (
    user_id = (select auth.uid())
    and not (kind in ('proposal_submitted', 'build_submitted', 'inquiry_received') and public.operator_mode_off())
  );

create or replace function public.mark_all_notifications_read(p_upto bigint)
returns timestamptz language plpgsql security definer set search_path = ''
as $$
declare
  t timestamptz := now();
  hide_staff boolean := public.operator_mode_off();
begin
  if (select auth.uid()) is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  update public.notifications
     set read_at = t
   where user_id = (select auth.uid()) and read_at is null and id <= p_upto
     and not (hide_staff and kind in ('proposal_submitted', 'build_submitted', 'inquiry_received'));
  return t;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.operator_mode_off() from public, anon;
grant execute on function public.operator_mode_off() to authenticated;  -- RLS 정책 안에서 쓴다 (내 상태만 알려 줌)
revoke execute on function public.set_operator_mode(boolean) from public, anon;
grant execute on function public.set_operator_mode(boolean) to authenticated;  -- 운영자인지는 함수 안에서 검사

commit;

-- 확인 (실행 뒤): supabase/scripts/check_operator_mode.sql
