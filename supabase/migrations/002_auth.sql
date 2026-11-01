-- =====================================================================
-- 3단계: 로그인 — 프로필 자동 생성, 닉네임 설정, 관리자 권한 구조
-- supabase/schema.sql(2단계)을 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 닉네임: 첫 로그인 직후에는 아직 없다 (null = 닉네임 설정 전)
--    중복 금지(대소문자 무시)·1~20자 규칙은 그대로. null은 서로 겹쳐도 됨.
-- ---------------------------------------------------------------------
alter table public.profiles alter column nickname drop not null;

-- 한 번 정한 닉네임을 다시 비울 수는 없다
create function public.keep_nickname()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if old.nickname is not null and new.nickname is null then
    raise exception '닉네임은 비울 수 없어요.' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger profiles_keep_nickname before update on public.profiles
  for each row execute function public.keep_nickname();

-- ---------------------------------------------------------------------
-- 2. profiles 자동 생성: auth.users에 유저가 생기면(첫 로그인) 프로필 행을 만든다
-- ---------------------------------------------------------------------
create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 이미 로그인해 본 유저가 있으면 프로필을 채워 준다
insert into public.profiles (id) select id from auth.users on conflict (id) do nothing;

-- 이제 프로필은 트리거만 만든다 → 클라이언트의 직접 생성 권한을 닫는다
drop policy "profiles: 본인 생성" on public.profiles;
revoke insert on public.profiles from authenticated;

-- ---------------------------------------------------------------------
-- 3. 닉네임을 정한 유저만 제안·빌드·투표·글쓰기 가능
-- ---------------------------------------------------------------------
create function public.has_nickname()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles where id = (select auth.uid()) and nickname is not null
  );
$$;

alter policy "edit_proposals: 본인 이름으로 대기 제안 작성" on public.edit_proposals
  with check (
    proposer_id = (select auth.uid()) and public.has_nickname() and status = 'pending'
    and reviewed_by is null and reviewed_at is null and reject_reason is null
  );
alter policy "builds: 본인 이름으로 대기 빌드 등록" on public.builds
  with check (
    author_id = (select auth.uid()) and public.has_nickname() and status = 'pending'
    and reviewed_by is null and reviewed_at is null and reject_reason is null
    and up_count = 0 and down_count = 0
  );
alter policy "build_votes: 투표" on public.build_votes
  with check (
    user_id = (select auth.uid()) and public.has_nickname()
    and exists (
      select 1 from public.builds b
      where b.id = build_id and b.status = 'approved'
        and b.author_id is distinct from (select auth.uid())
    )
  );
alter policy "posts: 본인 작성" on public.posts
  with check (author_id = (select auth.uid()) and public.has_nickname());
alter policy "post_comments: 본인 작성" on public.post_comments
  with check (author_id = (select auth.uid()) and public.has_nickname());

-- ---------------------------------------------------------------------
-- 4. 관리자 지정/해제 — 관리자만 호출 가능, 마지막 관리자는 해제 불가
--    (클라이언트는 profiles.role을 직접 못 바꾼다: 2단계의 칸 단위 권한)
--    호출: supabase.rpc('set_user_role', { target: '<유저 id>', new_role: 'admin' | 'user' })
-- ---------------------------------------------------------------------
create function public.set_user_role(target uuid, new_role text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception '관리자만 할 수 있어요.' using errcode = '42501';
  end if;
  if new_role not in ('user', 'admin') then
    raise exception '알 수 없는 권한이에요: %', new_role using errcode = '22023';
  end if;

  -- 관리자 행들을 잠가서, 두 관리자가 동시에 서로를 해제해 0명이 되는 일을 막는다
  perform 1 from public.profiles where role = 'admin' for update;
  if new_role = 'user'
     and not exists (select 1 from public.profiles where role = 'admin' and id <> target) then
    raise exception '마지막 관리자는 해제할 수 없어요.' using errcode = '23514';
  end if;

  update public.profiles set role = new_role where id = target;
  if not found then
    raise exception '해당 유저가 없어요.' using errcode = 'P0002';
  end if;
end;
$$;

-- 함수 실행 권한 정리 (Supabase는 기본으로 anon에게도 실행 권한을 준다)
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.keep_nickname() from public, anon, authenticated;
revoke execute on function public.set_user_role(uuid, text) from public, anon;
grant execute on function public.set_user_role(uuid, text) to authenticated;

commit;
