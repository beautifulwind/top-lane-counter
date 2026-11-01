-- =====================================================================
-- 5단계: 빌드 등록·승인 + 따봉
-- - 빌드 등록: 로그인(닉네임) 필요, 내용 검사 트리거, 승인 대기로만 들어간다
-- - 승인·거절·숨기기·다시 공개: 운영자 전용 함수, 메모 필수, build_status_log에 기록, 작성자에게 알림
-- - 따봉/비추: vote_build() 함수로만 (한 빌드 한 사람 한 표, 바꾸기·취소, 본인 빌드 불가, 공개된 빌드만)
--   표가 바뀔 때마다 build_vote_log에 남긴다 (6단계 경험치 계산용, 빌드·카운터가 지워져도 남음)
-- - 카운터 제안(새 카운터·문서 수정)도 승인·거절되면 제안자에게 알림
-- 007_inline_actions_notifications.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. builds 칸 추가·상태 'hidden'
-- ---------------------------------------------------------------------
alter table public.builds drop constraint builds_status_check;
alter table public.builds
  add column early_skills  text[],        -- 1·2·3레벨에 찍는 스킬 (예: {Q,E,W})
  add column approve_note  text,          -- 승인 메모 (작성자에게 보임)
  add column hide_reason   text,          -- 숨긴 사유 (작성자에게 보임)
  add column hidden_at     timestamptz,
  add column is_example    boolean not null default false,  -- 초기 데이터의 "예시 빌드" (작성자 없음)
  add constraint builds_status_check check (status in ('pending', 'approved', 'rejected', 'hidden')),
  add constraint builds_hide_reason_required check (status <> 'hidden' or coalesce(btrim(hide_reason), '') <> '');
comment on column public.builds.status is 'pending 대기 / approved 공개 / rejected 거절 / hidden 운영자가 숨김(승인 취소, 다시 공개 가능)';

-- 초기 데이터(작성자 없음) = 예시 빌드. 1·2·3레벨 스킬은 선마 순서로 채운다.
update public.builds set is_example = true where author_id is null;
update public.builds set early_skills = array(select jsonb_array_elements_text(skill_order)) where early_skills is null;
alter table public.builds alter column early_skills set not null;

create index builds_pending_idx on public.builds (created_at) where status = 'pending';
create index builds_author_idx on public.builds (author_id, created_at desc);

-- ---------------------------------------------------------------------
-- 2. 빌드 내용 검사·정리 (Data Dragon에 실제로 있는 ID인지는 화면이 확인하고, DB는 모양과 규칙을 본다)
-- ---------------------------------------------------------------------
create function public.check_build_ids(arr text[], what text, min_n int, max_n int, distinct_only boolean)
returns void language plpgsql immutable set search_path = ''
as $$
begin
  if arr is null or cardinality(arr) < min_n or cardinality(arr) > max_n then
    raise exception '%은(는) %~%개 골라 주세요.', what, min_n, max_n using errcode = '23514';
  end if;
  if exists (select 1 from unnest(arr) x where x !~ '^[0-9]{1,6}$') then
    raise exception '% 형식이 잘못됐어요.', what using errcode = '23514';
  end if;
  if distinct_only and (select count(distinct x) from unnest(arr) x) <> cardinality(arr) then
    raise exception '%에 같은 아이템이 두 번 들어 있어요.', what using errcode = '23514';
  end if;
end;
$$;

create function public.clean_build_runes(r jsonb)
returns jsonb language plpgsql immutable set search_path = ''
as $$
declare
  primary_path int;
  secondary_path int;
  keystone int;
  primary_ids int[];
  secondary_ids int[];
  shard_ids int[];
  all_ids int[];
begin
  if jsonb_typeof(r) is distinct from 'object'
     or jsonb_typeof(r -> 'primaryPath') is distinct from 'number' or jsonb_typeof(r -> 'keystone') is distinct from 'number'
     or jsonb_typeof(r -> 'secondaryPath') is distinct from 'number'
     or jsonb_typeof(r -> 'primary') is distinct from 'array' or jsonb_typeof(r -> 'secondary') is distinct from 'array'
     or jsonb_typeof(r -> 'shards') is distinct from 'array' then
    raise exception '특성(룬)을 모두 골라 주세요.' using errcode = '23514';
  end if;
  begin
    primary_path := (r ->> 'primaryPath')::int;
    secondary_path := (r ->> 'secondaryPath')::int;
    keystone := (r ->> 'keystone')::int;
    if (r ->> 'primaryPath')::numeric <> primary_path or (r ->> 'secondaryPath')::numeric <> secondary_path
       or (r ->> 'keystone')::numeric <> keystone then
      raise exception 'not integer';
    end if;
    primary_ids := array(select (x #>> '{}')::int from jsonb_array_elements(r -> 'primary') x);
    secondary_ids := array(select (x #>> '{}')::int from jsonb_array_elements(r -> 'secondary') x);
    shard_ids := array(select (x #>> '{}')::int from jsonb_array_elements(r -> 'shards') x);
  exception when others then
    raise exception '특성(룬) 형식이 잘못됐어요.' using errcode = '23514';
  end;
  if cardinality(primary_ids) <> 3 then
    raise exception '주 경로 룬은 3개 골라 주세요.' using errcode = '23514';
  end if;
  if cardinality(secondary_ids) <> 2 then
    raise exception '보조 룬은 2개 골라 주세요.' using errcode = '23514';
  end if;
  if cardinality(shard_ids) <> 3 then
    raise exception '능력치 파편은 3개 골라 주세요.' using errcode = '23514';
  end if;
  if primary_path = secondary_path then
    raise exception '보조 경로는 주 경로와 달라야 해요.' using errcode = '23514';
  end if;
  all_ids := array[keystone] || primary_ids || secondary_ids;
  if (select count(distinct x) from unnest(all_ids) x) <> 6 then
    raise exception '같은 룬을 두 번 고를 수 없어요.' using errcode = '23514';
  end if;
  -- 능력치 파편: 줄마다 정해진 값 중 하나 (공격 / 유연 / 방어)
  if not (shard_ids[1] = any (array[5008, 5005, 5007])
          and shard_ids[2] = any (array[5008, 5010, 5001])
          and shard_ids[3] = any (array[5011, 5013, 5001])) then
    raise exception '능력치 파편을 줄마다 하나씩 다시 골라 주세요.' using errcode = '23514';
  end if;
  return jsonb_build_object(
    'primaryPath', primary_path, 'keystone', keystone, 'primary', to_jsonb(primary_ids),
    'secondaryPath', secondary_path, 'secondary', to_jsonb(secondary_ids), 'shards', to_jsonb(shard_ids)
  );
end;
$$;

-- 같은 빌드인지 비교할 때 쓰는 내용 (패치·작성자 제외)
create function public.build_signature(b public.builds)
returns jsonb language sql immutable set search_path = ''
as $$
  select jsonb_build_object('runes', b.runes, 'spells', to_jsonb(b.summoner_spells), 'starting', to_jsonb(b.starting_items),
    'core', to_jsonb(b.core_items), 'skills', b.skill_order, 'early', to_jsonb(b.early_skills));
$$;

create function public.check_new_build()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  st text;
  skills text[];
begin
  select status into st from public.counters where id = new.counter_id;
  if st is distinct from 'approved' then
    raise exception '빌드를 등록할 매치업을 찾지 못했어요.' using errcode = '23514';
  end if;

  new.runes := public.clean_build_runes(new.runes);

  if new.summoner_spells is null or cardinality(new.summoner_spells) <> 2
     or exists (select 1 from unnest(new.summoner_spells) s where s !~ '^Summoner[A-Za-z]{1,30}$') then
    raise exception '소환사 주문을 2개 골라 주세요.' using errcode = '23514';
  end if;
  if new.summoner_spells[1] = new.summoner_spells[2] then
    raise exception '같은 소환사 주문을 두 번 고를 수 없어요.' using errcode = '23514';
  end if;

  perform public.check_build_ids(new.starting_items, '시작 아이템', 1, 4, false);
  perform public.check_build_ids(new.core_items, '핵심 템트리', 3, 6, true);

  begin
    skills := array(select jsonb_array_elements_text(new.skill_order));
  exception when others then
    skills := null;
  end;
  if skills is null or cardinality(skills) <> 3 or (select array_agg(x order by x) from unnest(skills) x) <> array['E', 'Q', 'W'] then
    raise exception '스킬 선마 순서는 Q·W·E를 한 번씩 골라 주세요.' using errcode = '23514';
  end if;
  new.skill_order := to_jsonb(skills);

  if new.early_skills is null or cardinality(new.early_skills) <> 3
     or exists (select 1 from unnest(new.early_skills) x where x is null or x not in ('Q', 'W', 'E')) then
    raise exception '1·2·3레벨에 찍는 스킬을 골라 주세요. (Q·W·E 중에서)' using errcode = '23514';
  end if;

  if new.patch is null or new.patch !~ '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$' then
    raise exception '패치 버전 형식이 잘못됐어요.' using errcode = '23514';
  end if;

  new.is_example := false;

  if exists (
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
create trigger builds_check_new before insert on public.builds
  for each row execute function public.check_new_build();

grant insert (early_skills) on public.builds to authenticated;

-- 탈퇴(프로필 삭제) 시: 공개되지 않은 내 빌드(대기·거절)는 지운다. 공개·숨긴 빌드는 작성자만 비운다(on delete set null).
create function public.delete_unpublished_builds()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.builds where author_id = old.id and status in ('pending', 'rejected');
  return old;
end;
$$;
create trigger profiles_delete_unpublished_builds before delete on public.profiles
  for each row execute function public.delete_unpublished_builds();

-- ---------------------------------------------------------------------
-- 3. 처리 기록 (승인·거절·숨김·다시 공개, 사유·메모 필수)
-- ---------------------------------------------------------------------
create table public.build_status_log (
  id          bigint generated always as identity primary key,
  build_id    bigint not null references public.builds (id) on delete cascade,
  action      text not null check (action in ('approve', 'reject', 'hide', 'restore')),
  reason      text not null check (btrim(reason) <> ''),
  actor       uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index build_status_log_build_idx on public.build_status_log (build_id, created_at desc);
revoke all on public.build_status_log from anon, authenticated;
grant select on public.build_status_log to authenticated;
alter table public.build_status_log enable row level security;
create policy "build_status_log: 운영자 읽기" on public.build_status_log
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 4. 투표 기록 (6단계 경험치 계산용) — 빌드·카운터와 연결하지 않아 지워져도 남는다
-- ---------------------------------------------------------------------
create table public.build_vote_log (
  id          bigint generated always as identity primary key,
  build_id    bigint not null,   -- 참조 아님
  counter_id  bigint not null,   -- 참조 아님
  author_id   uuid references public.profiles (id) on delete set null,  -- 표를 받은 빌드 작성자
  voter_id    uuid references public.profiles (id) on delete set null,
  old_value   smallint check (old_value in (1, -1)),  -- null = 표 없음
  new_value   smallint check (new_value in (1, -1)),  -- null = 취소
  created_at  timestamptz not null default now(),
  check (old_value is distinct from new_value)
);
create index build_vote_log_author_idx on public.build_vote_log (author_id, created_at);
create index build_vote_log_build_idx on public.build_vote_log (build_id, created_at);
comment on table public.build_vote_log is '따봉/비추가 바뀔 때마다 한 줄 (vote_build만 쓴다). 6단계: 따봉 받음 +2, 하루 상한, 부풀리기 판단';
revoke all on public.build_vote_log from anon, authenticated;
grant select on public.build_vote_log to authenticated;
alter table public.build_vote_log enable row level security;
create policy "build_vote_log: 운영자 읽기" on public.build_vote_log
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 5. 알림 종류 추가 + 빌드 연결
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add column build_id bigint references public.builds (id) on delete cascade,
  add constraint notifications_kind_check check (kind in (
    'revision_request', 'proposal_approved', 'proposal_rejected',
    'build_approved', 'build_rejected', 'build_hidden', 'build_restored'));

-- 알림 보내기 도우미 (받는 사람이 없거나 처리한 운영자 본인이면 보내지 않음)
create function public.notify(p_user uuid, p_kind text, p_message text, p_proposal bigint, p_build bigint)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if p_user is null or p_user = (select auth.uid()) then
    return;
  end if;
  insert into public.notifications (user_id, kind, message, proposal_id, build_id)
  values (p_user, p_kind, p_message, p_proposal, p_build);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 직접 쓰기 막기: 빌드 상태·따봉은 아래 함수로만 (운영자 포함)
-- ---------------------------------------------------------------------
revoke update, delete on public.builds from authenticated;
drop policy "builds: 관리자 처리" on public.builds;
drop policy "builds: 관리자 삭제" on public.builds;

revoke insert, update, delete on public.build_votes from authenticated;
drop policy "build_votes: 투표" on public.build_votes;
drop policy "build_votes: 표 바꾸기" on public.build_votes;
drop policy "build_votes: 표 취소" on public.build_votes;

-- ---------------------------------------------------------------------
-- 7. 운영자 전용: 빌드 승인·거절·숨기기·다시 공개 (메모 필수)
-- ---------------------------------------------------------------------
create function public.approve_build(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  b public.builds%rowtype;
  st text;
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
  -- (6단계) 빌드 승인 경험치(+30) 지급은 여기에 추가
end;
$$;

create function public.reject_build(p_id bigint, p_reason text)
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
  if b.status <> 'pending' then
    raise exception '이미 처리된 빌드예요.' using errcode = '23514';
  end if;
  update public.builds
     set status = 'rejected', reject_reason = reason, reviewed_by = (select auth.uid()), reviewed_at = now()
   where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'reject', reason, (select auth.uid()));
  perform public.notify(b.author_id, 'build_rejected', reason, null, b.id);
end;
$$;

create function public.hide_build(p_id bigint, p_reason text)
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
  update public.builds set status = 'hidden', hide_reason = reason, hidden_at = now() where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'hide', reason, (select auth.uid()));
  perform public.notify(b.author_id, 'build_hidden', reason, null, b.id);
  -- (6단계) 빌드 승인 경험치 회수는 여기에 추가 (SPEC 6-1 메모)
end;
$$;

create function public.restore_build(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  b public.builds%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '다시 공개 메모');
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if b.status <> 'hidden' then
    raise exception '숨긴 빌드가 아니에요.' using errcode = '23514';
  end if;
  update public.builds set status = 'approved', hide_reason = null, hidden_at = null where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor) values (b.id, 'restore', note, (select auth.uid()));
  perform public.notify(b.author_id, 'build_restored', note, null, b.id);
  -- (6단계) 빌드 승인 경험치 다시 지급은 여기에 추가 (한 번분만)
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 따봉/비추: p_value = 1(따봉) / -1(비추) / null(취소). 돌려주는 값: {up, down, mine}
-- ---------------------------------------------------------------------
create function public.vote_build(p_build_id bigint, p_value smallint)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  b public.builds%rowtype;
  cst text;
  old_v smallint;
begin
  if me is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  if not public.has_nickname() then
    raise exception '닉네임을 정한 뒤에 투표할 수 있어요.' using errcode = '42501';
  end if;
  if p_value is not null and p_value not in (1, -1) then
    raise exception '투표 값이 잘못됐어요.' using errcode = '23514';
  end if;
  select * into b from public.builds where id = p_build_id for update;
  select status into cst from public.counters where id = b.counter_id;
  if not found or b.status <> 'approved' or cst is distinct from 'approved' then
    raise exception '공개된 빌드에만 투표할 수 있어요.' using errcode = '23514';
  end if;
  if b.author_id = me then
    raise exception '내 빌드에는 투표할 수 없어요.' using errcode = '23514';
  end if;

  select value into old_v from public.build_votes where build_id = b.id and user_id = me;
  if p_value is null then
    delete from public.build_votes where build_id = b.id and user_id = me;
  elsif old_v is null then
    insert into public.build_votes (build_id, user_id, value) values (b.id, me, p_value);
  elsif old_v <> p_value then
    update public.build_votes set value = p_value where build_id = b.id and user_id = me;
  end if;

  if old_v is distinct from p_value then
    insert into public.build_vote_log (build_id, counter_id, author_id, voter_id, old_value, new_value)
    values (b.id, b.counter_id, b.author_id, me, old_v, p_value);
    -- (6단계) 따봉 받음 경험치(+2, 하루 상한)는 이 기록으로 계산
  end if;

  return (select jsonb_build_object('up', up_count, 'down', down_count, 'mine', p_value) from public.builds where id = b.id);
end;
$$;

-- ---------------------------------------------------------------------
-- 9. 카운터 제안 승인·거절도 알림 (approve_proposal은 007과 같고 알림만 추가, reject_proposal은 006과 같고 알림만 추가)
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
  perform public.notify(p.proposer_id, 'proposal_approved', note, p.id, null);
  -- (6단계) 경험치 지급은 여기에 추가
  return cid;
end;
$$;

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
  perform public.notify(p.proposer_id, 'proposal_rejected', reason, p.id, null);
end;
$$;

-- ---------------------------------------------------------------------
-- 10. 함수 실행 권한
-- ---------------------------------------------------------------------
revoke execute on function public.check_build_ids(text[], text, int, int, boolean) from public, anon, authenticated;
revoke execute on function public.clean_build_runes(jsonb) from public, anon, authenticated;
revoke execute on function public.build_signature(public.builds) from public, anon, authenticated;
revoke execute on function public.check_new_build() from public, anon, authenticated;
revoke execute on function public.delete_unpublished_builds() from public, anon, authenticated;
revoke execute on function public.notify(uuid, text, text, bigint, bigint) from public, anon, authenticated;
revoke execute on function public.approve_build(bigint, text) from public, anon;
revoke execute on function public.reject_build(bigint, text) from public, anon;
revoke execute on function public.hide_build(bigint, text) from public, anon;
revoke execute on function public.restore_build(bigint, text) from public, anon;
revoke execute on function public.vote_build(bigint, smallint) from public, anon;
grant execute on function public.approve_build(bigint, text) to authenticated;
grant execute on function public.reject_build(bigint, text) to authenticated;
grant execute on function public.hide_build(bigint, text) to authenticated;
grant execute on function public.restore_build(bigint, text) to authenticated;
grant execute on function public.vote_build(bigint, smallint) to authenticated;
revoke execute on function public.approve_proposal(bigint, text) from public, anon;
revoke execute on function public.reject_proposal(bigint, text) from public, anon;
grant execute on function public.approve_proposal(bigint, text) to authenticated;
grant execute on function public.reject_proposal(bigint, text) to authenticated;

commit;
