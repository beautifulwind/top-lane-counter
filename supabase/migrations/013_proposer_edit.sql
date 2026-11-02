-- =====================================================================
-- 제안자가 승인 대기 중인 제안·빌드를 직접 고친다 + "제안자가 방금 고쳤어요" 막기
-- - edit_my_proposal / edit_my_build: 본인 것, 승인 대기(pending)일 때만. 검사는 처음 낼 때와 같다.
--   고친 빌드는 화면이 보낸 지금 패치. 승인 대기 순서(created_at)는 그대로, 고친 때는 edited_at.
-- - version: 고칠 때(다시 제출 포함)마다 +1. 운영자의 승인·재검토 요청·거절은 화면이 본 version을 같이 보내고,
--   다르면 "제안자가 방금 고쳤어요. 다시 확인해 주세요."로 거부한다 (옛 내용을 보고 결정하지 않게).
--   [요청 취소]는 재검토 중(제안자가 못 고침)에만 하므로 검사하지 않는다.
-- - 012의 처리 함수는 이름만 바꿔(…_unchecked) 그대로 쓰고, 같은 이름의 새 함수가 버전을 확인한 뒤 부른다.
--   처리 내용을 바꿀 때는 …_unchecked 함수를 고친다.
-- 012_approve_edit_revision.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 버전·고친 때
-- ---------------------------------------------------------------------
alter table public.edit_proposals
  add column version   integer not null default 1,
  add column edited_at timestamptz;
comment on column public.edit_proposals.version is '제안자가 고칠 때(다시 제출 포함)마다 +1. 운영자 처리 함수가 화면이 본 값과 비교';
comment on column public.edit_proposals.edited_at is '제안자가 승인 대기 중에 마지막으로 고친 때 (승인 대기 순서는 created_at 그대로)';

alter table public.builds
  add column version   integer not null default 1,
  add column edited_at timestamptz;
comment on column public.builds.version is '작성자가 고칠 때(다시 제출 포함)마다 +1. 운영자 처리 함수가 화면이 본 값과 비교';
comment on column public.builds.edited_at is '작성자가 승인 대기 중에 마지막으로 고친 때';

-- ---------------------------------------------------------------------
-- 2. 버전 확인 도우미
-- ---------------------------------------------------------------------
create function public.require_proposal_version(p_id bigint, p_version integer)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v integer;
begin
  select version into v from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p_version is null or v <> p_version then
    raise exception '제안자가 방금 고쳤어요. 다시 확인해 주세요.' using errcode = '40001';
  end if;
end;
$$;

create function public.require_build_version(p_id bigint, p_version integer)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v integer;
begin
  select version into v from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p_version is null or v <> p_version then
    raise exception '작성자가 방금 고쳤어요. 다시 확인해 주세요.' using errcode = '40001';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 012의 처리 함수 → …_unchecked (안쪽 함수, 직접 부를 수 없음) + 버전을 받는 새 함수
-- ---------------------------------------------------------------------
alter function public.approve_proposal(bigint, text, jsonb, jsonb) rename to approve_proposal_unchecked;
alter function public.reject_proposal(bigint, text) rename to reject_proposal_unchecked;
alter function public.request_proposal_revision(bigint, text) rename to request_proposal_revision_unchecked;
alter function public.approve_build(bigint, text, jsonb) rename to approve_build_unchecked;
alter function public.reject_build(bigint, text) rename to reject_build_unchecked;
alter function public.request_build_revision(bigint, text) rename to request_build_revision_unchecked;
revoke execute on function public.approve_proposal_unchecked(bigint, text, jsonb, jsonb) from public, anon, authenticated;
revoke execute on function public.reject_proposal_unchecked(bigint, text) from public, anon, authenticated;
revoke execute on function public.request_proposal_revision_unchecked(bigint, text) from public, anon, authenticated;
revoke execute on function public.approve_build_unchecked(bigint, text, jsonb) from public, anon, authenticated;
revoke execute on function public.reject_build_unchecked(bigint, text) from public, anon, authenticated;
revoke execute on function public.request_build_revision_unchecked(bigint, text) from public, anon, authenticated;

create function public.approve_proposal(p_id bigint, p_note text, p_content jsonb, p_build jsonb, p_version integer)
returns bigint language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.require_proposal_version(p_id, p_version);
  return public.approve_proposal_unchecked(p_id, p_note, p_content, p_build);
end;
$$;

create function public.reject_proposal(p_id bigint, p_reason text, p_version integer)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.require_proposal_version(p_id, p_version);
  perform public.reject_proposal_unchecked(p_id, p_reason);
end;
$$;

create function public.request_proposal_revision(p_id bigint, p_note text, p_version integer)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.require_proposal_version(p_id, p_version);
  perform public.request_proposal_revision_unchecked(p_id, p_note);
end;
$$;

create function public.approve_build(p_id bigint, p_note text, p_build jsonb, p_version integer)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.require_build_version(p_id, p_version);
  perform public.approve_build_unchecked(p_id, p_note, p_build);
end;
$$;

create function public.reject_build(p_id bigint, p_reason text, p_version integer)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.require_build_version(p_id, p_version);
  perform public.reject_build_unchecked(p_id, p_reason);
end;
$$;

create function public.request_build_revision(p_id bigint, p_note text, p_version integer)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.require_build_version(p_id, p_version);
  perform public.request_build_revision_unchecked(p_id, p_note);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 제안자가 승인 대기 중인 제안을 고친다
-- ---------------------------------------------------------------------
create function public.edit_my_proposal(p_id bigint, p_content jsonb, p_build jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
  new_content jsonb;
  new_build jsonb;
  st text;
begin
  select * into p from public.edit_proposals where id = p_id for update;
  if not found or p.proposer_id is distinct from (select auth.uid()) then
    raise exception '제안을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.status = 'revision_requested' then
    raise exception '재검토 요청을 받은 제안은 [고쳐서 다시 제출]로 고쳐 주세요.' using errcode = '23514';
  end if;
  if p.status <> 'pending' then
    raise exception '승인 대기 중인 제안만 고칠 수 있어요.' using errcode = '23514';
  end if;
  new_content := public.clean_doc_content(p_content);

  if p.type = 'new_counter' then
    if p_build is null then
      raise exception '빌드도 함께 채워 주세요. 새 카운터 제안에는 빌드가 꼭 있어야 해요.' using errcode = '23514';
    end if;
    new_build := public.clean_build(p_build);
    if public.is_hidden_counter_flow(p) then
      select status into st from public.counters where id = p.counter_id;
      if st is distinct from 'hidden' then
        raise exception '이 카운터는 지금 고칠 수 없어요.' using errcode = '23514';
      end if;
    else
      select status into st from public.counters
       where target_champion = p.target_champion and counter_champion = p.counter_champion and status in ('approved', 'hidden');
      if st = 'approved' then
        raise exception '그 사이 같은 카운터가 등록됐어요. 문서 수정 제안을 이용해 주세요.' using errcode = '23514';
      end if;
      if st = 'hidden' then
        raise exception '운영자가 숨긴 카운터라 지금은 고칠 수 없어요.' using errcode = '23514';
      end if;
    end if;
  else  -- doc_edit
    if p_build is not null then
      raise exception '문서 수정 제안에는 빌드를 넣지 않아요.' using errcode = '23514';
    end if;
    select status into st from public.counters where id = p.counter_id;
    if st = 'approved' and new_content = (
      select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
      from public.matchup_docs d where d.counter_id = p.counter_id
    ) then
      raise exception '지금 문서와 달라진 내용이 없어요.' using errcode = '23514';
    end if;
  end if;

  if new_content = public.clean_doc_content(p.content)
     and (p.type = 'doc_edit' or (p.build is not null and new_build - 'patch' = p.build - 'patch')) then
    raise exception '고친 내용이 없어요.' using errcode = '23514';
  end if;

  update public.edit_proposals
     set content = new_content, build = coalesce(new_build, build), version = version + 1, edited_at = now()
   where id = p.id;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 작성자가 승인 대기 중인 빌드를 고친다 (지금 패치로)
-- ---------------------------------------------------------------------
create function public.edit_my_build(p_id bigint, p_build jsonb)
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
  if b.status = 'revision_requested' then
    raise exception '재검토 요청을 받은 빌드는 [고쳐서 다시 제출]로 고쳐 주세요.' using errcode = '23514';
  end if;
  if b.status <> 'pending' then
    raise exception '승인 대기 중인 빌드만 고칠 수 있어요.' using errcode = '23514';
  end if;
  if (select status from public.counters where id = b.counter_id) is distinct from 'approved' then
    raise exception '이 매치업은 지금 고칠 수 없어요.' using errcode = '23514';
  end if;
  nb := public.clean_build(p_build);
  if nb - 'patch' = public.build_signature(b) then
    raise exception '고친 내용이 없어요.' using errcode = '23514';
  end if;
  if exists (
    select 1 from public.builds x
    where x.counter_id = b.counter_id and x.status = 'approved' and public.build_signature(x) = nb - 'patch'
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있어요. 따봉으로 응원해 주세요.' using errcode = '23514';
  end if;

  perform public.set_build_fields(b.id, nb);
  update public.builds set version = version + 1, edited_at = now() where id = b.id;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 다시 제출도 버전을 올린다 (012의 resubmit_* 함수는 그대로 두고, 상태가 바뀌는 때를 트리거로 잡는다)
--    revision_requested → pending (다시 제출)일 때 +1
-- ---------------------------------------------------------------------
create function public.bump_version_on_resubmit()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if old.status = 'revision_requested' and new.status = 'pending' and new.resubmitted_at is distinct from old.resubmitted_at then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;
create trigger edit_proposals_bump_version before update on public.edit_proposals
  for each row execute function public.bump_version_on_resubmit();
create trigger builds_bump_version before update on public.builds
  for each row execute function public.bump_version_on_resubmit();

-- ---------------------------------------------------------------------
-- 7. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.require_proposal_version(bigint, integer) from public, anon, authenticated;
revoke execute on function public.require_build_version(bigint, integer) from public, anon, authenticated;
revoke execute on function public.bump_version_on_resubmit() from public, anon, authenticated;

revoke execute on function public.approve_proposal(bigint, text, jsonb, jsonb, integer) from public, anon;
grant execute on function public.approve_proposal(bigint, text, jsonb, jsonb, integer) to authenticated;
revoke execute on function public.reject_proposal(bigint, text, integer) from public, anon;
grant execute on function public.reject_proposal(bigint, text, integer) to authenticated;
revoke execute on function public.request_proposal_revision(bigint, text, integer) from public, anon;
grant execute on function public.request_proposal_revision(bigint, text, integer) to authenticated;
revoke execute on function public.approve_build(bigint, text, jsonb, integer) from public, anon;
grant execute on function public.approve_build(bigint, text, jsonb, integer) to authenticated;
revoke execute on function public.reject_build(bigint, text, integer) from public, anon;
grant execute on function public.reject_build(bigint, text, integer) to authenticated;
revoke execute on function public.request_build_revision(bigint, text, integer) from public, anon;
grant execute on function public.request_build_revision(bigint, text, integer) to authenticated;
revoke execute on function public.edit_my_proposal(bigint, jsonb, jsonb) from public, anon;
grant execute on function public.edit_my_proposal(bigint, jsonb, jsonb) to authenticated;
revoke execute on function public.edit_my_build(bigint, jsonb) from public, anon;
grant execute on function public.edit_my_build(bigint, jsonb) to authenticated;

commit;
