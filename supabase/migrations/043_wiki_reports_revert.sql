-- =====================================================================
-- 043: 오류 신고 · 빌드 되돌리기 · 운영자 빌드 수정 기록 · 감독관 빌드 숨기기 — 1단계 DB (2026-11-11, SPEC 6-30)
--
-- 1. 오류 신고 (새 표 wiki_reports — 게시판 신고 reports와 따로: 대상·이유·처리 방식이 다르고 옛 신고 화면이 깨지지 않게)
--    - report_wiki(상대법, 빌드, 이유, 메모): 구글·카카오로 로그인한 정식 회원만 (비회원·비로그인 불가).
--      빌드를 비우면 상대법 전체에 대한 신고. 이유 wrong(내용이 틀림)·outdated(패치가 지남)·vandal(장난·훼손)·
--      duplicate(같은 빌드가 또 있음)·other(기타, 메모 필수). 상대법 전체 신고는 wrong·vandal·other만. 메모 200자.
--    - 남발 막기: 같은 사람이 같은 대상에 낸 "처리 전" 신고는 1건, 하루(한국 시간) error_report_daily_cap(10)건.
--    - 새 알림 error_reported: 운영자 + 감독관 (신고자 본인 제외). 그 대상에 처리 전 신고가 처음 생길 때만.
--      운영자 모드를 끄면 목록·빨간 점·[모두 읽음]에서 빠지고 푸시도 안 감. 푸시 묶음 staff_new.
--    - staff_wiki_reports(상태, 쪽, 쪽 크기): 운영진(운영자·감독관) 목록. 신고자는 운영자에게만 보인다.
--    - handle_wiki_report(신고, resolved/dismissed, 메모, 같은 대상 함께): 운영진, 메모 필수, 처리 기록(resolve_report·dismiss_report).
--      감독관은 자기가 낸 신고를 처리할 수 없다. 신고자에게 error_report_handled 알림 (메모 없이, 푸시 없음).
--    - 1년 정리: purge_wiki_reports() — 처리한 날부터 error_report_keep_days(365)일 (처리 전 신고는 남김, pg_cron)
--    - 처리 대기 건수 admin_pending_counts()에 wiki_reports를 더한다 (있던 키는 그대로).
-- 2. 운영자 빌드 수정 기록: admin_build_revisions(빌드, 이 번호보다 앞, 개수) — 수정자·시각·전후 내용 (운영자만, _unchecked + require_operator)
-- 3. 되돌리기: revert_build(빌드, 수정 기록, 본 버전, 메모) — 운영자만. 그 기록의 "후" 내용으로 되돌리고 version +1
--    (편집 중이던 사람은 저장할 때 TL412). build_revisions에 kind='revert'·revert_of, 처리 기록 revert(메모 필수).
--    시초·경험치는 그대로. 되돌린 범위의 수정만 한 사람은 기여자에서 빠지고, 그 전에도 고친 사람은 횟수만 준다.
--    되돌린 운영자는 기여자에 넣지 않는다. 알림 없음.
-- 4. 감독관의 빌드 숨기기·다시 공개: hide_build·restore_build를 require_operator → require_staff로.
--    감독관은 시초가 일반 회원(또는 탈퇴)이고 본인이 아닌, 공개 중인 상대법의 빌드만. 다시 공개는 감독관이 숨긴 것만.
--    운영자·감독관 모두 처리 기록(hide·restore, 대상 build)을 남긴다. 감독관은 처리할 수 있는 숨긴 빌드를 읽을 수 있다(RLS 추가).
--    상대법 숨기기·다시 공개·완전 삭제는 운영자만 그대로.
-- 5. build_edit_check(빌드, 사람): 빌드 수정 권한을 한 곳에서 판단 (edit_build가 부름, 동작은 그대로).
--    나중에 "작성자와 운영진만 수정" 잠금(builds.edit_lock)을 넣을 자리.
--
-- 하위 호환: 있던 표·함수의 이름·인자·반환은 그대로 (hide_build·restore_build·edit_build·admin_pending_counts는 같은 모양으로 다시 만듦).
--   새 표·칸·함수·알림 종류만 더한다. 지금 배포된 화면과 그대로 동작한다
--   (옛 화면은 모르는 알림 종류를 종 모양 + 문장으로 보여 주고, 처리 대기 건수의 새 키는 무시한다).
-- 순서: 이 파일 실행 → supabase/scripts/check_wiki_reports_revert.sql로 확인 → pg_cron 일정 등록 → (2단계) 새 화면 push.
-- 042까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.admin_member_detail(uuid, integer)') is null then
    raise exception '042가 아직 실행되지 않았습니다. 042_member_admin_new_post_notify.sql을 먼저 실행해 주세요.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 0. 설정값
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('error_report_daily_cap', 10, '오류 신고 하루(한국 시간) 상한 — 한 사람 기준 (043)'),
  ('error_report_keep_days', 365, '처리한 오류 신고 보관 기간(일) — 지나면 매일 지움 (purge_wiki_reports, pg_cron, 043)')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 1. 표 · 칸
-- ---------------------------------------------------------------------
create table public.wiki_reports (
  id           bigint generated always as identity primary key,
  counter_id   bigint not null references public.counters (id) on delete cascade,
  build_id     bigint references public.builds (id) on delete cascade,      -- null = 상대법 전체
  reporter_id  uuid references public.profiles (id) on delete set null,     -- 탈퇴하면 비움 (신고 내용은 처리될 때까지 남김)
  reason       text not null check (reason in ('wrong', 'outdated', 'vandal', 'duplicate', 'other')),
  memo         text check (memo is null or (memo = btrim(memo) and char_length(memo) between 1 and 200)),
  status       text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  handled_by   uuid references public.profiles (id) on delete set null,
  handled_at   timestamptz,
  handled_note text check (handled_note is null or char_length(handled_note) <= 500),
  created_at   timestamptz not null default now(),
  constraint wiki_reports_other_memo check (reason <> 'other' or memo is not null),
  constraint wiki_reports_matchup_reason check (build_id is not null or reason in ('wrong', 'vandal', 'other')),
  constraint wiki_reports_handled check ((status = 'open') = (handled_at is null))
);
-- 같은 사람이 같은 대상(상대법 전체 / 빌드)에 낸 처리 전 신고는 1건
create unique index wiki_reports_open_once on public.wiki_reports (reporter_id, counter_id, coalesce(build_id, 0)) where status = 'open';
create index wiki_reports_open on public.wiki_reports (created_at, id) where status = 'open';
create index wiki_reports_target on public.wiki_reports (counter_id, build_id);
create index wiki_reports_reporter on public.wiki_reports (reporter_id, created_at);
create index wiki_reports_handled on public.wiki_reports (handled_at) where handled_at is not null;
alter table public.wiki_reports enable row level security;  -- 정책 없음: 함수로만 읽고 쓴다
revoke all on public.wiki_reports from anon, authenticated;
comment on table public.wiki_reports is
  '상대법·빌드 오류 신고 (043). 정식 회원만 report_wiki로 내고, 운영진이 staff_wiki_reports로 읽고 handle_wiki_report로 처리. 처리 뒤 1년 보관';

alter table public.build_revisions add column revert_of bigint;  -- 수정 기록은 1년 뒤 지워지므로 외래 키로 묶지 않는다
comment on column public.build_revisions.revert_of is '되돌리기(kind = revert)의 기준 수정 기록 번호 (043)';

-- ---------------------------------------------------------------------
-- 2. 처리 기록 종류
-- ---------------------------------------------------------------------
alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action in (
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete',
  'revert', 'resolve_report', 'dismiss_report'  -- 043: 빌드 되돌리기, 오류 신고 처리됨·기각
));
alter table public.moderation_log drop constraint moderation_log_target_kind_check;
alter table public.moderation_log add constraint moderation_log_target_kind_check check (target_kind in (
  'post', 'comment', 'doc_comment', 'proposal', 'user', 'inquiry',
  'build', 'wiki_report'  -- 043
));

-- ---------------------------------------------------------------------
-- 3. 알림 종류 · 운영자 모드 · 푸시
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
  'error_reported', 'error_report_handled'  -- 043: 새 오류 신고(운영진), 오류 신고 처리 결과(신고자, 푸시 없음)
]));

drop policy "notifications: 본인 읽기" on public.notifications;
create policy "notifications: 본인 읽기" on public.notifications
  for select using (
    user_id = (select auth.uid())
    and not (kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                      'error_reported')
             and public.operator_mode_off())
  );

do $$
declare
  f oid := 'public.mark_all_notifications_read'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
    $s$kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created')$s$,
    $s$kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created', 'error_reported')$s$);
  if new_def = old_def then
    raise exception 'mark_all_notifications_read에서 바꿀 부분을 찾지 못했습니다. (이미 043을 실행했거나 정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored') then 'my_results'
  end;
$$;

-- ---------------------------------------------------------------------
-- 4. 빌드 수정 권한 (한 곳에서 판단)
--    나중에 "작성자와 운영진만 수정" 잠금을 넣을 때: builds에 edit_lock 칸을 더하고 여기에 분기 하나만 더한다.
--      if b.edit_lock = 'author_staff' and b.author_id is distinct from me and not public.is_staff() then
--        raise exception '이 빌드는 작성자와 운영진만 수정할 수 있습니다.' using errcode = '42501';
--      end if;
--    잠금 칸은 wiki_snapshot(수정 기록 내용)에 넣지 않는다 → 되돌리기가 잠금을 바꾸지 않는다.
--    되돌리기(revert_build)는 운영자 전용이라 이 검사를 거치지 않는다.
-- ---------------------------------------------------------------------
create function public.build_edit_check(b public.builds, me uuid)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if b.status <> 'approved' or not exists (select 1 from public.counters where id = b.counter_id and status = 'approved') then
    raise exception '공개된 빌드만 수정할 수 있습니다.' using errcode = '23514';
  end if;
  if b.author_id is distinct from me and public.is_guest(me) then
    raise exception '다른 분의 빌드는 구글·카카오로 로그인한 회원만 수정할 수 있습니다. 비회원은 새 빌드를 등록하거나 내 빌드를 수정할 수 있습니다.'
      using errcode = '42501';
  end if;
end;
$$;
comment on function public.build_edit_check(public.builds, uuid) is
  '빌드를 이 사람이 고칠 수 있나 (043). 안 되면 오류. edit_build가 부르고, 잠금 기능이 들어오면 여기에 더한다';

create or replace function public.edit_build(p_id bigint, p_version integer, p_build jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b public.builds;
  nb public.builds;
  c jsonb;
  before jsonb;
  same_build boolean;
begin
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.build_edit_check(b, me);  -- 043: 공개 여부·비회원 규칙 (잠금이 들어올 자리)
  if p_version is distinct from b.version then
    raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
  end if;
  c := public.clean_wiki_build(p_build);
  before := public.wiki_snapshot(b);
  if c - 'patch' = before - 'patch' then
    raise exception '바뀐 내용이 없습니다.' using errcode = '23514';
  end if;
  same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' = public.build_signature(b);
  if not same_build and exists (
    select 1 from public.builds x
     where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
       and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions'
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있습니다. 그 빌드를 추천해 주세요.' using errcode = '23514';
  end if;
  perform public.wiki_throttle('edit');

  update public.builds
     set runes = c -> 'runes',
         summoner_spells = array(select jsonb_array_elements_text(c -> 'summoner_spells')),
         starting_items = array(select jsonb_array_elements_text(c -> 'starting_items')),
         core_items = array(select jsonb_array_elements_text(c -> 'core_items')),
         max_skill = c ->> 'max_skill',
         patch = case when same_build then b.patch else c ->> 'patch' end,  -- 글만 고치면 패치 그대로
         name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
         version = b.version + 1, updated_at = now(), updated_by = me
   where id = b.id
   returning * into nb;  -- 핵심 템트리·강타·시작 골드는 바뀐 칸만 트리거가 검사
  insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
  values (b.id, b.counter_id, me, 'edit', before, public.wiki_snapshot(nb), nb.version);
  if me is distinct from b.author_id then
    insert into public.build_editors (build_id, user_id) values (b.id, me)
    on conflict (build_id, user_id) do update set last_at = now(), edits = public.build_editors.edits + 1;
  end if;
  return nb.version;  -- 수정마다 알림은 보내지 않는다. 경험치도 없다
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 오류 신고
-- ---------------------------------------------------------------------
create function public.wiki_report_reason_label(p_reason text)
returns text language sql immutable set search_path = ''
as $$
  select case p_reason
    when 'wrong' then '내용이 틀림'
    when 'outdated' then '패치가 지남'
    when 'vandal' then '장난·훼손'
    when 'duplicate' then '같은 빌드가 또 있음'
    when 'other' then '기타'
  end;
$$;

-- 돌려주는 값: 신고 번호
create function public.report_wiki(p_counter bigint, p_build bigint, p_reason text, p_memo text default null)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();  -- 로그인 + 닉네임
  m text := nullif(btrim(coalesce(p_memo, '')), '');
  cid bigint := p_counter;
  b public.builds;
  cap integer := coalesce(public.xp_rule('error_report_daily_cap'), 10);
  today integer;
  first_open boolean;
  rid bigint;
begin
  if public.is_guest(me) then
    raise exception '오류 신고는 구글·카카오로 로그인한 회원만 할 수 있습니다.' using errcode = '42501';
  end if;
  if p_build is not null then
    select * into b from public.builds where id = p_build;
    if not found or b.status <> 'approved' or (cid is not null and b.counter_id <> cid) then
      raise exception '신고할 빌드를 찾지 못했습니다.' using errcode = 'P0002';
    end if;
    cid := b.counter_id;
  end if;
  if cid is null or not exists (select 1 from public.counters where id = cid and status = 'approved') then
    raise exception '신고할 상대법을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if p_reason is null or p_reason not in ('wrong', 'outdated', 'vandal', 'duplicate', 'other')
     or (p_build is null and p_reason not in ('wrong', 'vandal', 'other')) then
    raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
  end if;
  if p_reason = 'other' and m is null then
    raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(m) > 200 then
    raise exception '메모는 200자 이하로 적어 주세요.' using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(hashtext('wiki_report:' || me::text));  -- 같은 사람이 동시에 여러 번 눌러도 상한을 넘지 않게
  select count(*) into today from public.wiki_reports
   where reporter_id = me
     and created_at >= ((now() at time zone 'Asia/Seoul')::date::timestamp at time zone 'Asia/Seoul');
  if today >= cap then
    raise exception '오류 신고는 하루에 %건까지 할 수 있습니다. 내일 다시 해 주세요.', cap using errcode = '23514';
  end if;

  perform 1 from public.counters where id = cid for update;  -- 같은 대상의 "첫 신고" 판단이 겹치지 않게
  first_open := not exists (
    select 1 from public.wiki_reports
     where counter_id = cid and build_id is not distinct from p_build and status = 'open');
  begin
    insert into public.wiki_reports (counter_id, build_id, reporter_id, reason, memo)
    values (cid, p_build, me, p_reason, m)
    returning id into rid;
  exception when unique_violation then
    raise exception '이미 신고한 내용이 처리를 기다리고 있습니다.' using errcode = '23505';
  end;

  -- 운영진 알림: 그 대상에 처리 전 신고가 처음 생길 때만 (운영자 + 감독관, 신고자 본인 제외)
  if first_open then
    insert into public.notifications (user_id, kind, message, counter_id, build_id)
    select u.id, 'error_reported',
           format('새 오류 신고가 들어왔습니다. (%s)', public.wiki_report_reason_label(p_reason)), cid, p_build
      from public.profiles u
     where u.role in ('admin', 'moderator') and u.id <> me;
  end if;
  return rid;
end;
$$;

-- 운영진 목록. p_status: open(처리 전, 오래된 순) / handled(처리됨·기각, 최근 처리 순)
create function public.staff_wiki_reports(p_status text default 'open', p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  op boolean;
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  st text := coalesce(p_status, 'open');
begin
  perform public.require_staff();
  op := public.is_admin();
  if st not in ('open', 'handled') then
    raise exception '목록 종류를 다시 골라 주세요.' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'total', (select count(*) from public.wiki_reports r where (st = 'open') = (r.status = 'open')),
    'page', pg, 'size', sz,
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'counter_id', x.counter_id, 'target_champion', x.target_champion, 'counter_champion', x.counter_champion,
               'counter_status', x.counter_status, 'build_id', x.build_id, 'build_seq', x.build_seq, 'build_name', x.build_name,
               'build_status', x.build_status, 'reason', x.reason, 'memo', x.memo, 'status', x.status, 'created_at', x.created_at,
               'handled_at', x.handled_at, 'handled_note', x.handled_note,
               'handler', case when x.status = 'open' then null
                               when x.h_id is null then jsonb_build_object('withdrawn', true)
                               else jsonb_build_object('id', x.h_id, 'nickname', x.h_nickname, 'role', x.h_role, 'withdrawn', false) end,
               'reporter', case when not op then null
                                when x.r_id is null then jsonb_build_object('withdrawn', true)
                                else jsonb_build_object('id', x.r_id, 'nickname', x.r_nickname, 'role', x.r_role,
                                                        'is_guest', x.r_guest, 'withdrawn', false) end,
               'mine', x.mine,
               'same_open', x.same_open)
             order by x.ord)
      from (
        select r.*, k.target_champion, k.counter_champion, k.status as counter_status,
               b.seq as build_seq, b.name as build_name, b.status as build_status,
               h.id as h_id, h.nickname as h_nickname, h.role as h_role,
               rp.id as r_id, rp.nickname as r_nickname, rp.role as r_role, coalesce(rp.is_guest, false) as r_guest,
               r.reporter_id is not distinct from me and me is not null as mine,
               (select count(*) from public.wiki_reports o
                 where o.status = 'open' and o.counter_id = r.counter_id and o.build_id is not distinct from r.build_id) as same_open,
               row_number() over (order by
                 case when st = 'open' then r.created_at end asc,
                 case when st = 'handled' then r.handled_at end desc,
                 case when st = 'open' then r.id end asc,
                 case when st = 'handled' then r.id end desc) as ord
          from public.wiki_reports r
          join public.counters k on k.id = r.counter_id
          left join public.builds b on b.id = r.build_id
          left join public.profiles h on h.id = r.handled_by
          left join public.profiles rp on rp.id = r.reporter_id
         where (st = 'open') = (r.status = 'open')
         order by ord
         limit sz offset (pg - 1) * sz
      ) x
    ), '[]'::jsonb));
end;
$$;

-- 돌려주는 값: 처리한 신고 수 (p_same_target = true면 같은 대상의 처리 전 신고를 함께 처리)
create function public.handle_wiki_report(p_id bigint, p_status text, p_note text, p_same_target boolean default false)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  note text;
  r public.wiki_reports;
  x public.wiki_reports;
  n integer := 0;
begin
  perform public.require_staff();
  if p_status is null or p_status not in ('resolved', 'dismissed') then
    raise exception '처리 결과(처리됨·기각)를 골라 주세요.' using errcode = '23514';
  end if;
  note := public.require_note(p_note, '처리 메모');
  select * into r from public.wiki_reports where id = p_id for update;
  if not found then
    raise exception '신고를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if r.status <> 'open' then
    raise exception '이미 처리된 신고입니다.' using errcode = '23514';
  end if;
  if public.is_moderator() and r.reporter_id = me then
    raise exception '내가 낸 신고는 다른 운영진이 처리합니다.' using errcode = '42501';
  end if;

  for x in
    select * from public.wiki_reports w
     where w.status = 'open'
       and (w.id = r.id or (coalesce(p_same_target, false)
                            and w.counter_id = r.counter_id and w.build_id is not distinct from r.build_id
                            and not (public.is_moderator() and w.reporter_id = me)))
     order by w.id
     for update
  loop
    update public.wiki_reports
       set status = p_status, handled_by = me, handled_at = now(), handled_note = note
     where id = x.id;
    perform public.log_moderation(case p_status when 'resolved' then 'resolve_report' else 'dismiss_report' end,
                                  'wiki_report', x.id::text, note);
    if x.reporter_id is not null and x.reporter_id <> me then
      insert into public.notifications (user_id, kind, message, counter_id, build_id)
      values (x.reporter_id, 'error_report_handled',
              case p_status when 'resolved' then '보내 주신 오류 신고를 처리했습니다. 고맙습니다.'
                            else '보내 주신 오류 신고를 검토했지만 고칠 내용이 없어 기각했습니다.' end,
              x.counter_id, x.build_id);
    end if;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- 처리한 지 오래된 오류 신고 지우기 (사람은 못 부르고 pg_cron만). 처리 전 신고는 남긴다
create function public.purge_wiki_reports()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  delete from public.wiki_reports
   where status <> 'open'
     and handled_at < now() - make_interval(days => coalesce(public.xp_rule('error_report_keep_days'), 365));
  get diagnostics n = row_count;
  return n;
end;
$$;

-- 처리 대기 건수: 오류 신고(wiki_reports)를 더한다 (감독관은 자기가 낸 것 제외)
create or replace function public.admin_pending_counts()
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
      'inquiries', (select count(*) from public.inquiries where answer is null and user_id <> me),
      'wiki_reports', (select count(*) from public.wiki_reports where status = 'open'));
  end if;
  return jsonb_build_object(
    'proposals', (select count(*) from public.edit_proposals
                   where status = 'pending' and type = 'new_counter' and counter_id is null
                     and proposer_id <> me and public.moderatable_author(proposer_id)),
    'builds', 0,
    'inquiries', (select count(*) from public.inquiries where answer is null and user_id <> me and category <> 'account'),
    'wiki_reports', (select count(*) from public.wiki_reports where status = 'open' and reporter_id is distinct from me));
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 운영자 빌드 수정 기록 (운영자만)
-- ---------------------------------------------------------------------
create function public.admin_build_revisions_unchecked(p_build bigint, p_before bigint, p_limit integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  lim integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  b public.builds;
  k public.counters;
  rows jsonb;
  more boolean;
begin
  select * into b from public.builds where id = p_build;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  select * into k from public.counters where id = b.counter_id;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'kind', x.kind, 'version', x.version, 'created_at', x.created_at, 'revert_of', x.revert_of,
           'editor', case when x.editor_id is null then null
                          else jsonb_build_object('id', p.id, 'nickname', p.nickname, 'role', p.role,
                                                  'is_guest', coalesce(p.is_guest, false), 'level', p.level, 'main_title', p.main_title) end,
           'before', x.before, 'after', x.after) order by x.id desc), '[]'::jsonb)
    into rows
    from (
      select * from public.build_revisions r
       where r.build_id = b.id and (p_before is null or r.id < p_before)
       order by r.id desc limit lim
    ) x
    left join public.profiles p on p.id = x.editor_id;
  select exists (
    select 1 from public.build_revisions r
     where r.build_id = b.id
       and r.id < coalesce((select min((e ->> 'id')::bigint) from jsonb_array_elements(rows) e), p_before, 0)
  ) into more;
  return jsonb_build_object(
    'build', jsonb_build_object(
      'id', b.id, 'counter_id', b.counter_id, 'seq', b.seq, 'name', b.name, 'status', b.status, 'version', b.version,
      'updated_at', b.updated_at, 'created_at', b.created_at, 'is_first', k.first_build_id = b.id,
      'target_champion', k.target_champion, 'counter_champion', k.counter_champion, 'counter_status', k.status,
      'author', (select jsonb_build_object('id', a.id, 'nickname', a.nickname, 'role', a.role, 'is_guest', coalesce(a.is_guest, false),
                                           'level', a.level, 'main_title', a.main_title)
                   from public.profiles a where a.id = b.author_id),
      'current', public.wiki_snapshot(b)),
    'revisions', rows,
    'has_more', more,
    'keep_days', coalesce(public.xp_rule('build_revision_keep_days'), 365));
end;
$$;

create function public.admin_build_revisions(p_build bigint, p_before bigint default null, p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_build_revisions_unchecked(p_build, p_before, p_limit);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 되돌리기 (운영자만)
--    돌려주는 값: {version: 새 버전, removed_contributors: 기여자에서 뺀 사람 수}
-- ---------------------------------------------------------------------
create function public.revert_build_unchecked(p_build bigint, p_revision bigint, p_version integer, p_note text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  note text := public.require_note(p_note, '되돌리는 사유');
  b public.builds;
  nb public.builds;
  rv public.build_revisions;
  c jsonb;
  before jsonb;
  same_build boolean;
  e record;
  ed public.build_editors;
  removed integer := 0;
begin
  select * into b from public.builds where id = p_build for update;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if b.status not in ('approved', 'hidden') then
    raise exception '공개됐거나 숨긴 빌드만 되돌릴 수 있습니다.' using errcode = '23514';
  end if;
  if p_version is distinct from b.version then
    raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
  end if;
  select * into rv from public.build_revisions where id = p_revision and build_id = b.id;
  if not found then
    raise exception '되돌릴 수정 기록을 찾지 못했습니다. (보관 기간이 지나 지워졌을 수 있습니다)' using errcode = 'P0002';
  end if;
  c := public.clean_wiki_build(rv.after);  -- 지금 규칙으로 다시 검사 (없어진 아이템 등은 여기나 트리거에서 오류)
  before := public.wiki_snapshot(b);
  if c = before then
    raise exception '지금 내용과 같습니다.' using errcode = '23514';
  end if;
  same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' = public.build_signature(b);
  if not same_build and exists (
    select 1 from public.builds x
     where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
       and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions'
  ) then
    raise exception '되돌리면 다른 공개 빌드와 똑같아집니다. 둘 중 하나를 숨겨 주세요.' using errcode = '23514';
  end if;

  update public.builds
     set runes = c -> 'runes',
         summoner_spells = array(select jsonb_array_elements_text(c -> 'summoner_spells')),
         starting_items = array(select jsonb_array_elements_text(c -> 'starting_items')),
         core_items = array(select jsonb_array_elements_text(c -> 'core_items')),
         max_skill = c ->> 'max_skill', patch = c ->> 'patch',
         name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
         version = b.version + 1, updated_at = now(), updated_by = me
   where id = b.id
   returning * into nb;  -- 편집 중이던 사람은 저장할 때 버전이 달라 TL412
  insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version, revert_of)
  values (b.id, b.counter_id, me, 'revert', before, public.wiki_snapshot(nb), nb.version, rv.id);

  -- 기여자 정리: 되돌린 범위(기준 기록 뒤)의 수정만 한 사람은 빼고, 그 전에도 고친 사람은 횟수만 줄인다.
  --   "그 전에도 고침" = 기여자 줄의 첫 기여 시각(first_at)이 범위의 첫 수정보다 앞섬.
  --   (예전에 되돌려져 기여자에서 빠졌던 수정은 세지 않는다 — 빠질 때 줄이 지워지고 다음 수정 때 새로 생기므로)
  for e in
    select r.editor_id as uid, count(*)::integer as n, min(r.created_at) as first_in_range
      from public.build_revisions r
     where r.build_id = b.id and r.id > rv.id and r.kind in ('edit', 'migrate')
       and r.editor_id is not null and r.editor_id is distinct from b.author_id
     group by r.editor_id
  loop
    select * into ed from public.build_editors where build_id = b.id and user_id = e.uid for update;
    continue when not found;
    if ed.first_at < e.first_in_range then
      update public.build_editors set edits = greatest(edits - e.n, 1) where build_id = b.id and user_id = e.uid;
    else
      delete from public.build_editors where build_id = b.id and user_id = e.uid;
      removed := removed + 1;
    end if;
  end loop;

  perform public.log_moderation('revert', 'build', b.id::text, note);
  return jsonb_build_object('version', nb.version, 'removed_contributors', removed);  -- 알림·경험치 변화 없음
end;
$$;

create function public.revert_build(p_build bigint, p_revision bigint, p_version integer, p_note text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.revert_build_unchecked(p_build, p_revision, p_version, p_note);
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 빌드 숨기기·다시 공개: 운영진 (감독관은 범위 제한)
-- ---------------------------------------------------------------------
-- 감독관이 처리할 수 있는 빌드: 공개 중인 상대법의 빌드, 시초가 일반 회원(또는 탈퇴)이고 본인이 아님
create function public.require_moderate_build(b public.builds)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_moderator() then
    return;
  end if;
  if not exists (select 1 from public.counters where id = b.counter_id and status = 'approved') then
    raise exception '숨긴 상대법의 빌드는 운영자만 처리할 수 있습니다.' using errcode = '42501';
  end if;
  if not public.moderatable_author(b.author_id) then
    raise exception '본인이나 운영진이 처음 등록한 빌드는 감독관이 처리할 수 없습니다.' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.hide_build(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  reason text;
  b public.builds%rowtype;
begin
  perform public.require_staff();  -- 043: 운영자 → 운영진
  reason := public.require_note(p_reason, '숨기는 사유');
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.require_moderate_build(b);
  if b.status = 'hidden' then
    raise exception '이미 숨긴 빌드입니다.' using errcode = '23514';
  end if;
  if b.status <> 'approved' then
    raise exception '공개 중인 빌드만 숨길 수 있습니다.' using errcode = '23514';
  end if;
  perform 1 from public.builds where counter_id = b.counter_id and status = 'approved' for update;
  if not exists (select 1 from public.builds where counter_id = b.counter_id and status = 'approved' and id <> b.id) then
    raise exception '마지막 공개 빌드라 숨길 수 없습니다. 다른 빌드를 먼저 승인하거나, 상대법을 숨겨 주세요.' using errcode = '23514';
  end if;
  update public.builds set status = 'hidden', hide_reason = reason, hidden_at = now() where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'hide', reason, (select auth.uid()));
  perform public.log_moderation('hide', 'build', b.id::text, reason);
  perform public.notify(b.author_id, 'build_hidden', reason, null, b.id);
end;
$$;

create or replace function public.restore_build(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  b public.builds%rowtype;
begin
  perform public.require_staff();  -- 043: 운영자 → 운영진
  note := public.require_note(p_note, '다시 공개 메모');
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.require_moderate_build(b);
  if b.status <> 'hidden' then
    raise exception '숨긴 빌드가 아닙니다.' using errcode = '23514';
  end if;
  -- 감독관은 감독관이 숨긴 것만 (마지막 숨김 기록의 처리자)
  perform public.require_restore_allowed(
    (select l.actor from public.build_status_log l where l.build_id = b.id and l.action = 'hide' order by l.created_at desc, l.id desc limit 1));
  update public.builds set status = 'approved', hide_reason = null, hidden_at = null where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'restore', note, (select auth.uid()));
  perform public.log_moderation('restore', 'build', b.id::text, note);
  perform public.notify(b.author_id, 'build_restored', note, null, b.id);
end;
$$;

-- 감독관: 처리할 수 있는 숨긴 빌드를 읽는다 (상대법 화면에서 [다시 공개]를 하려면 보여야 함). 운영자 규칙은 그대로
--   can_see_hidden(작성자) = 운영자 또는 (감독관 + 처리할 수 있는 작성자) — 글·댓글 읽기 정책과 같은 함수 (누구나 실행 가능)
create policy "builds: 감독관이 숨긴 빌드 읽기" on public.builds
  for select using (
    status = 'hidden' and public.can_see_hidden(author_id)
    and exists (select 1 from public.counters c where c.id = builds.counter_id and c.status = 'approved')
  );

-- ---------------------------------------------------------------------
-- 9. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.build_edit_check(public.builds, uuid) from public, anon, authenticated;
revoke execute on function public.wiki_report_reason_label(text) from public, anon, authenticated;
revoke execute on function public.purge_wiki_reports() from public, anon, authenticated;
revoke execute on function public.admin_build_revisions_unchecked(bigint, bigint, integer) from public, anon, authenticated;
revoke execute on function public.revert_build_unchecked(bigint, bigint, integer, text) from public, anon, authenticated;
revoke execute on function public.require_moderate_build(public.builds) from public, anon, authenticated;
revoke execute on function public.report_wiki(bigint, bigint, text, text) from public, anon;
revoke execute on function public.staff_wiki_reports(text, integer, integer) from public, anon;
revoke execute on function public.handle_wiki_report(bigint, text, text, boolean) from public, anon;
revoke execute on function public.admin_build_revisions(bigint, bigint, integer) from public, anon;
revoke execute on function public.revert_build(bigint, bigint, integer, text) from public, anon;
grant execute on function public.report_wiki(bigint, bigint, text, text) to authenticated;         -- 정식 회원인지는 함수 안에서
grant execute on function public.staff_wiki_reports(text, integer, integer) to authenticated;      -- 운영진인지는 함수 안에서
grant execute on function public.handle_wiki_report(bigint, text, text, boolean) to authenticated;
grant execute on function public.admin_build_revisions(bigint, bigint, integer) to authenticated;  -- 운영자인지는 함수 안에서
grant execute on function public.revert_build(bigint, bigint, integer, text) to authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_wiki_reports_revert.sql
