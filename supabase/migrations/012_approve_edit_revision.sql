-- =====================================================================
-- 승인 대기 제안의 처리 = [승인] [재검토 요청] [거절]
-- - [승인]: 운영자가 내용(글·빌드)을 고쳐서 승인할 수 있다. 안 고쳤으면 그대로 공개.
--   · 원래 제안은 그대로 남고(edit_proposals.content/build, builds.original_build),
--     고친 내용은 edit_proposals.approved_content/approved_build에 남는다 (안 고쳤으면 null).
--   · 문서를 고쳤으면 수정 기록이 두 줄: 제안 원본(공개 안 됨, 작성자 = 제안자) + 운영자 수정(admin_edit, 지금 문서).
--   · 빌드를 고쳤으면 패치는 화면이 보낸 지금 패치, 안 고쳤으면 원래 패치.
--   · 작성자(제안자·빌드 작성자·카운터 제안자)는 그대로 → 경험치(6단계)도 제안자에게.
-- - [재검토 요청]: 승인 대기 제안·빌드에도. 제안자가 /me에서 고쳐 다시 내면 다시 승인 대기.
--   운영자는 기다리는 동안 [요청 취소](메모 필수, 원래대로 승인 대기) 또는 [거절]을 할 수 있다.
-- - 숨긴 카운터의 재검토(request_revision, [다시 공개]로 취소)는 그대로. 그 카운터를 만든 제안(다시 낸 것)에
--   [재검토 요청]을 하면 같은 흐름이 된다: 요청 취소는 [다시 공개]로, 거절도 가능 (계속 숨김, 다시 요청 가능).
-- 011_special_notes_label.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 표 칸·상태
-- ---------------------------------------------------------------------
alter table public.edit_proposals
  add column approved_content jsonb,
  add column approved_build   jsonb;
comment on column public.edit_proposals.approved_content is '운영자가 고쳐서 승인한 글 (안 고쳤으면 null, 원래 제안은 content)';
comment on column public.edit_proposals.approved_build is '운영자가 고쳐서 승인한 빌드 (안 고쳤으면 null, 원래 제안은 build)';

alter table public.builds drop constraint builds_status_check;
alter table public.builds
  add column original_build        jsonb,
  add column revision_note         text,
  add column revision_requested_by uuid references public.profiles (id) on delete set null,
  add column revision_requested_at timestamptz,
  add column resubmitted_at        timestamptz,
  add constraint builds_status_check check (status in ('pending', 'approved', 'rejected', 'hidden', 'revision_requested')),
  add constraint builds_revision_note_required check (status <> 'revision_requested' or coalesce(btrim(revision_note), '') <> '');
comment on column public.builds.status is 'pending 대기 / approved 공개 / rejected 거절 / hidden 운영자가 숨김 / revision_requested 재검토 요청 (작성자가 고쳐서 다시 냄)';
comment on column public.builds.original_build is '운영자가 고쳐서 승인했으면 작성자가 낸 원래 빌드 (안 고쳤으면 null)';
comment on column public.builds.revision_note is '재검토 요청 메모 — 작성자에게 보인다';

-- 이름 없는 check 제약을 내용으로 찾아 지운다 (010과 같은 방법)
do $$
declare
  r record;
  n int := 0;
begin
  for r in
    select conrelid::regclass as tbl, conname
    from pg_constraint
    where contype = 'c'
      and ((conrelid = 'public.build_status_log'::regclass and pg_get_constraintdef(oid) ~ '\(action = ANY')
        or (conrelid = 'public.doc_revisions'::regclass and pg_get_constraintdef(oid) ~ '\(kind = ANY'))
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    n := n + 1;
  end loop;
  if n <> 2 then
    raise exception 'build_status_log·doc_revisions의 종류 제약을 찾지 못했어요 (찾은 개수: %)', n;
  end if;
end;
$$;

alter table public.build_status_log
  add constraint build_status_log_action_check
  check (action in ('approve', 'reject', 'hide', 'restore', 'revision_request', 'revision_cancel', 'resubmit'));
alter table public.doc_revisions
  add constraint doc_revisions_kind_check check (kind in ('create', 'edit', 'revert', 'admin_edit'));
comment on column public.doc_revisions.kind is
  'create: 새 카운터 승인 / edit: 수정 제안 승인 / revert: 되돌림 / admin_edit: 운영자가 고쳐서 승인 (바로 앞 같은 제안의 줄 = 제안 원본, 공개 안 됨)';

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check check (kind in (
    'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected',
    'build_approved', 'build_rejected', 'build_hidden', 'build_restored'));

create index builds_revision_idx on public.builds (author_id) where status = 'revision_requested';

-- ---------------------------------------------------------------------
-- 2. "대기 중인 내 것 1개" 규칙에 재검토 중인 것도 넣는다 / 탈퇴 시 재검토 중인 빌드도 지운다
-- ---------------------------------------------------------------------
create or replace function public.check_new_proposal()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  c public.counters%rowtype;
  st text;
begin
  new.content := public.clean_doc_content(new.content);

  if new.type = 'doc_edit' then
    if new.build is not null then
      raise exception '문서 수정 제안에는 빌드를 넣지 않아요. 빌드는 [+ 빌드 등록]으로 보내 주세요.' using errcode = '23514';
    end if;
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
    if new.build is null then
      raise exception '새 카운터 제안에는 빌드가 꼭 있어야 해요. 룬·주문·아이템·스킬을 채워 주세요.' using errcode = '23514';
    end if;
    new.build := public.clean_build(new.build);
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

  select status into st from public.edit_proposals
   where proposer_id = new.proposer_id and status in ('pending', 'revision_requested') and type = new.type
     and target_champion = new.target_champion and counter_champion = new.counter_champion
   order by status = 'revision_requested' desc
   limit 1;
  if st = 'revision_requested' then
    raise exception '이 매치업에 재검토 요청을 받은 내 제안이 있어요. [내 활동]에서 고쳐서 다시 제출해 주세요.' using errcode = '23514';
  end if;
  if st = 'pending' then
    raise exception '이 매치업에 이미 대기 중인 내 제안이 있어요. 처리된 뒤에 다시 제안해 주세요.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.check_new_build()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  st text;
  c jsonb;
  mine text;
begin
  select status into st from public.counters where id = new.counter_id;
  if st is distinct from 'approved' then
    raise exception '빌드를 등록할 매치업을 찾지 못했어요.' using errcode = '23514';
  end if;

  c := public.clean_build(public.build_json(new));
  new.runes := c -> 'runes';
  new.summoner_spells := array(select jsonb_array_elements_text(c -> 'summoner_spells'));
  new.starting_items := array(select jsonb_array_elements_text(c -> 'starting_items'));
  new.core_items := array(select jsonb_array_elements_text(c -> 'core_items'));
  new.skill_order := c -> 'skill_order';
  new.early_skills := array(select jsonb_array_elements_text(c -> 'early_skills'));

  -- 유저가 직접 등록하는 빌드 (운영자 함수가 넣는 제안의 첫 빌드는 바로 공개라 해당 없음)
  if new.status = 'pending' then
    select b.status into mine from public.builds b
     where b.counter_id = new.counter_id and b.author_id = new.author_id and b.status in ('pending', 'revision_requested')
     order by b.status = 'revision_requested' desc
     limit 1;
    if mine = 'revision_requested' then
      raise exception '이 매치업에 재검토 요청을 받은 내 빌드가 있어요. [내 활동]에서 고쳐서 다시 제출해 주세요.' using errcode = '23514';
    end if;
    if mine = 'pending' then
      raise exception '이 매치업에 이미 승인 대기 중인 내 빌드가 있어요. 처리된 뒤에 다시 등록해 주세요.' using errcode = '23514';
    end if;
  end if;
  if exists (
    select 1 from public.builds b
    where b.counter_id = new.counter_id and b.status = 'approved' and public.build_signature(b) = public.build_signature(new)
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있어요. 따봉으로 응원해 주세요.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.delete_unpublished_builds()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.builds where author_id = old.id and status in ('pending', 'rejected', 'revision_requested');
  return old;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 도우미
-- ---------------------------------------------------------------------
-- 숨긴 카운터 재검토 흐름의 제안인가 (그 카운터를 만든 새 카운터 제안)
create function public.is_hidden_counter_flow(p public.edit_proposals)
returns boolean language sql immutable set search_path = ''
as $$
  select p.type = 'new_counter' and p.counter_id is not null;
$$;

-- 빌드 줄의 내용 칸을 정리된 빌드 jsonb로 바꾼다
create function public.set_build_fields(p_id bigint, b jsonb)
returns void language sql set search_path = ''
as $$
  update public.builds
     set runes = b -> 'runes',
         summoner_spells = array(select jsonb_array_elements_text(b -> 'summoner_spells')),
         starting_items = array(select jsonb_array_elements_text(b -> 'starting_items')),
         core_items = array(select jsonb_array_elements_text(b -> 'core_items')),
         skill_order = b -> 'skill_order',
         early_skills = array(select jsonb_array_elements_text(b -> 'early_skills')),
         patch = b ->> 'patch'
   where id = p_id;
$$;

-- 문서 수정 기록: 고쳤으면 두 줄(제안 원본 → 운영자 수정), 아니면 한 줄. 지금 문서가 가리킬 줄 id를 돌려준다.
create function public.add_approved_revisions(
  p public.edit_proposals, p_counter_id bigint, p_kind text, p_original jsonb, p_content jsonb, p_note text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  rid bigint;
begin
  insert into public.doc_revisions (counter_id, proposal_id, content, edited_by, approved_by, kind)
  values (p_counter_id, p.id, p_original, p.proposer_id, (select auth.uid()), p_kind)
  returning id into rid;
  if p_content is distinct from p_original then
    insert into public.doc_revisions (counter_id, proposal_id, content, edited_by, approved_by, kind, note)
    values (p_counter_id, p.id, p_content, (select auth.uid()), (select auth.uid()), 'admin_edit', p_note)
    returning id into rid;
  end if;
  return rid;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 새 카운터 제안의 첫 빌드 공개: 공개할 빌드(고쳤으면 고친 것)와 원래 빌드를 받는다
-- ---------------------------------------------------------------------
drop function public.publish_proposal_build(public.edit_proposals, bigint, text);
create function public.publish_proposal_build(
  p public.edit_proposals, p_counter_id bigint, p_note text, p_build jsonb, p_original jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  b jsonb := public.clean_build(p_build);
  bid bigint;
  old record;
begin
  select id into bid from public.builds x
   where x.counter_id = p_counter_id and x.status = 'approved' and public.build_signature(x) = b - 'patch'
   order by (x.proposal_id = p.id) desc nulls last, x.id
   limit 1;
  if bid is null then
    insert into public.builds
      (counter_id, author_id, proposal_id, runes, summoner_spells, starting_items, core_items, skill_order, early_skills, patch,
       status, approve_note, reviewed_by, reviewed_at, original_build)
    values (
      p_counter_id, p.proposer_id, p.id, b -> 'runes',
      array(select jsonb_array_elements_text(b -> 'summoner_spells')),
      array(select jsonb_array_elements_text(b -> 'starting_items')),
      array(select jsonb_array_elements_text(b -> 'core_items')),
      b -> 'skill_order',
      array(select jsonb_array_elements_text(b -> 'early_skills')),
      b ->> 'patch', 'approved', p_note, (select auth.uid()), now(), p_original
    )
    returning id into bid;
    insert into public.build_status_log (build_id, action, reason, actor) values (bid, 'approve', p_note, (select auth.uid()));
  end if;

  -- 같은 제안에서 나왔던 예전 첫 빌드는 숨긴다 (새 것이 공개된 뒤라 공개 빌드가 0개가 되지 않는다)
  for old in
    select id from public.builds where proposal_id = p.id and status = 'approved' and id <> bid
  loop
    update public.builds set status = 'hidden', hide_reason = '재검토로 교체: ' || p_note, hidden_at = now() where id = old.id;
    insert into public.build_status_log (build_id, action, reason, actor)
    values (old.id, 'hide', '재검토로 교체: ' || p_note, (select auth.uid()));
  end loop;
  -- (6단계) 첫 빌드는 카운터 승인 경험치(+100)에 포함, 빌드 승인 +30은 따로 주지 않는다 (SPEC 6-1)
  return bid;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 제안 승인: p_content / p_build가 null이면 그대로, 있으면 운영자가 고친 내용으로 공개
-- ---------------------------------------------------------------------
drop function public.approve_proposal(bigint, text);
create function public.approve_proposal(p_id bigint, p_note text, p_content jsonb, p_build jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  p public.edit_proposals%rowtype;
  c public.counters%rowtype;
  cid bigint;
  st text;
  rid bigint;
  orig_doc jsonb;
  new_doc jsonb;
  orig_build jsonb;
  new_build jsonb;
  nb jsonb;
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
  if p.type = 'new_counter' and p.build is null then
    raise exception '빌드가 없는 새 카운터 제안이라 승인할 수 없어요. 거절해 주세요.' using errcode = '23514';
  end if;
  if p.type = 'doc_edit' and p_build is not null then
    raise exception '문서 수정 제안에는 빌드가 없어요.' using errcode = '23514';
  end if;

  -- 운영자가 고친 내용 (정리했더니 원래와 같으면 안 고친 것)
  orig_doc := public.clean_doc_content(p.content);
  new_doc := orig_doc;
  if p_content is not null then
    new_doc := public.clean_doc_content(p_content);
  end if;
  if p.type = 'new_counter' then
    orig_build := public.clean_build(p.build);
    new_build := orig_build;
    if p_build is not null then
      nb := public.clean_build(p_build);
      if nb - 'patch' <> orig_build - 'patch' then
        new_build := nb;  -- 고친 빌드는 화면이 보낸 지금 패치
      end if;
    end if;
  end if;

  if p.type = 'new_counter' and p.counter_id is not null then
    -- 숨긴 카운터 재검토 후 다시 낸 제안
    select * into c from public.counters where id = p.counter_id for update;
    if not found or c.status <> 'hidden' then
      raise exception '숨긴 카운터가 아니라 승인할 수 없어요. 거절해 주세요.' using errcode = '23514';
    end if;
    cid := c.id;
    perform 1 from public.counters where target_champion = c.target_champion and status = 'approved' for update;

    rid := public.add_approved_revisions(p, cid, 'edit', orig_doc, new_doc, note);
    update public.matchup_docs
       set summary = new_doc ->> 'summary', level_notes = new_doc -> 'level_notes',
           lane_cautions = new_doc ->> 'lane_cautions', updated_by = p.proposer_id, revision_id = rid
     where counter_id = cid;

    update public.counters
       set status = 'approved',
           sort_order = coalesce((select max(sort_order) + 1 from public.counters
                                  where target_champion = c.target_champion and status = 'approved'), 0)
     where id = cid;

    update public.edit_proposals
       set status = 'approved', approve_note = note, reviewed_by = (select auth.uid()), reviewed_at = now(),
           revoke_reason = null, revoked_by = null, revoked_at = null, reject_reason = null,
           approved_content = case when new_doc is distinct from orig_doc then new_doc end,
           approved_build = case when new_build is distinct from orig_build then new_build end
     where id = p.id;

    perform public.publish_proposal_build(p, cid, note, new_build,
                                          case when new_build is distinct from orig_build then orig_build end);

    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (cid, 'restore', note, p.id, (select auth.uid()));
    perform public.notify(p.proposer_id, 'proposal_approved', note, p.id, null);
    -- (6단계) 경험치 다시 지급은 여기에 추가 (SPEC 6-1 메모: 한 번분만, 고쳐서 승인해도 제안자에게)
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
    if new_doc is distinct from orig_doc and new_doc = (
      select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
      from public.matchup_docs d where d.counter_id = cid
    ) then
      raise exception '고친 내용이 지금 문서와 같아요. 바꿀 게 없으면 거절해 주세요.' using errcode = '23514';
    end if;
  end if;

  rid := public.add_approved_revisions(p, cid, case when p.type = 'new_counter' then 'create' else 'edit' end,
                                       orig_doc, new_doc, note);

  insert into public.matchup_docs (counter_id, summary, level_notes, lane_cautions, updated_by, revision_id)
  values (cid, new_doc ->> 'summary', new_doc -> 'level_notes', new_doc ->> 'lane_cautions', p.proposer_id, rid)
  on conflict (counter_id) do update
    set summary = excluded.summary, level_notes = excluded.level_notes,
        lane_cautions = excluded.lane_cautions, updated_by = excluded.updated_by,
        revision_id = excluded.revision_id;

  update public.edit_proposals
     set status = 'approved', approve_note = note, reviewed_by = (select auth.uid()), reviewed_at = now(), counter_id = cid,
         approved_content = case when new_doc is distinct from orig_doc then new_doc end,
         approved_build = case when new_build is distinct from orig_build then new_build end
   where id = p.id;
  if p.type = 'new_counter' then
    perform public.publish_proposal_build(p, cid, note, new_build,
                                          case when new_build is distinct from orig_build then orig_build end);
  end if;
  perform public.notify(p.proposer_id, 'proposal_approved', note, p.id, null);
  -- (6단계) 경험치 지급은 여기에 추가 (고쳐서 승인해도 제안자에게)
  return cid;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 빌드 승인: p_build가 null이면 그대로, 있으면 고친 빌드로 공개 (원래 빌드는 original_build)
-- ---------------------------------------------------------------------
drop function public.approve_build(bigint, text);
create function public.approve_build(p_id bigint, p_note text, p_build jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  b public.builds%rowtype;
  st text;
  nb jsonb;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '승인 메모');
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if b.status <> 'pending' then
    raise exception '이미 처리된 빌드예요.' using errcode = '23514';
  end if;
  select status into st from public.counters where id = b.counter_id;
  if st = 'hidden' then
    raise exception '숨긴 카운터의 빌드라 승인할 수 없어요. 거절해 주세요.' using errcode = '23514';
  end if;
  if st is distinct from 'approved' then
    raise exception '매치업을 찾지 못했어요.' using errcode = 'P0002';
  end if;

  if p_build is not null then
    nb := public.clean_build(p_build);
    if nb - 'patch' <> public.build_signature(b) then
      update public.builds set original_build = public.build_json(b) where id = b.id;
      perform public.set_build_fields(b.id, nb);
      select * into b from public.builds where id = b.id;
    end if;
  end if;

  if exists (
    select 1 from public.builds x
    where x.counter_id = b.counter_id and x.status = 'approved' and x.id <> b.id
      and public.build_signature(x) = public.build_signature(b)
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있어요. 거절해 주세요.' using errcode = '23514';
  end if;

  update public.builds
     set status = 'approved', approve_note = note, reviewed_by = (select auth.uid()), reviewed_at = now()
   where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'approve', note, (select auth.uid()));
  perform public.notify(b.author_id, 'build_approved', note, null, b.id);
  -- (6단계) 빌드 승인 경험치(+30) 지급은 여기에 추가 (고쳐서 승인해도 작성자에게)
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 승인 대기 제안: 재검토 요청 / 요청 취소 / 거절(재검토 중인 것도) / 다시 제출
-- ---------------------------------------------------------------------
create function public.request_proposal_revision(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  p public.edit_proposals%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '재검토 요청 메모');
  select * into p from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status = 'revision_requested' then
    raise exception '이미 재검토를 요청했어요. 제안자가 고쳐서 낼 때까지 기다려 주세요.' using errcode = '23514';
  end if;
  if p.status <> 'pending' then
    raise exception '승인 대기 중인 제안만 재검토를 요청할 수 있어요.' using errcode = '23514';
  end if;

  update public.edit_proposals
     set status = 'revision_requested', revision_note = note,
         revision_requested_by = (select auth.uid()), revision_requested_at = now()
   where id = p.id;
  if public.is_hidden_counter_flow(p) then
    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (p.counter_id, 'revision_request', note, p.id, (select auth.uid()));
  end if;
  perform public.notify(p.proposer_id, 'revision_request', note, p.id, null);
end;
$$;

create function public.cancel_proposal_revision(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  p public.edit_proposals%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '요청 취소 메모');
  select * into p from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status <> 'revision_requested' then
    raise exception '재검토 요청 중인 제안이 아니에요.' using errcode = '23514';
  end if;
  if public.is_hidden_counter_flow(p) then
    raise exception '숨긴 카운터의 재검토 요청은 [다시 공개]로 취소해 주세요.' using errcode = '23514';
  end if;

  update public.edit_proposals
     set status = 'pending', revision_note = null, revision_requested_by = null, revision_requested_at = null
   where id = p.id;
  update public.notifications set read_at = now()
   where proposal_id = p.id and kind = 'revision_request' and read_at is null;
  perform public.notify(p.proposer_id, 'revision_cancelled', note, p.id, null);
end;
$$;

create or replace function public.reject_proposal(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  reason text;
  p public.edit_proposals%rowtype;
begin
  perform public.require_operator();
  reason := public.require_note(p_reason, '거절 사유');
  select * into p from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status not in ('pending', 'revision_requested') then
    raise exception '이미 처리된 제안이에요.' using errcode = '23514';
  end if;
  update public.edit_proposals
     set status = 'rejected', reject_reason = reason, reviewed_by = (select auth.uid()), reviewed_at = now()
   where id = p_id;
  update public.notifications set read_at = now()
   where proposal_id = p.id and kind = 'revision_request' and read_at is null;
  if public.is_hidden_counter_flow(p) then
    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (p.counter_id, 'reject', reason, p.id, (select auth.uid()));
  end if;
  perform public.notify(p.proposer_id, 'proposal_rejected', reason, p.id, null);
end;
$$;

drop function public.resubmit_proposal(bigint, jsonb, jsonb);
create function public.resubmit_proposal(p_id bigint, p_content jsonb, p_build jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
  hidden_flow boolean;
  st text;
  new_content jsonb;
  new_build jsonb;
begin
  select * into p from public.edit_proposals where id = p_id for update;
  if not found or p.proposer_id is distinct from (select auth.uid()) then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status <> 'revision_requested' then
    raise exception '재검토 요청을 받은 제안만 다시 제출할 수 있어요.' using errcode = '23514';
  end if;
  hidden_flow := public.is_hidden_counter_flow(p);
  new_content := public.clean_doc_content(p_content);

  if p.type = 'new_counter' then
    if p_build is null then
      raise exception '빌드도 함께 채워 주세요. 새 카운터 제안에는 빌드가 꼭 있어야 해요.' using errcode = '23514';
    end if;
    new_build := public.clean_build(p_build);
    if hidden_flow then
      select status into st from public.counters where id = p.counter_id for update;
      if st is distinct from 'hidden' then
        raise exception '이 카운터는 지금 다시 제출할 수 없어요.' using errcode = '23514';
      end if;
    else
      select status into st from public.counters
       where target_champion = p.target_champion and counter_champion = p.counter_champion and status in ('approved', 'hidden');
      if st = 'approved' then
        raise exception '그 사이 같은 카운터가 등록됐어요. 문서 수정 제안을 이용해 주세요.' using errcode = '23514';
      end if;
      if st = 'hidden' then
        raise exception '운영자가 숨긴 카운터라 지금은 다시 제출할 수 없어요.' using errcode = '23514';
      end if;
    end if;
  else  -- doc_edit
    if p_build is not null then
      raise exception '문서 수정 제안에는 빌드를 넣지 않아요.' using errcode = '23514';
    end if;
    select status into st from public.counters where id = p.counter_id;
    if st is distinct from 'approved' then
      raise exception '이 매치업은 지금 다시 제출할 수 없어요.' using errcode = '23514';
    end if;
    if new_content = (
      select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
      from public.matchup_docs d where d.counter_id = p.counter_id
    ) then
      raise exception '지금 문서와 달라진 내용이 없어요.' using errcode = '23514';
    end if;
  end if;

  if new_content = public.clean_doc_content(p.content)
     and (p.type = 'doc_edit' or (p.build is not null and new_build - 'patch' = p.build - 'patch')) then
    raise exception '고친 내용이 없어요. 운영자 메모를 보고 고쳐 주세요.' using errcode = '23514';
  end if;

  update public.edit_proposals
     set status = 'pending', content = new_content, build = coalesce(new_build, build), resubmitted_at = now(),
         reviewed_by = null, reviewed_at = null
   where id = p.id;

  update public.notifications set read_at = now()
   where proposal_id = p.id and kind = 'revision_request' and read_at is null;

  if hidden_flow then
    insert into public.counter_status_log (counter_id, action, proposal_id, actor)
    values (p.counter_id, 'resubmit', p.id, (select auth.uid()));
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 승인 대기 빌드: 재검토 요청 / 요청 취소 / 거절(재검토 중인 것도) / 다시 제출
-- ---------------------------------------------------------------------
create function public.request_build_revision(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  b public.builds%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '재검토 요청 메모');
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if b.status = 'revision_requested' then
    raise exception '이미 재검토를 요청했어요. 작성자가 고쳐서 낼 때까지 기다려 주세요.' using errcode = '23514';
  end if;
  if b.status <> 'pending' then
    raise exception '승인 대기 중인 빌드만 재검토를 요청할 수 있어요.' using errcode = '23514';
  end if;
  if (select status from public.counters where id = b.counter_id) is distinct from 'approved' then
    raise exception '숨긴 카운터의 빌드라 재검토를 요청할 수 없어요. 거절해 주세요.' using errcode = '23514';
  end if;
  if b.author_id is null then
    raise exception '작성자가 없는 빌드라 재검토를 요청할 수 없어요. 거절해 주세요.' using errcode = '23514';
  end if;

  update public.builds
     set status = 'revision_requested', revision_note = note,
         revision_requested_by = (select auth.uid()), revision_requested_at = now()
   where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'revision_request', note, (select auth.uid()));
  perform public.notify(b.author_id, 'revision_request', note, null, b.id);
end;
$$;

create function public.cancel_build_revision(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  b public.builds%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '요청 취소 메모');
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if b.status <> 'revision_requested' then
    raise exception '재검토 요청 중인 빌드가 아니에요.' using errcode = '23514';
  end if;
  update public.builds
     set status = 'pending', revision_note = null, revision_requested_by = null, revision_requested_at = null
   where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'revision_cancel', note, (select auth.uid()));
  update public.notifications set read_at = now()
   where build_id = b.id and kind = 'revision_request' and read_at is null;
  perform public.notify(b.author_id, 'revision_cancelled', note, null, b.id);
end;
$$;

create or replace function public.reject_build(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  reason text;
  b public.builds%rowtype;
begin
  perform public.require_operator();
  reason := public.require_note(p_reason, '거절 사유');
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if b.status not in ('pending', 'revision_requested') then
    raise exception '이미 처리된 빌드예요.' using errcode = '23514';
  end if;
  update public.builds
     set status = 'rejected', reject_reason = reason, reviewed_by = (select auth.uid()), reviewed_at = now()
   where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'reject', reason, (select auth.uid()));
  update public.notifications set read_at = now()
   where build_id = b.id and kind = 'revision_request' and read_at is null;
  perform public.notify(b.author_id, 'build_rejected', reason, null, b.id);
end;
$$;

create function public.resubmit_build(p_id bigint, p_build jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  b public.builds%rowtype;
  nb jsonb;
begin
  select * into b from public.builds where id = p_id for update;
  if not found or b.author_id is distinct from (select auth.uid()) then
    raise exception '빌드를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if b.status <> 'revision_requested' then
    raise exception '재검토 요청을 받은 빌드만 다시 제출할 수 있어요.' using errcode = '23514';
  end if;
  if (select status from public.counters where id = b.counter_id) is distinct from 'approved' then
    raise exception '이 매치업은 지금 다시 제출할 수 없어요.' using errcode = '23514';
  end if;
  nb := public.clean_build(p_build);
  if nb - 'patch' = public.build_signature(b) then
    raise exception '고친 내용이 없어요. 운영자 메모를 보고 고쳐 주세요.' using errcode = '23514';
  end if;
  if exists (
    select 1 from public.builds x
    where x.counter_id = b.counter_id and x.status = 'approved' and public.build_signature(x) = nb - 'patch'
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있어요. 따봉으로 응원해 주세요.' using errcode = '23514';
  end if;

  perform public.set_build_fields(b.id, nb);
  update public.builds set status = 'pending', resubmitted_at = now() where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor)
  values (b.id, 'resubmit', '작성자가 고쳐서 다시 제출', (select auth.uid()));
  update public.notifications set read_at = now()
   where build_id = b.id and kind = 'revision_request' and read_at is null;
end;
$$;

-- ---------------------------------------------------------------------
-- 9. 권한: 도우미는 막고, 처리 함수는 로그인한 사람만 (운영자 검사는 함수 안에서)
-- ---------------------------------------------------------------------
revoke execute on function public.is_hidden_counter_flow(public.edit_proposals) from public, anon, authenticated;
revoke execute on function public.set_build_fields(bigint, jsonb) from public, anon, authenticated;
revoke execute on function public.add_approved_revisions(public.edit_proposals, bigint, text, jsonb, jsonb, text) from public, anon, authenticated;
revoke execute on function public.publish_proposal_build(public.edit_proposals, bigint, text, jsonb, jsonb) from public, anon, authenticated;
revoke execute on function public.check_new_proposal() from public, anon, authenticated;
revoke execute on function public.check_new_build() from public, anon, authenticated;
revoke execute on function public.delete_unpublished_builds() from public, anon, authenticated;

revoke execute on function public.approve_proposal(bigint, text, jsonb, jsonb) from public, anon;
grant execute on function public.approve_proposal(bigint, text, jsonb, jsonb) to authenticated;
revoke execute on function public.approve_build(bigint, text, jsonb) from public, anon;
grant execute on function public.approve_build(bigint, text, jsonb) to authenticated;
revoke execute on function public.request_proposal_revision(bigint, text) from public, anon;
grant execute on function public.request_proposal_revision(bigint, text) to authenticated;
revoke execute on function public.cancel_proposal_revision(bigint, text) from public, anon;
grant execute on function public.cancel_proposal_revision(bigint, text) to authenticated;
revoke execute on function public.reject_proposal(bigint, text) from public, anon;
grant execute on function public.reject_proposal(bigint, text) to authenticated;
revoke execute on function public.resubmit_proposal(bigint, jsonb, jsonb) from public, anon;
grant execute on function public.resubmit_proposal(bigint, jsonb, jsonb) to authenticated;
revoke execute on function public.request_build_revision(bigint, text) from public, anon;
grant execute on function public.request_build_revision(bigint, text) to authenticated;
revoke execute on function public.cancel_build_revision(bigint, text) from public, anon;
grant execute on function public.cancel_build_revision(bigint, text) to authenticated;
revoke execute on function public.reject_build(bigint, text) from public, anon;
grant execute on function public.reject_build(bigint, text) to authenticated;
revoke execute on function public.resubmit_build(bigint, jsonb) from public, anon;
grant execute on function public.resubmit_build(bigint, jsonb) to authenticated;

commit;
