-- =====================================================================
-- 4단계: 제안·승인 시스템
-- - 제안 내용 검사 (필수 레벨, 글자 수, 중복 제안)를 DB에서도 한다
-- - 승인·거절·순서 변경·되돌리기는 운영자 전용 함수로만 한다 (한 번에 처리, 기록 필수)
-- - 운영자도 counters / matchup_docs / doc_revisions / 제안 상태를 직접 고칠 수 없다
-- 003_operator.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 문서 버전 관리
--    doc_revisions: 문서가 바뀔 때마다 그 시점 내용 전체를 한 줄씩 남긴다
--    matchup_docs.revision_id: 지금 보이는 문서가 어느 버전인가
-- ---------------------------------------------------------------------
alter table public.doc_revisions
  add column kind text not null default 'edit' check (kind in ('create', 'edit', 'revert')),
  add column reverted_from bigint references public.doc_revisions (id) on delete set null;
comment on column public.doc_revisions.kind is 'create: 새 카운터 승인 / edit: 수정 제안 승인 / revert: 운영자가 예전 버전으로 되돌림';

alter table public.matchup_docs
  add column revision_id bigint references public.doc_revisions (id) on delete set null;

-- 제안할 때 보고 있던 문서 버전 (승인 전에 문서가 바뀌었는지 운영자에게 경고하는 데 쓴다)
alter table public.edit_proposals
  add column base_revision_id bigint references public.doc_revisions (id) on delete set null;

-- 이미 있는 문서(초기 데이터 등)를 "처음 버전"으로 기록해 둔다 → 되돌리기 가능
with r as (
  insert into public.doc_revisions (counter_id, content, edited_by, kind, created_at)
  select d.counter_id,
         jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions),
         d.updated_by, 'create', d.updated_at
  from public.matchup_docs d
  where d.revision_id is null
    and not exists (select 1 from public.doc_revisions x where x.counter_id = d.counter_id)
  returning id, counter_id
)
update public.matchup_docs d set revision_id = r.id from r where d.counter_id = r.counter_id;

-- ---------------------------------------------------------------------
-- 2. 문서 내용 검사·정리
--    {summary, level_notes, lane_cautions}만 남기고 앞뒤 공백을 지운다.
--    문제가 있으면 사람이 읽을 수 있는 문장으로 오류를 낸다 (errcode 23514).
-- ---------------------------------------------------------------------
create function public.clean_doc_content(c jsonb)
returns jsonb language plpgsql immutable set search_path = ''
as $$
declare
  summary text;
  cautions text;
  notes jsonb := '{}'::jsonb;
  k text;
  v jsonb;
  lv int;
  req int;
begin
  if c is null or jsonb_typeof(c) <> 'object' then
    raise exception '문서 내용 형식이 잘못됐어요.' using errcode = '23514';
  end if;

  summary := btrim(coalesce(c ->> 'summary', ''));
  if summary = '' then
    raise exception '한 줄 요약을 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(summary) > 100 then
    raise exception '한 줄 요약은 100자 이하로 적어 주세요.' using errcode = '23514';
  end if;

  cautions := btrim(coalesce(c ->> 'lane_cautions', ''));
  if char_length(cautions) > 3000 then
    raise exception '라인전 주의사항은 3000자 이하로 적어 주세요.' using errcode = '23514';
  end if;

  if jsonb_typeof(c -> 'level_notes') is distinct from 'object' then
    raise exception '레벨별 딜교법 형식이 잘못됐어요.' using errcode = '23514';
  end if;
  for k, v in select * from jsonb_each(c -> 'level_notes') loop
    if k !~ '^[0-9]{1,2}$' or k::int not between 1 and 18 then
      raise exception '레벨은 1~18 사이 숫자만 쓸 수 있어요. (%)', k using errcode = '23514';
    end if;
    lv := k::int;
    if jsonb_typeof(v) <> 'string' then
      raise exception '%레벨 내용 형식이 잘못됐어요.', lv using errcode = '23514';
    end if;
    if char_length(btrim(v #>> '{}')) > 1000 then
      raise exception '%레벨 내용은 1000자 이하로 적어 주세요.', lv using errcode = '23514';
    end if;
    if btrim(v #>> '{}') <> '' then
      notes := notes || jsonb_build_object(lv::text, btrim(v #>> '{}'));  -- "06" 같은 키도 "6"으로
    end if;
  end loop;

  foreach req in array array[1, 2, 3, 6, 9, 11] loop
    if not notes ? req::text then
      raise exception '%레벨 딜교법은 꼭 적어야 해요.', req using errcode = '23514';
    end if;
  end loop;

  return jsonb_build_object('summary', summary, 'level_notes', notes, 'lane_cautions', cautions);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 제안 넣을 때 검사 (클라이언트가 보낸 값은 믿지 않고 여기서 다시 정한다)
-- ---------------------------------------------------------------------
create function public.check_new_proposal()
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
    -- 대상 챔피언은 카운터에서 가져온다
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
    if exists (
      select 1 from public.counters
      where target_champion = new.target_champion and counter_champion = new.counter_champion and status = 'approved'
    ) then
      raise exception '이미 등록된 카운터예요. 문서 수정 제안을 이용해 주세요.' using errcode = '23514';
    end if;
  end if;

  -- 같은 사람이 같은 매치업에 대기 중인 제안을 여러 개 쌓지 못하게
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
create trigger edit_proposals_check before insert on public.edit_proposals
  for each row execute function public.check_new_proposal();

grant insert (base_revision_id) on public.edit_proposals to authenticated;

-- ---------------------------------------------------------------------
-- 4. 운영자 전용 함수 — 함수 안에서 운영자인지 먼저 확인한다
--    호출: supabase.rpc('approve_proposal', { p_id }) 등
-- ---------------------------------------------------------------------
create function public.require_operator()
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception '운영자만 할 수 있어요.' using errcode = '42501';
  end if;
end;
$$;

-- 제안 승인: 새 카운터면 카운터+문서+첫 기록, 문서 수정이면 문서 교체+기록. 돌려주는 값: 카운터 id
create function public.approve_proposal(p_id bigint)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
  cid bigint;
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
    -- 같은 챔피언의 카운터 목록을 잠가서, 동시에 승인해도 순서 번호가 겹치지 않게
    perform 1 from public.counters where target_champion = p.target_champion for update;
    insert into public.counters (target_champion, counter_champion, sort_order, status, proposed_by)
    values (
      p.target_champion, p.counter_champion,
      coalesce((select max(sort_order) + 1 from public.counters
                where target_champion = p.target_champion and status = 'approved'), 0),
      'approved', p.proposer_id
    )
    on conflict (target_champion, counter_champion) do update
      set status = 'approved', sort_order = excluded.sort_order, proposed_by = excluded.proposed_by
      where public.counters.status <> 'approved'
    returning id into cid;
    if cid is null then
      raise exception '이미 등록된 카운터예요. 이 제안은 거절해 주세요.' using errcode = '23514';
    end if;
  else
    select id into cid from public.counters where id = p.counter_id and status = 'approved' for update;
    if cid is null then
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

-- 제안 거절 (사유 필수)
create function public.reject_proposal(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  reason text := btrim(coalesce(p_reason, ''));
  st text;
begin
  perform public.require_operator();
  if reason = '' then
    raise exception '거절 사유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(reason) > 500 then
    raise exception '거절 사유는 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  select status into st from public.edit_proposals where id = p_id for update;
  if st is null then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if st <> 'pending' then
    raise exception '이미 처리된 제안이에요.' using errcode = '23514';
  end if;
  update public.edit_proposals
     set status = 'rejected', reject_reason = reason, reviewed_by = (select auth.uid()), reviewed_at = now()
   where id = p_id;
end;
$$;

-- 카운터 순서 변경: p_ids = 그 챔피언의 공개된 카운터 id 전부를 새 순서대로
create function public.reorder_counters(p_target text, p_ids bigint[])
returns void language plpgsql security definer set search_path = ''
as $$
declare
  current_ids bigint[];
begin
  perform public.require_operator();
  select coalesce(array_agg(id order by id), '{}') into current_ids
  from (select id from public.counters
        where target_champion = p_target and status = 'approved' for update) c;
  if p_ids is null
     or cardinality(p_ids) <> cardinality(current_ids)
     or (select coalesce(array_agg(distinct x order by x), '{}') from unnest(p_ids) x) is distinct from current_ids then
    raise exception '그 사이 카운터 목록이 바뀌었어요. 새로고침한 뒤 다시 정해 주세요.' using errcode = '23514';
  end if;
  update public.counters c
     set sort_order = o.ord - 1
    from unnest(p_ids) with ordinality as o (id, ord)
   where c.id = o.id and c.sort_order is distinct from o.ord - 1;
end;
$$;

-- 문서를 예전 버전으로 되돌리기: 그 버전 내용으로 바꾸고 "되돌림" 기록을 새로 남긴다
create function public.revert_doc(p_revision_id bigint)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  r public.doc_revisions%rowtype;
  cur bigint;
  rid bigint;
begin
  perform public.require_operator();
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

  insert into public.doc_revisions (counter_id, content, edited_by, approved_by, kind, reverted_from)
  values (r.counter_id, r.content, (select auth.uid()), (select auth.uid()), 'revert', r.id)
  returning id into rid;
  update public.matchup_docs
     set summary = r.content ->> 'summary', level_notes = r.content -> 'level_notes',
         lane_cautions = r.content ->> 'lane_cautions', updated_by = (select auth.uid()), revision_id = rid
   where counter_id = r.counter_id;
  return rid;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 직접 쓰기 막기: 위 함수만 문서·카운터·제안 상태를 바꿀 수 있다 (운영자 포함)
--    → 승인 없이 문서가 바뀌거나, 기록 없이 바뀌는 일이 없다
-- ---------------------------------------------------------------------
revoke insert, update, delete on public.counters, public.matchup_docs, public.doc_revisions from authenticated;
revoke update on public.edit_proposals from authenticated;

drop policy "counters: 관리자 쓰기" on public.counters;
drop policy "matchup_docs: 관리자 쓰기" on public.matchup_docs;
drop policy "edit_proposals: 관리자 처리" on public.edit_proposals;
drop policy "doc_revisions: 관리자" on public.doc_revisions;
create policy "doc_revisions: 운영자 읽기" on public.doc_revisions
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 6. 함수 실행 권한
-- ---------------------------------------------------------------------
revoke execute on function public.clean_doc_content(jsonb) from public, anon, authenticated;
revoke execute on function public.check_new_proposal() from public, anon, authenticated;
revoke execute on function public.require_operator() from public, anon, authenticated;
revoke execute on function public.approve_proposal(bigint) from public, anon;
revoke execute on function public.reject_proposal(bigint, text) from public, anon;
revoke execute on function public.reorder_counters(text, bigint[]) from public, anon;
revoke execute on function public.revert_doc(bigint) from public, anon;
grant execute on function public.approve_proposal(bigint) to authenticated;
grant execute on function public.reject_proposal(bigint, text) to authenticated;
grant execute on function public.reorder_counters(text, bigint[]) to authenticated;
grant execute on function public.revert_doc(bigint) to authenticated;

commit;
