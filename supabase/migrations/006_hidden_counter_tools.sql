-- =====================================================================
-- 숨긴 카운터 도구: 미리보기 / 재검토 요청 / 완전 삭제 (모두 운영자 전용)
-- - 미리보기: 숨긴 카운터의 문서·빌드는 RLS(is_admin)가 이미 운영자에게만 보여 준다 → DB 변경 없음
-- - 재검토 요청: 운영자가 메모와 함께 요청 → 제안자가 고쳐서 다시 제출 → 승인하면 고친 내용으로 다시 공개
-- - 완전 삭제: 숨긴 카운터만. 카운터·문서·수정 기록·빌드·따봉·제안·숨김 기록을 지우고,
--   "누가 언제 왜 지웠나"는 카운터와 연결되지 않은 counter_deletions에 남긴다
-- 005_hide_counter.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 제안 상태 'revision_requested'(재검토 요청) + 메모 칸
-- ---------------------------------------------------------------------
alter table public.edit_proposals drop constraint edit_proposals_status_check;
alter table public.edit_proposals
  add column revision_note          text,
  add column revision_requested_by  uuid references public.profiles (id) on delete set null,
  add column revision_requested_at  timestamptz,
  add column resubmitted_at         timestamptz,  -- 재검토 후 다시 낸 때 (승인 대기 목록에 "다시 낸 제안" 표시)
  add constraint edit_proposals_status_check
    check (status in ('pending', 'approved', 'rejected', 'revoked', 'revision_requested')),
  add constraint edit_proposals_revision_note_required
    check (status <> 'revision_requested' or coalesce(btrim(revision_note), '') <> '');
comment on column public.edit_proposals.revision_note is '재검토 요청 메모 — 제안자에게 보인다';

-- 제안자 알림(빨간 점)용: 내 재검토 요청 찾기
create index edit_proposals_revision_idx on public.edit_proposals (proposer_id) where status = 'revision_requested';

-- ---------------------------------------------------------------------
-- 2. 숨김 기록 종류 늘리기
--    hide 숨김 / restore 다시 공개 / revision_request 재검토 요청 / resubmit 다시 제출 / reject 다시 낸 제안 거절
-- ---------------------------------------------------------------------
alter table public.counter_status_log drop constraint counter_status_log_action_check;
alter table public.counter_status_log drop constraint counter_status_log_check;
alter table public.counter_status_log
  add constraint counter_status_log_action_check
    check (action in ('hide', 'restore', 'revision_request', 'resubmit', 'reject')),
  add constraint counter_status_log_reason_required
    check (action not in ('hide', 'revision_request', 'reject') or coalesce(btrim(reason), '') <> '');

-- ---------------------------------------------------------------------
-- 3. 삭제 기록 — 카운터와 연결하지 않는다 (카운터가 지워져도 남게)
-- ---------------------------------------------------------------------
create table public.counter_deletions (
  id                bigint generated always as identity primary key,
  counter_id        bigint not null,  -- 지워진 카운터 id (참조 아님)
  target_champion   text not null,
  counter_champion  text not null,
  reason            text not null check (btrim(reason) <> ''),
  proposer_id       uuid references public.profiles (id) on delete set null,  -- 원래 제안자 (없으면 초기 데이터)
  deleted_by        uuid references public.profiles (id) on delete set null,
  deleted_at        timestamptz not null default now(),
  proposals_count   integer not null default 0,
  revisions_count   integer not null default 0,
  builds_count      integer not null default 0,
  votes_count       integer not null default 0
);
create index counter_deletions_at_idx on public.counter_deletions (deleted_at desc);

revoke all on public.counter_deletions from anon, authenticated;
grant select on public.counter_deletions to authenticated;
alter table public.counter_deletions enable row level security;
create policy "counter_deletions: 운영자 읽기" on public.counter_deletions
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 4. 도우미: 숨긴 카운터를 만든 원래 제안 (초기 데이터처럼 없으면 null)
-- ---------------------------------------------------------------------
create function public.origin_proposal_id(p_counter_id bigint)
returns bigint language sql stable security definer set search_path = ''
as $$
  select id from public.edit_proposals
   where type = 'new_counter' and counter_id = p_counter_id
   order by id desc limit 1;
$$;

-- ---------------------------------------------------------------------
-- 5. 재검토 요청 (운영자만, 메모 필수)
--    원래 제안 상태가 "승인 취소" 또는 "거절"(다시 낸 것이 거절됨)일 때만.
--    숨긴 시점의 문서 내용을 수정 출발점으로 넣어 둔다.
-- ---------------------------------------------------------------------
create function public.request_revision(p_counter_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text := btrim(coalesce(p_note, ''));
  st text;
  pid bigint;
  pst text;
  doc jsonb;
  rid bigint;
begin
  perform public.require_operator();
  if note = '' then
    raise exception '재검토 요청 메모를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(note) > 500 then
    raise exception '메모는 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  select status into st from public.counters where id = p_counter_id for update;
  if st is null then
    raise exception '카운터를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if st <> 'hidden' then
    raise exception '숨긴 카운터만 재검토를 요청할 수 있어요.' using errcode = '23514';
  end if;
  pid := public.origin_proposal_id(p_counter_id);
  if pid is null then
    raise exception '제안 없이 생긴 카운터라 재검토를 요청할 제안자가 없어요.' using errcode = '23514';
  end if;
  select status into pst from public.edit_proposals where id = pid for update;
  if pst = 'revision_requested' then
    raise exception '이미 재검토를 요청했어요. 제안자가 고쳐서 낼 때까지 기다려 주세요.' using errcode = '23514';
  end if;
  if pst = 'pending' then
    raise exception '제안자가 이미 다시 제출했어요. 승인 대기 목록에서 처리해 주세요.' using errcode = '23514';
  end if;
  if pst not in ('revoked', 'rejected') then
    raise exception '지금은 재검토를 요청할 수 없는 상태예요.' using errcode = '23514';
  end if;

  select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions), d.revision_id
    into doc, rid
    from public.matchup_docs d where d.counter_id = p_counter_id;
  if doc is null then
    raise exception '매치업 문서를 찾지 못했어요.' using errcode = 'P0002';
  end if;

  update public.edit_proposals
     set status = 'revision_requested', revision_note = note,
         revision_requested_by = (select auth.uid()), revision_requested_at = now(),
         content = doc, base_revision_id = rid, reject_reason = null
   where id = pid;

  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'revision_request', note, pid, (select auth.uid()));
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 고쳐서 다시 제출 (그 제안을 낸 본인만) → 승인 대기
-- ---------------------------------------------------------------------
create function public.resubmit_proposal(p_id bigint, p_content jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
  st text;
  new_content jsonb;
begin
  select * into p from public.edit_proposals where id = p_id for update;
  -- 남의 제안은 "없는 것"처럼 (있는지도 알려 주지 않음)
  if not found or p.proposer_id is distinct from (select auth.uid()) then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status <> 'revision_requested' then
    raise exception '재검토 요청을 받은 제안만 다시 제출할 수 있어요.' using errcode = '23514';
  end if;
  select status into st from public.counters where id = p.counter_id for update;
  if st is distinct from 'hidden' then
    raise exception '이 카운터는 지금 다시 제출할 수 없어요.' using errcode = '23514';
  end if;
  new_content := public.clean_doc_content(p_content);
  if new_content = public.clean_doc_content(p.content) then
    raise exception '고친 내용이 없어요. 운영자 메모를 보고 고쳐 주세요.' using errcode = '23514';
  end if;

  update public.edit_proposals
     set status = 'pending', content = new_content, resubmitted_at = now(),
         reviewed_by = null, reviewed_at = null
   where id = p.id;

  insert into public.counter_status_log (counter_id, action, proposal_id, actor)
  values (p.counter_id, 'resubmit', p.id, (select auth.uid()));
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 승인: 재검토 후 다시 낸 제안이면 → 고친 내용으로 문서 교체 + 수정 기록 + 다시 공개(목록 맨 뒤)
--    (나머지는 005와 같음)
-- ---------------------------------------------------------------------
create or replace function public.approve_proposal(p_id bigint)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
  c public.counters%rowtype;
  cid bigint;
  st text;
  rid bigint;
  content jsonb;
begin
  perform public.require_operator();
  select * into p from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status <> 'pending' then
    raise exception '이미 처리된 제안이에요.' using errcode = '23514';
  end if;
  content := public.clean_doc_content(p.content);

  -- 재검토 후 다시 낸 제안 (새 카운터 제안인데 이미 카운터가 정해져 있음)
  if p.type = 'new_counter' and p.counter_id is not null then
    select * into c from public.counters where id = p.counter_id for update;
    if not found or c.status <> 'hidden' then
      raise exception '숨긴 카운터가 아니라 승인할 수 없어요. 거절해 주세요.' using errcode = '23514';
    end if;
    cid := c.id;
    perform 1 from public.counters where target_champion = c.target_champion and status = 'approved' for update;

    insert into public.doc_revisions (counter_id, proposal_id, content, edited_by, approved_by, kind)
    values (cid, p.id, content, p.proposer_id, (select auth.uid()), 'edit')
    returning id into rid;
    update public.matchup_docs
       set summary = content ->> 'summary', level_notes = content -> 'level_notes',
           lane_cautions = content ->> 'lane_cautions', updated_by = p.proposer_id, revision_id = rid
     where counter_id = cid;

    update public.counters
       set status = 'approved',
           sort_order = coalesce((select max(sort_order) + 1 from public.counters
                                  where target_champion = c.target_champion and status = 'approved'), 0)
     where id = cid;

    update public.edit_proposals
       set status = 'approved', reviewed_by = (select auth.uid()), reviewed_at = now(),
           revoke_reason = null, revoked_by = null, revoked_at = null, reject_reason = null
     where id = p.id;

    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (cid, 'restore', '재검토 후 다시 낸 내용을 승인', p.id, (select auth.uid()));
    -- (6단계) 경험치 다시 지급은 여기에 추가 (SPEC 6-1 메모: 한 번분만)
    return cid;
  end if;

  if p.type = 'new_counter' then
    perform 1 from public.counters where target_champion = p.target_champion for update;
    select status into st from public.counters
     where target_champion = p.target_champion and counter_champion = p.counter_champion;
    if st = 'hidden' then
      raise exception '숨긴 카운터예요. 살리려면 [다시 공개]를 쓰고, 이 제안은 거절해 주세요.' using errcode = '23514';
    end if;
    insert into public.counters (target_champion, counter_champion, sort_order, status, proposed_by)
    values (
      p.target_champion, p.counter_champion,
      coalesce((select max(sort_order) + 1 from public.counters
                where target_champion = p.target_champion and status = 'approved'), 0),
      'approved', p.proposer_id
    )
    on conflict (target_champion, counter_champion) do update
      set status = 'approved', sort_order = excluded.sort_order, proposed_by = excluded.proposed_by
      where public.counters.status not in ('approved', 'hidden')
    returning id into cid;
    if cid is null then
      raise exception '이미 등록된 카운터예요. 이 제안은 거절해 주세요.' using errcode = '23514';
    end if;
  else
    select id, status into cid, st from public.counters where id = p.counter_id for update;
    if st = 'hidden' then
      raise exception '숨긴 카운터의 제안이라 승인할 수 없어요. 거절해 주세요.' using errcode = '23514';
    end if;
    if cid is null or st <> 'approved' then
      raise exception '수정할 매치업 문서를 찾지 못했어요.' using errcode = 'P0002';
    end if;
  end if;

  insert into public.doc_revisions (counter_id, proposal_id, content, edited_by, approved_by, kind)
  values (cid, p.id, content, p.proposer_id, (select auth.uid()),
          case when p.type = 'new_counter' then 'create' else 'edit' end)
  returning id into rid;

  insert into public.matchup_docs (counter_id, summary, level_notes, lane_cautions, updated_by, revision_id)
  values (cid, content ->> 'summary', content -> 'level_notes', content ->> 'lane_cautions', p.proposer_id, rid)
  on conflict (counter_id) do update
    set summary = excluded.summary, level_notes = excluded.level_notes,
        lane_cautions = excluded.lane_cautions, updated_by = excluded.updated_by,
        revision_id = excluded.revision_id;

  update public.edit_proposals
     set status = 'approved', reviewed_by = (select auth.uid()), reviewed_at = now(), counter_id = cid
   where id = p.id;
  -- (6단계) 경험치 지급은 여기에 추가
  return cid;
end;
$$;

-- 거절: 004와 같고, 재검토 후 다시 낸 제안이면 숨김 기록에도 남긴다 (카운터는 계속 숨김)
create or replace function public.reject_proposal(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  reason text := btrim(coalesce(p_reason, ''));
  p public.edit_proposals%rowtype;
begin
  perform public.require_operator();
  if reason = '' then
    raise exception '거절 사유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(reason) > 500 then
    raise exception '거절 사유는 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  select * into p from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status <> 'pending' then
    raise exception '이미 처리된 제안이에요.' using errcode = '23514';
  end if;
  update public.edit_proposals
     set status = 'rejected', reject_reason = reason, reviewed_by = (select auth.uid()), reviewed_at = now()
   where id = p_id;
  if p.type = 'new_counter' and p.counter_id is not null then
    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (p.counter_id, 'reject', reason, p.id, (select auth.uid()));
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 다시 공개: 005와 같고,
--    - 다시 제출돼 승인 대기 중이면 막는다 (그 제안부터 승인·거절)
--    - 재검토 요청 중이거나 다시 낸 것이 거절된 상태면 → 요청을 취소하고 원래 문서대로 공개, 제안은 다시 "승인"
-- ---------------------------------------------------------------------
create or replace function public.restore_counter(p_counter_id bigint, p_note text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text := nullif(btrim(coalesce(p_note, '')), '');
  c public.counters%rowtype;
  pid bigint;
begin
  perform public.require_operator();
  if char_length(note) > 500 then
    raise exception '메모는 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  select * into c from public.counters where id = p_counter_id for update;
  if not found then
    raise exception '카운터를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if c.status <> 'hidden' then
    raise exception '숨긴 카운터가 아니에요.' using errcode = '23514';
  end if;
  pid := public.origin_proposal_id(p_counter_id);
  if exists (select 1 from public.edit_proposals where id = pid and status = 'pending') then
    raise exception '제안자가 고쳐서 다시 낸 제안이 승인 대기 중이에요. 그 제안부터 승인하거나 거절해 주세요.' using errcode = '23514';
  end if;

  perform 1 from public.counters where target_champion = c.target_champion and status = 'approved' for update;
  update public.counters
     set status = 'approved',
         sort_order = coalesce((select max(sort_order) + 1 from public.counters
                                where target_champion = c.target_champion and status = 'approved'), 0)
   where id = p_counter_id;

  update public.edit_proposals
     set status = 'approved', revoke_reason = null, revoked_by = null, revoked_at = null, reject_reason = null
   where id = pid and status in ('revoked', 'revision_requested', 'rejected');
  if not found then
    pid := null;
  end if;

  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'restore', note, pid, (select auth.uid()));
  -- (6단계) 경험치 다시 지급은 여기에 추가 (SPEC 6-1 메모)
end;
$$;

-- ---------------------------------------------------------------------
-- 9. 완전 삭제 (운영자만, 숨긴 카운터만, 사유 필수)
--    p_confirm: 화면에서 확인한 이기는 챔피언 ID (예: 'Garen') — 실제 카운터와 다르면 거부
-- ---------------------------------------------------------------------
create function public.delete_counter(p_counter_id bigint, p_confirm text, p_reason text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  reason text := btrim(coalesce(p_reason, ''));
  c public.counters%rowtype;
  pid bigint;
  did bigint;
begin
  perform public.require_operator();
  if reason = '' then
    raise exception '삭제 사유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(reason) > 500 then
    raise exception '삭제 사유는 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  select * into c from public.counters where id = p_counter_id for update;
  if not found then
    raise exception '카운터를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if c.status <> 'hidden' then
    raise exception '숨긴 카운터만 삭제할 수 있어요. 먼저 숨겨 주세요.' using errcode = '23514';
  end if;
  if p_confirm is distinct from c.counter_champion then
    raise exception '확인한 챔피언이 이 카운터와 달라요. 새로고침한 뒤 다시 해 주세요.' using errcode = '23514';
  end if;
  pid := public.origin_proposal_id(p_counter_id);
  if exists (select 1 from public.edit_proposals where id = pid and status = 'pending') then
    raise exception '제안자가 고쳐서 다시 낸 제안이 승인 대기 중이에요. 그 제안부터 승인하거나 거절해 주세요.' using errcode = '23514';
  end if;

  insert into public.counter_deletions
    (counter_id, target_champion, counter_champion, reason, proposer_id, deleted_by,
     proposals_count, revisions_count, builds_count, votes_count)
  values (
    c.id, c.target_champion, c.counter_champion, reason,
    (select proposer_id from public.edit_proposals where id = pid), (select auth.uid()),
    (select count(*) from public.edit_proposals where counter_id = c.id),
    (select count(*) from public.doc_revisions where counter_id = c.id),
    (select count(*) from public.builds where counter_id = c.id),
    (select count(*) from public.build_votes v join public.builds b on b.id = v.build_id where b.counter_id = c.id)
  )
  returning id into did;

  -- on delete cascade: 문서, 수정 기록, 빌드 → 따봉, 이 카운터에 대한 제안, 숨김 기록
  delete from public.counters where id = c.id;
  -- (6단계) 경험치 회수는 여기에 추가 (SPEC 6-1 메모 — 삭제 전에 대상 기록을 모아 둘 것)
  return did;
end;
$$;

-- ---------------------------------------------------------------------
-- 10. 함수 실행 권한: 로그인한 사람만 부를 수 있고, 함수 안에서 운영자·본인인지 다시 확인한다
-- ---------------------------------------------------------------------
revoke execute on function public.origin_proposal_id(bigint) from public, anon, authenticated;
revoke execute on function public.request_revision(bigint, text) from public, anon;
revoke execute on function public.resubmit_proposal(bigint, jsonb) from public, anon;
revoke execute on function public.delete_counter(bigint, text, text) from public, anon;
grant execute on function public.request_revision(bigint, text) to authenticated;
grant execute on function public.resubmit_proposal(bigint, jsonb) to authenticated;
grant execute on function public.delete_counter(bigint, text, text) to authenticated;
-- create or replace는 기존 권한을 유지하지만, 혹시 몰라 다시 확인
revoke execute on function public.approve_proposal(bigint) from public, anon;
revoke execute on function public.reject_proposal(bigint, text) from public, anon;
revoke execute on function public.restore_counter(bigint, text) from public, anon;
grant execute on function public.approve_proposal(bigint) to authenticated;
grant execute on function public.reject_proposal(bigint, text) to authenticated;
grant execute on function public.restore_counter(bigint, text) to authenticated;

commit;
