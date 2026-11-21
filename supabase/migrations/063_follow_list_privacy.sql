-- =====================================================================
-- 063: 팔로우 목록 공개 범위 줄이기 (2026-11-21, SPEC 6-74) - 함수 4개 내용만 바꾸는 변경. 표·칸·권한(grant)은 그대로
--
-- 1. 팔로워 목록 influencer_followers(장인, 쪽)
--    - 볼 수 있는 사람: 그 장인 본인 + 운영자(운영자 모드가 켜진 운영자 - is_admin(), 기존 운영자 함수와 같은 기준). 그 밖은 거부(42501).
--      예전(050)에는 로그인한 모든 사람(게스트 포함)이 아무 장인의 팔로워 목록을 볼 수 있었다.
--    - 게스트(비회원, is_guest) 계정은 거부 - 비로그인은 원래대로 실행 권한이 없다.
--    - 차단(061): "장인 본인이 자기 목록을 볼 때"(p_user = auth.uid())만, 장인과 팔로워 사이에 차단이 있으면
--      목록·total·follower_count 모두에서 뺀다.
--      (팔로워가 장인을 차단 = blocker 팔로워·blocked 장인, 장인이 팔로워를 차단 = blocker 장인·blocked 팔로워, 둘 다)
--      운영자가 남의 목록을 볼 때는 차단과 상관없이 전부 보인다(운영진 관리 화면은 차단과 무관 - 061과 같은 원칙).
--      운영자 자신이 장인이라 자기 목록을 볼 때는 장인 본인 규칙(차단 관계 제외). 장인 페이지의 공개 팔로워 수
--      (influencer_builds·influencer_follower_count·search_influencers)는 그대로 전체 수다(차단 사실이 드러나지 않게).
--    - 응답에서 팔로우한 때(followed_at)를 뺀다: items = [{ id, nickname, influencer, nickname_state }].
--      순서(최근 팔로우 순)는 서버 안에서만 쓴다. follower_count는 옛 화면과 맞추려고 남기고 total과 같은 값.
-- 2. 내가 팔로우한 장인 my_following(쪽)
--    - 원래대로 "나" 것만(다른 사람 id를 받는 인자가 없다 - 운영자도 남의 팔로잉 목록을 보는 화면·함수가 없다). 게스트 계정은 거부.
--    - 응답에서 followed_at을 뺀다: items = [{ id, nickname, influencer, follower_count }]. 순서는 서버 안에서만.
-- 다른 사람의 팔로잉·팔로워를 보는 길은 이 둘뿐이다(표 influencer_follows는 RLS 켬·정책 없음·권한 회수 그대로).
-- 운영자 장인 목록(admin_influencer_list)·장인 검색·장인 페이지는 팔로워 "수"만 준다(사람·날짜 없음).
--
-- 새 표·새 칸·새 알림 종류·새 설정값·새 pg_cron 없음, Edge Function 재배포 없음.
-- 실행 전 supabase/scripts/check_follow_privacy_before.sql, 실행 뒤 check_follow_privacy_after.sql.
-- 062까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 실행 직후 새 화면을 배포(푸시)한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 062 상태(함수 내용은 050과 같음)로 돌아간다.
--    되돌릴 데이터 없음 (063은 데이터를 바꾸지 않는다). 권한(grant)은 063에서 바꾸지 않았으므로 그대로 둔다.
--     begin;
--     -- 팔로워 목록 (로그인한 사용자만 - 비로그인은 수만). 최근 팔로우 순, 20개씩. 닉네임을 아직 안 정한 사람은 nickname null
--     -- 돌려주는 값: { follower_count, total, page, size, items: [{ id, nickname, influencer, nickname_state, followed_at }] } - 역할/레벨 없음
--     create or replace function public.influencer_followers_unchecked(p_user uuid, p_page integer)
--     returns jsonb language plpgsql stable security definer set search_path = ''
--     as $$
--     declare
--       pg integer := greatest(coalesce(p_page, 1), 1);
--       sz constant integer := 20;
--       n bigint;
--     begin
--       if p_user is null or not exists (select 1 from public.profiles where id = p_user and influencer is not null) then
--         raise exception '인증된 장인을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       select count(*) into n from public.influencer_follows where influencer_id = p_user;
--       return jsonb_build_object(
--         'follower_count', n, 'total', n, 'page', pg, 'size', sz,
--         'items', coalesce((
--           select jsonb_agg(jsonb_build_object('id', u.id, 'nickname', u.nickname, 'influencer', u.influencer,
--                                               'nickname_state', u.nickname_state, 'followed_at', x.created_at)
--                            order by x.created_at desc, x.follower_id)
--             from (select f.follower_id, f.created_at from public.influencer_follows f
--                    where f.influencer_id = p_user
--                    order by f.created_at desc, f.follower_id
--                    limit sz offset (pg - 1) * sz) x
--             join public.profiles u on u.id = x.follower_id
--         ), '[]'::jsonb));
--     end;
--     $$;
--
--     create or replace function public.influencer_followers(p_user uuid, p_page integer default 1)
--     returns jsonb language plpgsql stable security definer set search_path = ''
--     as $$
--     begin
--       if (select auth.uid()) is null then
--         raise exception '로그인하면 팔로워 목록을 볼 수 있습니다.' using errcode = '42501';
--       end if;
--       return public.influencer_followers_unchecked(p_user, p_page);
--     end;
--     $$;
--
--     -- 내가 팔로우한 장인. 최근 팔로우 순, 20개씩
--     -- 돌려주는 값: { total, page, size, items: [{ id, nickname, influencer, followed_at, follower_count }] }
--     create or replace function public.my_following_unchecked(p_me uuid, p_page integer)
--     returns jsonb language plpgsql stable security definer set search_path = ''
--     as $$
--     declare
--       pg integer := greatest(coalesce(p_page, 1), 1);
--       sz constant integer := 20;
--     begin
--       return jsonb_build_object(
--         'total', (select count(*) from public.influencer_follows where follower_id = p_me),
--         'page', pg, 'size', sz,
--         'items', coalesce((
--           select jsonb_agg(jsonb_build_object('id', u.id, 'nickname', u.nickname, 'influencer', u.influencer, 'followed_at', x.created_at,
--                                               'follower_count', (select count(*) from public.influencer_follows g where g.influencer_id = u.id))
--                            order by x.created_at desc, x.influencer_id)
--             from (select f.influencer_id, f.created_at from public.influencer_follows f
--                    where f.follower_id = p_me
--                    order by f.created_at desc, f.influencer_id
--                    limit sz offset (pg - 1) * sz) x
--             join public.profiles u on u.id = x.influencer_id
--         ), '[]'::jsonb));
--     end;
--     $$;
--
--     create or replace function public.my_following(p_page integer default 1)
--     returns jsonb language plpgsql stable security definer set search_path = ''
--     as $$
--     declare
--       me uuid := (select auth.uid());
--     begin
--       if me is null then
--         raise exception '로그인해 주세요.' using errcode = '42501';
--       end if;
--       return public.my_following_unchecked(me, p_page);
--     end;
--     $$;
--     commit;
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 팔로워 목록 - 안쪽 함수 (장인 본인일 때 차단 거르기 + 날짜 빼기). 직접 부를 수 없다(050의 revoke 그대로)
--    바깥 함수가 본인 또는 운영자만 들여보낸다 -> 여기서 p_user = auth.uid()이면 장인 본인, 아니면 운영자
--    돌려주는 값: { follower_count, total, page, size, items: [{ id, nickname, influencer, nickname_state }] } - 역할/레벨/날짜 없음
--    최근 팔로우 순(서버 안에서만), 20개씩. 닉네임을 아직 안 정한 사람은 nickname null
-- ---------------------------------------------------------------------
create or replace function public.influencer_followers_unchecked(p_user uuid, p_page integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
  n bigint;
  own constant boolean := p_user = (select auth.uid());  -- 장인 본인이 자기 목록을 보는가 (아니면 운영자 - 전부 보임)
begin
  if p_user is null or not exists (select 1 from public.profiles where id = p_user and influencer is not null) then
    raise exception '인증된 장인을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  -- 063: 장인 본인이 볼 때만, 장인과 팔로워 사이에 차단(어느 쪽이든)이 있으면 목록과 수에서 뺀다
  select count(*) into n from public.influencer_follows f
   where f.influencer_id = p_user
     and (not own or not exists (select 1 from public.user_blocks b
                      where (b.blocker_id = f.follower_id and b.blocked_id = p_user)
                         or (b.blocker_id = p_user and b.blocked_id = f.follower_id)));
  return jsonb_build_object(
    'follower_count', n, 'total', n, 'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', u.id, 'nickname', u.nickname, 'influencer', u.influencer,
                                          'nickname_state', u.nickname_state)
                       order by x.created_at desc, x.follower_id)
        from (select f.follower_id, f.created_at from public.influencer_follows f
               where f.influencer_id = p_user
                 and (not own or not exists (select 1 from public.user_blocks b
                                  where (b.blocker_id = f.follower_id and b.blocked_id = p_user)
                                     or (b.blocker_id = p_user and b.blocked_id = f.follower_id)))
               order by f.created_at desc, f.follower_id
               limit sz offset (pg - 1) * sz) x
        join public.profiles u on u.id = x.follower_id
    ), '[]'::jsonb));
end;
$$;

-- 팔로워 목록 - 바깥 함수: 로그인 + 게스트 아님 + (장인 본인 또는 운영자)
create or replace function public.influencer_followers(p_user uuid, p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인하면 팔로워 목록을 볼 수 있습니다.' using errcode = '42501';
  end if;
  if public.is_guest(me) then
    raise exception '비회원은 팔로워 목록을 볼 수 없습니다. 마이페이지에서 구글·카카오를 연결해 주세요.' using errcode = '42501';
  end if;
  if p_user is distinct from me and not public.is_admin() then
    raise exception '팔로워 목록은 장인 본인만 볼 수 있습니다.' using errcode = '42501';
  end if;
  return public.influencer_followers_unchecked(p_user, p_page);
end;
$$;

-- ---------------------------------------------------------------------
-- 2. 내가 팔로우한 장인 - 안쪽 함수 (날짜 빼기). 최근 팔로우 순(서버 안에서만), 20개씩
--    돌려주는 값: { total, page, size, items: [{ id, nickname, influencer, follower_count }] }
-- ---------------------------------------------------------------------
create or replace function public.my_following_unchecked(p_me uuid, p_page integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
begin
  return jsonb_build_object(
    'total', (select count(*) from public.influencer_follows where follower_id = p_me),
    'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', u.id, 'nickname', u.nickname, 'influencer', u.influencer,
                                          'follower_count', (select count(*) from public.influencer_follows g where g.influencer_id = u.id))
                       order by x.created_at desc, x.influencer_id)
        from (select f.influencer_id, f.created_at from public.influencer_follows f
               where f.follower_id = p_me
               order by f.created_at desc, f.influencer_id
               limit sz offset (pg - 1) * sz) x
        join public.profiles u on u.id = x.influencer_id
    ), '[]'::jsonb));
end;
$$;

-- 내가 팔로우한 장인 - 바깥 함수: 로그인 + 게스트 아님 (언제나 "나" 것만)
create or replace function public.my_following(p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  if public.is_guest(me) then
    raise exception '비회원은 팔로우한 장인 목록을 볼 수 없습니다. 마이페이지에서 구글·카카오를 연결해 주세요.' using errcode = '42501';
  end if;
  return public.my_following_unchecked(me, p_page);
end;
$$;

-- 권한은 050 그대로 (create or replace는 권한을 바꾸지 않는다):
--   influencer_followers·my_following = authenticated만, 안쪽 함수 = 아무도 직접 못 부름

commit;
