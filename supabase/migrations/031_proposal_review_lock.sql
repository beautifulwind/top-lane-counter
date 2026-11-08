-- =====================================================================
-- 031: 운영자·감독관이 같은 카운터 제안을 동시에 처리하는 일 줄이기 (SPEC 5장, 6-18)
--  1. 이미 다른 분이 처리한 제안을 승인·거절·재검토 요청·요청 취소하면 전용 오류(TL409)
--     "이미 다른 분이 처리했습니다." — 화면이 이 코드를 보고 안내 + 목록 새로고침
--  2. 제안 [자세히]를 열면 "검토 중" 표시(proposal_reviewing)를 남긴다. 막지 않고 경고만.
--     10분 뒤 저절로 사라지고, 제안이 처리되면(대기 상태를 벗어나면) 트리거가 지운다.
--     운영자·감독관만 함수로 읽고 쓴다 — 표는 아무도 직접 못 만진다.
-- 지금 배포된 화면과도 동작한다 (옛 화면은 새 문구를 오류 글자로 보여 줄 뿐). SQL을 먼저 실행하고 확인 뒤 새 코드 push.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. "이미 처리됨" 전용 오류 (SQLSTATE TL409)
-- ---------------------------------------------------------------------
-- 감독관은 처리된 제안을 열면 "처리할 수 없는 제안"이 먼저 나왔다 (승인 뒤에는 counter_id가 채워지므로).
-- 상태를 먼저 보고, 이미 처리됐으면 전용 오류를 낸다.
create or replace function public.require_review_allowed(p public.edit_proposals)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.is_moderator() then
    if p.status <> 'pending' then
      raise exception '이미 다른 분이 처리했습니다.' using errcode = 'TL409';
    end if;
    if p.type <> 'new_counter' or p.counter_id is not null or not public.moderatable_author(p.proposer_id) then
      raise exception '감독관이 처리할 수 없는 제안입니다. (본인·운영진의 제안, 문서 수정 제안, 숨긴 카운터의 제안은 운영자가 처리합니다)'
        using errcode = '42501';
    end if;
  end if;
end;
$$;

do $$
declare
  f record;
  old_def text;
  new_def text;
begin
  -- 승인·거절: 상태가 대기(거절은 재검토 중도)가 아니면
  for f in
    select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('approve_proposal_unchecked', 'reject_proposal_unchecked')
  loop
    old_def := pg_get_functiondef(f.oid);
    new_def := replace(old_def,
      $s$'이미 처리된 제안입니다.' using errcode = '23514'$s$,
      $s$'이미 다른 분이 처리했습니다.' using errcode = 'TL409'$s$);
    if new_def = old_def then
      raise exception '% 에서 바꿀 문구를 찾지 못했습니다.', f.proname;
    end if;
    execute new_def;
  end loop;

  -- 재검토 요청: 대기 중이 아니면 / 요청 취소: 재검토 중이 아니면
  for f in
    select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('request_proposal_revision_unchecked', 'cancel_proposal_revision')
  loop
    old_def := pg_get_functiondef(f.oid);
    new_def := regexp_replace(
      old_def,
      $re$(if p\.status <> '(?:pending|revision_requested)' then\s+raise exception ')[^']*(' using errcode = ')23514(')$re$,
      $re$\1이미 다른 분이 처리했습니다.\2TL409\3$re$);
    if new_def = old_def then
      raise exception '% 에서 바꿀 줄을 찾지 못했습니다.', f.proname;
    end if;
    execute new_def;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. "검토 중" 표시
-- ---------------------------------------------------------------------
create table public.proposal_reviewing (
  proposal_id bigint      not null references public.edit_proposals (id) on delete cascade,
  user_id     uuid        not null references public.profiles (id) on delete cascade,
  started_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  primary key (proposal_id, user_id)
);
create index proposal_reviewing_expires on public.proposal_reviewing (expires_at);
comment on table public.proposal_reviewing is
  '제안 [자세히]를 열고 있는 운영진 표시 (031). 10분 뒤 저절로 만료, 제안이 처리되면 트리거가 지움. 아무도 직접 못 읽고 못 씀 — 함수로만';

-- 일반 회원은 물론 운영진도 표를 직접 못 본다 (정책 없음 + 권한 회수)
revoke all on public.proposal_reviewing from public, anon, authenticated;
alter table public.proposal_reviewing enable row level security;

-- 제안이 대기 상태를 벗어나면(승인·거절·재검토 요청 …) 표시를 지운다. 처리 함수들은 건드리지 않는다.
create function public.clear_proposal_reviewing()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.proposal_reviewing where proposal_id = new.id;
  return null;
end;
$$;
create trigger edit_proposals_clear_reviewing
  after update of status on public.edit_proposals
  for each row when (old.status = 'pending' and new.status <> 'pending')
  execute function public.clear_proposal_reviewing();

-- 열었다: 내 표시를 10분짜리로 남기고, 지금 같이 보고 있는 다른 사람을 돌려준다
create function public.start_proposal_review(p_id bigint)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  p public.edit_proposals%rowtype;
  me uuid := (select auth.uid());
begin
  perform public.require_staff();
  select * into p from public.edit_proposals where id = p_id;
  -- 대기 중이 아니거나 내가 처리할 수 없는 제안이면 표시하지 않는다 (오류도 내지 않음)
  if not found or p.status <> 'pending' then
    return '[]'::jsonb;
  end if;
  if public.is_moderator() and (
    p.type <> 'new_counter' or p.counter_id is not null or not public.moderatable_author(p.proposer_id)
  ) then
    return '[]'::jsonb;
  end if;

  delete from public.proposal_reviewing where expires_at <= now();
  insert into public.proposal_reviewing (proposal_id, user_id, started_at, expires_at)
  values (p_id, me, now(), now() + interval '10 minutes')
  on conflict (proposal_id, user_id) do update
    set started_at = excluded.started_at, expires_at = excluded.expires_at;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'nickname', u.nickname, 'role', u.role, 'level', u.level, 'main_title', u.main_title,
             'started_at', r.started_at) order by r.started_at)
    from public.proposal_reviewing r join public.profiles u on u.id = r.user_id
    where r.proposal_id = p_id and r.user_id <> me and r.expires_at > now()
  ), '[]'::jsonb);
end;
$$;

-- 닫았다 / 처리했다: 내 표시를 지운다
create function public.end_proposal_review(p_id bigint)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_staff();
  delete from public.proposal_reviewing where proposal_id = p_id and user_id = (select auth.uid());
end;
$$;

-- 대기 목록용: 제안 번호 → 나 말고 지금 검토 중인 사람들 { "12": [{nickname, role, …}] }
create function public.proposal_reviewers(p_ids bigint[])
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_staff();
  return coalesce((
    select jsonb_object_agg(pid, people)
    from (
      select r.proposal_id::text as pid,
             jsonb_agg(jsonb_build_object(
               'nickname', u.nickname, 'role', u.role, 'level', u.level, 'main_title', u.main_title,
               'started_at', r.started_at) order by r.started_at) as people
      from public.proposal_reviewing r join public.profiles u on u.id = r.user_id
      where r.proposal_id = any (coalesce(p_ids, '{}')) and r.user_id <> (select auth.uid()) and r.expires_at > now()
      group by r.proposal_id
    ) s
  ), '{}'::jsonb);
end;
$$;

revoke execute on function public.clear_proposal_reviewing() from public, anon, authenticated;
revoke execute on function public.start_proposal_review(bigint) from public, anon;
revoke execute on function public.end_proposal_review(bigint) from public, anon;
revoke execute on function public.proposal_reviewers(bigint[]) from public, anon;
grant execute on function public.start_proposal_review(bigint) to authenticated;
grant execute on function public.end_proposal_review(bigint) to authenticated;
grant execute on function public.proposal_reviewers(bigint[]) to authenticated;
revoke execute on function public.require_review_allowed(public.edit_proposals) from public, anon, authenticated;

commit;
