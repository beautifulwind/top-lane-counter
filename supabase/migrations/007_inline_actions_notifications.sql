-- =====================================================================
-- 알림(확인하면 꺼짐) + 운영자 작업 메모 필수 (확인 창 대신 메모가 확인 단계)
-- - notifications: 받는 사람별 알림. DB 함수만 만들고, 본인만 읽음 처리 (mark_notifications_read)
--   지금 종류: revision_request(재검토 요청). 앞으로 다른 알림도 같은 표를 쓴다.
-- - 승인 메모 필수: approve_proposal(제안 id, 메모) — 메모 없는 예전 함수는 지운다. 제안자 /me에 보인다.
-- - 다시 공개 메모 필수: restore_counter(카운터 id, 메모)
-- - 되돌리기 메모 필수: revert_doc(버전 id, 메모) — 수정 기록(doc_revisions.note)에 남는다
-- 006_hidden_counter_tools.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- ⚠️ 실행 후 새 화면을 push하기 전까지는 승인·다시 공개·되돌리기가 안 된다 (예전 화면은 메모 없이 부름).
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 알림
-- ---------------------------------------------------------------------
create table public.notifications (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  kind         text not null check (kind in ('revision_request')),
  proposal_id  bigint references public.edit_proposals (id) on delete cascade,
  message      text,
  created_at   timestamptz not null default now(),
  read_at      timestamptz
);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;
comment on table public.notifications is '알림 — /me에서 확인하면 read_at이 채워지고 상단 빨간 점이 꺼진다';

-- Supabase 기본 권한을 걷어내고 본인 것 읽기만 연다. 만들기·읽음 처리는 아래 함수만.
revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
alter table public.notifications enable row level security;
create policy "notifications: 본인 읽기" on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));

-- 내 알림 읽음 처리: p_ids = 화면에 보인 내 알림 id들 (남의 것은 섞여 있어도 무시). 돌려주는 값: 처리한 개수
create function public.mark_notifications_read(p_ids bigint[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  if (select auth.uid()) is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  update public.notifications
     set read_at = now()
   where id = any (coalesce(p_ids, '{}')) and user_id = (select auth.uid()) and read_at is null;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- 이미 와 있는 재검토 요청 → 안 읽은 알림으로 만들어 둔다
insert into public.notifications (user_id, kind, proposal_id, message, created_at)
select proposer_id, 'revision_request', id, revision_note, coalesce(revision_requested_at, now())
from public.edit_proposals where status = 'revision_requested';

-- ---------------------------------------------------------------------
-- 2. 메모 칸
-- ---------------------------------------------------------------------
alter table public.edit_proposals add column approve_note text;
comment on column public.edit_proposals.approve_note is '승인 메모 — 제안자에게 보인다';
alter table public.doc_revisions add column note text;
comment on column public.doc_revisions.note is '되돌리기 메모 (운영자가 되돌릴 때 필수)';

-- 다시 공개 메모 필수 (이전 기록은 메모가 없을 수 있어 새 기록부터 검사)
alter table public.counter_status_log
  add constraint counter_status_log_restore_note_required
    check (action <> 'restore' or coalesce(btrim(reason), '') <> '') not valid;

-- 운영자 메모 공통 검사: 공백 정리, 필수, 500자
create function public.require_note(p_note text, p_what text)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  note text := btrim(coalesce(p_note, ''));
begin
  if note = '' then
    raise exception '%를 적어 주세요.', p_what using errcode = '23514';
  end if;
  if char_length(note) > 500 then
    raise exception '%는 500자 이하로 적어 주세요.', p_what using errcode = '23514';
  end if;
  return note;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 승인: 메모 필수 (나머지는 006과 같음)
-- ---------------------------------------------------------------------
drop function public.approve_proposal(bigint);
create function public.approve_proposal(p_id bigint, p_note text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  p public.edit_proposals%rowtype;
  c public.counters%rowtype;
  cid bigint;
  st text;
  rid bigint;
  content jsonb;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '승인 메모');
  select * into p from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status <> 'pending' then
    raise exception '이미 처리된 제안이에요.' using errcode = '23514';
  end if;
  content := public.clean_doc_content(p.content);

  -- 재검토 후 다시 낸 제안 → 고친 내용으로 문서 교체 + 다시 공개(목록 맨 뒤)
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
       set status = 'approved', approve_note = note, reviewed_by = (select auth.uid()), reviewed_at = now(),
           revoke_reason = null, revoked_by = null, revoked_at = null, reject_reason = null
     where id = p.id;

    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (cid, 'restore', note, p.id, (select auth.uid()));
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
     set status = 'approved', approve_note = note, reviewed_by = (select auth.uid()), reviewed_at = now(), counter_id = cid
   where id = p.id;
  -- (6단계) 경험치 지급은 여기에 추가
  return cid;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 다시 공개: 메모 필수 + 재검토 요청을 취소하면 그 알림도 읽음 처리 (나머지는 006과 같음)
--    (매개변수 기본값을 없애야 해서 지우고 다시 만든다)
-- ---------------------------------------------------------------------
drop function public.restore_counter(bigint, text);
create function public.restore_counter(p_counter_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  c public.counters%rowtype;
  pid bigint;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '다시 공개 메모');
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
  -- 취소된 재검토 요청 알림이 빨간 점으로 남지 않게
  update public.notifications set read_at = now()
   where proposal_id = pid and kind = 'revision_request' and read_at is null;

  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'restore', note, pid, (select auth.uid()));
  -- (6단계) 경험치 다시 지급은 여기에 추가 (SPEC 6-1 메모)
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 되돌리기: 메모 필수, 수정 기록에 남긴다 (나머지는 004와 같음)
-- ---------------------------------------------------------------------
drop function public.revert_doc(bigint);
create function public.revert_doc(p_revision_id bigint, p_note text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  r public.doc_revisions%rowtype;
  cur bigint;
  rid bigint;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '되돌리기 메모');
  select * into r from public.doc_revisions where id = p_revision_id;
  if not found then
    raise exception '그 버전을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  select revision_id into cur from public.matchup_docs where counter_id = r.counter_id for update;
  if not found then
    raise exception '매치업 문서를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if cur = r.id then
    raise exception '이미 지금 보이는 버전이에요.' using errcode = '23514';
  end if;

  insert into public.doc_revisions (counter_id, content, edited_by, approved_by, kind, reverted_from, note)
  values (r.counter_id, r.content, (select auth.uid()), (select auth.uid()), 'revert', r.id, note)
  returning id into rid;
  update public.matchup_docs
     set summary = r.content ->> 'summary', level_notes = r.content -> 'level_notes',
         lane_cautions = r.content ->> 'lane_cautions', updated_by = (select auth.uid()), revision_id = rid
   where counter_id = r.counter_id;
  return rid;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 재검토 요청 → 알림 만들기 / 다시 제출 → 알림 읽음 처리 (나머지는 006과 같음)
-- ---------------------------------------------------------------------
create or replace function public.request_revision(p_counter_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text := btrim(coalesce(p_note, ''));
  st text;
  pid bigint;
  pst text;
  who uuid;
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
  select status, proposer_id into pst, who from public.edit_proposals where id = pid for update;
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

  insert into public.notifications (user_id, kind, proposal_id, message)
  values (who, 'revision_request', pid, note);
end;
$$;

create or replace function public.resubmit_proposal(p_id bigint, p_content jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
  st text;
  new_content jsonb;
begin
  select * into p from public.edit_proposals where id = p_id for update;
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

  update public.notifications set read_at = now()
   where proposal_id = p.id and kind = 'revision_request' and read_at is null;

  insert into public.counter_status_log (counter_id, action, proposal_id, actor)
  values (p.counter_id, 'resubmit', p.id, (select auth.uid()));
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 함수 실행 권한
-- ---------------------------------------------------------------------
revoke execute on function public.require_note(text, text) from public, anon, authenticated;
revoke execute on function public.mark_notifications_read(bigint[]) from public, anon;
revoke execute on function public.approve_proposal(bigint, text) from public, anon;
revoke execute on function public.restore_counter(bigint, text) from public, anon;
revoke execute on function public.revert_doc(bigint, text) from public, anon;
revoke execute on function public.request_revision(bigint, text) from public, anon;
revoke execute on function public.resubmit_proposal(bigint, jsonb) from public, anon;
grant execute on function public.mark_notifications_read(bigint[]) to authenticated;
grant execute on function public.approve_proposal(bigint, text) to authenticated;
grant execute on function public.restore_counter(bigint, text) to authenticated;
grant execute on function public.revert_doc(bigint, text) to authenticated;
grant execute on function public.request_revision(bigint, text) to authenticated;
grant execute on function public.resubmit_proposal(bigint, jsonb) to authenticated;

commit;
