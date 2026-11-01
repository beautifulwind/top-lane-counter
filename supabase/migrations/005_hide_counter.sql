-- =====================================================================
-- 카운터 숨기기(승인 취소) / 다시 공개
-- - 실수로 승인한 새 카운터를 지우지 않고 숨긴다 → 문서·수정 기록·빌드는 그대로 남고, 다시 공개할 수 있다
-- - 숨기면 그 카운터를 만든 제안은 "승인 취소"(revoked) + 사유 필수 → 제안자 /me에 보인다
-- - 숨기기·다시 공개는 운영자 전용 함수로만, 매번 counter_status_log에 기록
-- 004_proposals.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 상태 값 추가: counters.status에 'hidden', edit_proposals.status에 'revoked'
--    (기존 상태 제약을 이름 대신 내용으로 찾아 바꾼다)
-- ---------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select conrelid::regclass as tbl, conname
    from pg_constraint
    where contype = 'c'
      and conrelid in ('public.counters'::regclass, 'public.edit_proposals'::regclass)
      and pg_get_constraintdef(oid) ~ '\(status = ANY'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end;
$$;

alter table public.counters
  add constraint counters_status_check check (status in ('pending', 'approved', 'rejected', 'hidden'));
comment on column public.counters.status is 'approved: 공개 / hidden: 운영자가 숨김(승인 취소, 다시 공개 가능)';

alter table public.edit_proposals
  add column revoke_reason text,
  add column revoked_by    uuid references public.profiles (id) on delete set null,
  add column revoked_at    timestamptz,
  add constraint edit_proposals_status_check check (status in ('pending', 'approved', 'rejected', 'revoked')),
  add constraint edit_proposals_revoke_reason_required
    check (status <> 'revoked' or coalesce(btrim(revoke_reason), '') <> '');  -- 승인 취소 사유 필수
comment on column public.edit_proposals.revoke_reason is '승인 취소(카운터 숨김) 사유 — 제안자에게 보인다';

-- ---------------------------------------------------------------------
-- 2. 숨김·다시 공개 기록
-- ---------------------------------------------------------------------
create table public.counter_status_log (
  id           bigint generated always as identity primary key,
  counter_id   bigint not null references public.counters (id) on delete cascade,
  action       text not null check (action in ('hide', 'restore')),
  reason       text,  -- 숨김: 필수 / 다시 공개: 메모(선택)
  proposal_id  bigint references public.edit_proposals (id) on delete set null,
  actor        uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  check (action <> 'hide' or coalesce(btrim(reason), '') <> '')
);
create index counter_status_log_counter_idx on public.counter_status_log (counter_id, created_at desc);

-- Supabase는 새 표에 anon/authenticated 전체 권한을 기본으로 준다 → 걷어내고 운영자 읽기만 연다.
-- 쓰기는 아래 운영자 전용 함수만 한다.
revoke all on public.counter_status_log from anon, authenticated;
grant select on public.counter_status_log to authenticated;
alter table public.counter_status_log enable row level security;
create policy "counter_status_log: 운영자 읽기" on public.counter_status_log
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 3. 운영자 전용 함수
-- ---------------------------------------------------------------------

-- 카운터 숨기기(승인 취소): 사유 필수
create function public.hide_counter(p_counter_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  reason text := btrim(coalesce(p_reason, ''));
  st text;
  pid bigint;
begin
  perform public.require_operator();
  if reason = '' then
    raise exception '숨기는 사유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(reason) > 500 then
    raise exception '숨기는 사유는 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  select status into st from public.counters where id = p_counter_id for update;
  if st is null then
    raise exception '카운터를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if st = 'hidden' then
    raise exception '이미 숨긴 카운터예요.' using errcode = '23514';
  end if;
  if st <> 'approved' then
    raise exception '공개 중인 카운터만 숨길 수 있어요.' using errcode = '23514';
  end if;

  update public.counters set status = 'hidden' where id = p_counter_id;

  -- 이 카운터를 만든 새 카운터 제안 → 승인 취소 (초기 데이터처럼 제안 없이 생긴 카운터면 없음)
  update public.edit_proposals
     set status = 'revoked', revoke_reason = reason, revoked_by = (select auth.uid()), revoked_at = now()
   where type = 'new_counter' and counter_id = p_counter_id and status = 'approved'
  returning id into pid;

  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'hide', reason, pid, (select auth.uid()));
  -- (6단계) 이 승인으로 지급한 경험치 회수는 여기에 추가 (SPEC 6-1 메모)
end;
$$;

-- 숨긴 카운터 다시 공개: 목록 맨 뒤로, 제안은 다시 "승인"
create function public.restore_counter(p_counter_id bigint, p_note text default null)
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

  perform 1 from public.counters where target_champion = c.target_champion and status = 'approved' for update;
  update public.counters
     set status = 'approved',
         sort_order = coalesce((select max(sort_order) + 1 from public.counters
                                where target_champion = c.target_champion and status = 'approved'), 0)
   where id = p_counter_id;

  update public.edit_proposals
     set status = 'approved', revoke_reason = null, revoked_by = null, revoked_at = null
   where type = 'new_counter' and counter_id = p_counter_id and status = 'revoked'
  returning id into pid;

  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'restore', note, pid, (select auth.uid()));
  -- (6단계) 경험치 다시 지급은 여기에 추가 (SPEC 6-1 메모)
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 004의 제안 검사·승인 함수에 "숨긴 카운터" 규칙 추가 (나머지는 004와 같음)
--    - 숨긴 동안 같은 매치업은 새 카운터로 제안·승인 불가 (살리려면 다시 공개)
--    - 숨긴 카운터의 문서 수정 제안은 승인 불가 (거절은 가능)
-- ---------------------------------------------------------------------
create or replace function public.check_new_proposal()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  c public.counters%rowtype;
begin
  new.content := public.clean_doc_content(new.content);

  if new.type = 'doc_edit' then
    select * into c from public.counters where id = new.counter_id;
    if not found or c.status <> 'approved' then
      raise exception '수정할 매치업 문서를 찾지 못했어요.' using errcode = '23514';
    end if;
    new.target_champion := c.target_champion;
    new.counter_champion := c.counter_champion;
    if new.content = (
      select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
      from public.matchup_docs d where d.counter_id = c.id
    ) then
      raise exception '지금 문서와 달라진 내용이 없어요.' using errcode = '23514';
    end if;
  else  -- new_counter
    new.counter_id := null;
    new.base_revision_id := null;
    if new.target_champion !~ '^[A-Za-z]{1,30}$' or new.counter_champion !~ '^[A-Za-z]{1,30}$' then
      raise exception '챔피언을 다시 골라 주세요.' using errcode = '23514';
    end if;
    if new.target_champion = new.counter_champion then
      raise exception '같은 챔피언끼리는 카운터로 제안할 수 없어요.' using errcode = '23514';
    end if;
    select * into c from public.counters
     where target_champion = new.target_champion and counter_champion = new.counter_champion
       and status in ('approved', 'hidden');
    if found and c.status = 'approved' then
      raise exception '이미 등록된 카운터예요. 문서 수정 제안을 이용해 주세요.' using errcode = '23514';
    end if;
    if found then
      raise exception '운영자가 숨긴 카운터라 지금은 제안할 수 없어요.' using errcode = '23514';
    end if;
  end if;

  if exists (
    select 1 from public.edit_proposals
    where proposer_id = new.proposer_id and status = 'pending' and type = new.type
      and target_champion = new.target_champion and counter_champion = new.counter_champion
  ) then
    raise exception '이 매치업에 이미 대기 중인 내 제안이 있어요. 처리된 뒤에 다시 제안해 주세요.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.approve_proposal(p_id bigint)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
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

-- ---------------------------------------------------------------------
-- 5. 함수 실행 권한: 로그인한 사람만 부를 수 있고, 함수 안에서 운영자인지 다시 확인한다
--    (Supabase는 새 함수에 anon 실행 권한도 기본으로 준다 → 걷어낸다)
-- ---------------------------------------------------------------------
revoke execute on function public.hide_counter(bigint, text) from public, anon;
revoke execute on function public.restore_counter(bigint, text) from public, anon;
grant execute on function public.hide_counter(bigint, text) to authenticated;
grant execute on function public.restore_counter(bigint, text) to authenticated;
-- create or replace는 기존 권한을 유지하지만, 혹시 몰라 다시 확인
revoke execute on function public.check_new_proposal() from public, anon, authenticated;
revoke execute on function public.approve_proposal(bigint) from public, anon;
grant execute on function public.approve_proposal(bigint) to authenticated;

commit;
