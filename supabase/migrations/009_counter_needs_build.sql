-- =====================================================================
-- 새 카운터 제안 = 글 + 빌드 1개 (예외 없음)
-- - 새 카운터 제안에는 build(jsonb)가 반드시 있어야 한다. 넣을 때·다시 제출할 때 빌드 등록과 같은 규칙으로 검사.
-- - 승인하면 그 빌드가 카운터의 첫 공개 빌드가 된다 (builds.proposal_id로 연결). 거절하면 빌드도 제안과 함께 거절된 채 남는다.
-- - 재검토 요청 때는 글과 빌드를 같이 고쳐 다시 제출. 다시 승인될 때 빌드가 바뀌었으면 원래 첫 빌드는 숨기고 고친 빌드를 공개.
-- - 공개 빌드가 하나뿐이면 숨길 수 없다. 공개 빌드가 없는 숨긴 카운터는 다시 공개할 수 없다 (재검토로 빌드를 받는다).
-- - 이미 승인 대기 중인 "빌드 없는 새 카운터 제안"은 자동 거절 + 알림.
-- - "예시 빌드"(is_example) 개념을 없앤다. 작성자가 없는 빌드 = 탈퇴한 유저.
-- 008_builds.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 빌드 내용 검사를 함수 하나로 (빌드 등록 트리거와 새 카운터 제안이 같이 쓴다)
--    b = { runes, summoner_spells, starting_items, core_items, skill_order, early_skills, patch }
--    돌려주는 값: 정리된 같은 모양 (같은 빌드인지 비교할 때는 patch를 뺀다)
-- ---------------------------------------------------------------------
create function public.text_array(j jsonb, what text)
returns text[] language plpgsql immutable set search_path = ''
as $$
begin
  if jsonb_typeof(j) is distinct from 'array' then
    raise exception '%을(를) 골라 주세요.', what using errcode = '23514';
  end if;
  if exists (select 1 from jsonb_array_elements(j) x where jsonb_typeof(x) <> 'string') then
    raise exception '% 형식이 잘못됐어요.', what using errcode = '23514';
  end if;
  return array(select jsonb_array_elements_text(j));
end;
$$;

create function public.clean_build(b jsonb)
returns jsonb language plpgsql immutable set search_path = ''
as $$
declare
  runes jsonb;
  spells text[];
  starting text[];
  core text[];
  skills text[];
  early text[];
  patch text;
begin
  if jsonb_typeof(b) is distinct from 'object' then
    raise exception '빌드(룬·주문·아이템·스킬)를 채워 주세요.' using errcode = '23514';
  end if;
  runes := public.clean_build_runes(b -> 'runes');

  spells := public.text_array(b -> 'summoner_spells', '소환사 주문');
  if cardinality(spells) <> 2 or exists (select 1 from unnest(spells) s where s !~ '^Summoner[A-Za-z]{1,30}$') then
    raise exception '소환사 주문을 2개 골라 주세요.' using errcode = '23514';
  end if;
  if spells[1] = spells[2] then
    raise exception '같은 소환사 주문을 두 번 고를 수 없어요.' using errcode = '23514';
  end if;

  starting := public.text_array(b -> 'starting_items', '시작 아이템');
  core := public.text_array(b -> 'core_items', '핵심 템트리');
  perform public.check_build_ids(starting, '시작 아이템', 1, 4, false);
  perform public.check_build_ids(core, '핵심 템트리', 3, 6, true);

  begin
    skills := public.text_array(b -> 'skill_order', '스킬 선마 순서');
  exception when others then
    skills := null;
  end;
  if skills is null or cardinality(skills) <> 3 or (select array_agg(x order by x) from unnest(skills) x) <> array['E', 'Q', 'W'] then
    raise exception '스킬 선마 순서는 Q·W·E를 한 번씩 골라 주세요.' using errcode = '23514';
  end if;

  begin
    early := public.text_array(b -> 'early_skills', '1·2·3레벨 스킬');
  exception when others then
    early := null;
  end;
  if early is null or cardinality(early) <> 3 or exists (select 1 from unnest(early) x where x not in ('Q', 'W', 'E')) then
    raise exception '1·2·3레벨에 찍는 스킬을 골라 주세요. (Q·W·E 중에서)' using errcode = '23514';
  end if;

  patch := b ->> 'patch';
  if jsonb_typeof(b -> 'patch') is distinct from 'string' or patch !~ '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$' then
    raise exception '패치 버전 형식이 잘못됐어요.' using errcode = '23514';
  end if;

  return jsonb_build_object(
    'runes', runes, 'summoner_spells', to_jsonb(spells), 'starting_items', to_jsonb(starting), 'core_items', to_jsonb(core),
    'skill_order', to_jsonb(skills), 'early_skills', to_jsonb(early), 'patch', patch
  );
end;
$$;

-- 빌드 행 → 위와 같은 모양
create function public.build_json(b public.builds)
returns jsonb language sql immutable set search_path = ''
as $$
  select jsonb_build_object(
    'runes', b.runes, 'summoner_spells', to_jsonb(b.summoner_spells), 'starting_items', to_jsonb(b.starting_items),
    'core_items', to_jsonb(b.core_items), 'skill_order', b.skill_order, 'early_skills', to_jsonb(b.early_skills), 'patch', b.patch
  );
$$;

-- 같은 빌드인지 비교하는 값 = 패치를 뺀 내용 (008과 같은 이름, 모양만 build_json 기준으로)
create or replace function public.build_signature(b public.builds)
returns jsonb language sql immutable set search_path = ''
as $$
  select public.build_json(b) - 'patch';
$$;

-- ---------------------------------------------------------------------
-- 2. builds: 예시 빌드 없애기, 제안 연결, 등록 검사 다시 만들기
-- ---------------------------------------------------------------------
alter table public.builds
  drop column is_example,
  add column proposal_id bigint references public.edit_proposals (id) on delete set null;
comment on column public.builds.proposal_id is '새 카운터 제안과 함께 공개된 빌드면 그 제안 (카운터의 첫 빌드)';
comment on column public.builds.author_id is '작성자. 비어 있으면 탈퇴한 유저';
create index builds_proposal_idx on public.builds (proposal_id) where proposal_id is not null;

create or replace function public.check_new_build()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  st text;
  c jsonb;
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
  if new.status = 'pending' and exists (
    select 1 from public.builds b
    where b.counter_id = new.counter_id and b.author_id = new.author_id and b.status = 'pending'
  ) then
    raise exception '이 매치업에 이미 승인 대기 중인 내 빌드가 있어요. 처리된 뒤에 다시 등록해 주세요.' using errcode = '23514';
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

-- 008의 4-인자 검사 도우미는 clean_build가 계속 쓴다

-- ---------------------------------------------------------------------
-- 3. edit_proposals.build: 새 카운터 제안에는 필수, 문서 수정 제안에는 없음 (나머지 검사는 005와 같음)
--    (지난 제안 기록은 건드리지 않으려고 표 제약 대신 넣을 때·다시 제출할 때 검사한다)
-- ---------------------------------------------------------------------
alter table public.edit_proposals add column build jsonb;
comment on column public.edit_proposals.build is '새 카운터 제안의 빌드 (승인되면 카운터의 첫 빌드). 문서 수정 제안은 null';
grant insert (build) on public.edit_proposals to authenticated;

create or replace function public.check_new_proposal()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  c public.counters%rowtype;
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

-- ---------------------------------------------------------------------
-- 4. 제안의 빌드를 공개 (승인 함수 안에서만). 돌려주는 값: 공개된 빌드 id (이미 똑같은 공개 빌드가 있으면 그것)
--    재검토 후 다시 승인: 원래 첫 빌드와 다르면 원래 것은 숨기고("재검토로 교체") 고친 빌드를 공개
-- ---------------------------------------------------------------------
create function public.publish_proposal_build(p public.edit_proposals, p_counter_id bigint, p_note text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  b jsonb := public.clean_build(p.build);
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
       status, approve_note, reviewed_by, reviewed_at)
    values (
      p_counter_id, p.proposer_id, p.id, b -> 'runes',
      array(select jsonb_array_elements_text(b -> 'summoner_spells')),
      array(select jsonb_array_elements_text(b -> 'starting_items')),
      array(select jsonb_array_elements_text(b -> 'core_items')),
      b -> 'skill_order',
      array(select jsonb_array_elements_text(b -> 'early_skills')),
      b ->> 'patch', 'approved', p_note, (select auth.uid()), now()
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
-- 5. 승인: 008과 같고, 카운터를 공개한 뒤 제안의 빌드를 공개한다 (빌드 없는 새 카운터 제안은 승인 불가)
-- ---------------------------------------------------------------------
create or replace function public.approve_proposal(p_id bigint, p_note text)
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
  if p.type = 'new_counter' and p.build is null then
    raise exception '빌드가 없는 새 카운터 제안이라 승인할 수 없어요. 거절해 주세요.' using errcode = '23514';
  end if;
  content := public.clean_doc_content(p.content);

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

    perform public.publish_proposal_build(p, cid, note);

    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (cid, 'restore', note, p.id, (select auth.uid()));
    perform public.notify(p.proposer_id, 'proposal_approved', note, p.id, null);
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
  if p.type = 'new_counter' then
    perform public.publish_proposal_build(p, cid, note);
  end if;
  perform public.notify(p.proposer_id, 'proposal_approved', note, p.id, null);
  -- (6단계) 경험치 지급은 여기에 추가
  return cid;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 재검토 요청: 007과 같고, 고칠 시작값에 빌드도 넣는다 (그 제안의 지금 공개 빌드 → 없으면 제안에 있던 빌드)
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
  cur_build jsonb;
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
  select public.build_json(b) into cur_build from public.builds b
   where b.proposal_id = pid and b.status = 'approved' order by b.id desc limit 1;

  update public.edit_proposals
     set status = 'revision_requested', revision_note = note,
         revision_requested_by = (select auth.uid()), revision_requested_at = now(),
         content = doc, base_revision_id = rid, reject_reason = null,
         build = coalesce(cur_build, build)
   where id = pid;

  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'revision_request', note, pid, (select auth.uid()));

  insert into public.notifications (user_id, kind, proposal_id, message)
  values (who, 'revision_request', pid, note);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 다시 제출: 글 + 빌드 (빌드 필수). 둘 다 그대로면 거부 (빌드는 패치를 빼고 비교)
-- ---------------------------------------------------------------------
drop function public.resubmit_proposal(bigint, jsonb);
create function public.resubmit_proposal(p_id bigint, p_content jsonb, p_build jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
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
  select status into st from public.counters where id = p.counter_id for update;
  if st is distinct from 'hidden' then
    raise exception '이 카운터는 지금 다시 제출할 수 없어요.' using errcode = '23514';
  end if;
  new_content := public.clean_doc_content(p_content);
  if p_build is null then
    raise exception '빌드도 함께 채워 주세요. 새 카운터 제안에는 빌드가 꼭 있어야 해요.' using errcode = '23514';
  end if;
  new_build := public.clean_build(p_build);
  if new_content = public.clean_doc_content(p.content)
     and p.build is not null and new_build - 'patch' = p.build - 'patch' then
    raise exception '고친 내용이 없어요. 운영자 메모를 보고 글이나 빌드를 고쳐 주세요.' using errcode = '23514';
  end if;

  update public.edit_proposals
     set status = 'pending', content = new_content, build = new_build, resubmitted_at = now(),
         reviewed_by = null, reviewed_at = null
   where id = p.id;

  update public.notifications set read_at = now()
   where proposal_id = p.id and kind = 'revision_request' and read_at is null;

  insert into public.counter_status_log (counter_id, action, proposal_id, actor)
  values (p.counter_id, 'resubmit', p.id, (select auth.uid()));
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 공개 카운터에는 공개 빌드가 항상 있어야 한다
--    - 공개 빌드가 하나뿐이면 숨기기 불가 (008과 같고 이 검사만 추가)
--    - 공개 빌드가 없는 숨긴 카운터는 다시 공개 불가 (007과 같고 이 검사만 추가)
-- ---------------------------------------------------------------------
create or replace function public.hide_build(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  reason text;
  b public.builds%rowtype;
begin
  perform public.require_operator();
  reason := public.require_note(p_reason, '숨기는 사유');
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if b.status = 'hidden' then
    raise exception '이미 숨긴 빌드예요.' using errcode = '23514';
  end if;
  if b.status <> 'approved' then
    raise exception '공개 중인 빌드만 숨길 수 있어요.' using errcode = '23514';
  end if;
  perform 1 from public.builds where counter_id = b.counter_id and status = 'approved' for update;
  if not exists (select 1 from public.builds where counter_id = b.counter_id and status = 'approved' and id <> b.id) then
    raise exception '마지막 공개 빌드라 숨길 수 없어요. 다른 빌드를 먼저 승인하거나, 카운터를 숨겨 주세요.' using errcode = '23514';
  end if;
  update public.builds set status = 'hidden', hide_reason = reason, hidden_at = now() where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'hide', reason, (select auth.uid()));
  perform public.notify(b.author_id, 'build_hidden', reason, null, b.id);
  -- (6단계) 빌드 승인 경험치 회수는 여기에 추가 (SPEC 6-1 메모)
end;
$$;

create or replace function public.restore_counter(p_counter_id bigint, p_note text)
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
  if not exists (select 1 from public.builds where counter_id = p_counter_id and status = 'approved') then
    raise exception '공개 빌드가 없어서 다시 공개할 수 없어요. 재검토를 요청해서 빌드를 받거나, 숨긴 빌드를 먼저 다시 공개해 주세요.' using errcode = '23514';
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
  update public.notifications set read_at = now()
   where proposal_id = pid and kind = 'revision_request' and read_at is null;

  insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
  values (p_counter_id, 'restore', note, pid, (select auth.uid()));
  -- (6단계) 경험치 다시 지급은 여기에 추가 (SPEC 6-1 메모)
end;
$$;

-- ---------------------------------------------------------------------
-- 9. 이미 승인 대기 중인 "빌드 없는 새 카운터 제안" → 자동 거절 + 알림
--    (재검토 요청 중인 제안은 다시 제출할 때 빌드가 필수라 그대로 둔다)
-- ---------------------------------------------------------------------
do $$
declare
  r record;
  reason constant text := '새 규칙: 새 카운터 제안에는 빌드가 필요해요. 빌드와 함께 다시 제안해 주세요.';
begin
  for r in
    select id, proposer_id, counter_id from public.edit_proposals
     where type = 'new_counter' and status = 'pending' and build is null
  loop
    update public.edit_proposals set status = 'rejected', reject_reason = reason, reviewed_at = now() where id = r.id;
    if r.counter_id is not null then
      insert into public.counter_status_log (counter_id, action, reason, proposal_id) values (r.counter_id, 'reject', reason, r.id);
    end if;
    perform public.notify(r.proposer_id, 'proposal_rejected', reason, r.id, null);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 10. 함수 실행 권한
-- ---------------------------------------------------------------------
revoke execute on function public.text_array(jsonb, text) from public, anon, authenticated;
revoke execute on function public.clean_build(jsonb) from public, anon, authenticated;
revoke execute on function public.build_json(public.builds) from public, anon, authenticated;
revoke execute on function public.build_signature(public.builds) from public, anon, authenticated;
revoke execute on function public.check_new_build() from public, anon, authenticated;
revoke execute on function public.check_new_proposal() from public, anon, authenticated;
revoke execute on function public.publish_proposal_build(public.edit_proposals, bigint, text) from public, anon, authenticated;
revoke execute on function public.resubmit_proposal(bigint, jsonb, jsonb) from public, anon;
grant execute on function public.resubmit_proposal(bigint, jsonb, jsonb) to authenticated;
revoke execute on function public.approve_proposal(bigint, text) from public, anon;
grant execute on function public.approve_proposal(bigint, text) to authenticated;
revoke execute on function public.request_revision(bigint, text) from public, anon;
grant execute on function public.request_revision(bigint, text) to authenticated;
revoke execute on function public.hide_build(bigint, text) from public, anon;
grant execute on function public.hide_build(bigint, text) to authenticated;
revoke execute on function public.restore_counter(bigint, text) from public, anon;
grant execute on function public.restore_counter(bigint, text) to authenticated;

commit;
