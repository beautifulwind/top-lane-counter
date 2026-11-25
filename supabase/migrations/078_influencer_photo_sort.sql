-- =====================================================================
-- 078: 장인 목록 정렬에 프로필 사진 유무 반영 (2026-11-25, SPEC 6-113, 1.3 패치 2-0b)
--
-- 바꾸는 것: influencer_directory(text, text, integer, integer) 본문의 정렬(row_number의 order by) 맨 앞에 한 줄을 더한다.
--   「사진 있는 장인 먼저」 = photo_path가 null이 아니고 공백뿐이 아님(웹 lib/influencerOrder.js hasPhoto와 같은 판정).
--   그 뒤는 070 그대로 - 'followers': 팔로워 내림 → 최근 활동 내림(null 맨 뒤) → 팔로워 → 닉네임 → id
--                      'recent'   : 최근 활동 내림(null 맨 뒤) → 팔로워 내림 → 닉네임 → id
--   (사진 먼저는 두 정렬 모두에 적용 - 웹이 지금 두 정렬 모두 사진 없는 장인을 뒤로 보내므로 같은 결과)
--   마지막이 id(유일)라 순서가 하나로 정해지고, 쪽은 이 순서의 번호(rn)로 자르므로 같은 데이터에서 쪽 사이 겹침·빠짐이 없다.
-- 그대로인 것: 이름·인자·기본값·반환(jsonb)·돌려주는 칸 7개·total·검색·쪽 크기 보정·stable·security definer·search_path·권한·소유자·설명,
--   다른 모든 함수, 표·데이터. 쓰기 함수 103/30/73, 읽기 함수 66.
-- 왜 본문을 고치나: 웹이 사진 없는 장인을 뒤로 보내는 일을 받은 목록(최대 50명) 안에서만 해서, 장인이 50명을 넘어 서버 쪽 나누기로 바뀌면
--   사진 순서가 쪽마다 따로 놀게 된다. DB가 정렬해야 모든 쪽이 한 순서가 된다.
-- 옛 앱 1.1·1.2: 이 함수를 부르지 않는다(1.3 웹 /influencers·메인 장인 줄만). 칸·모양이 같아 부르더라도 순서만 다르다.
-- 「사진 있음」 판정: profiles.photo_path(062). null = 사진 없음, 빈 문자열은 제약 profiles_photo_path_shape(경로가 'id/'로 시작) 때문에 들어올 수 없다.
--   사진 삭제(본인·운영자)는 같은 트랜잭션에서 photo_path를 null로 바꾼다. 저장소 파일이 따로 사라진 경우(직접 지움 등)는 DB가 알 수 없어
--   「있음」으로 정렬된다(화면은 그림을 못 불러오면 첫 글자 원으로 보여 준다).
--
-- 실행 전 supabase/scripts/check_influencer_photo_sort_before.sql, 실행 뒤 check_influencer_photo_sort_after.sql.
-- 077까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
--
-- >> 되돌리기 (rollback) - SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 070 본문(지문 7955c630a2b304baf7628375ca3f3940)으로 돌아간다.
--     begin;
--     create or replace function public.influencer_directory(p_query text default null, p_sort text default 'followers', p_page integer default 1, p_size integer default 10)
--     returns jsonb language plpgsql stable security definer set search_path = ''
--     as $$
--     declare
--       q text := btrim(coalesce(p_query, ''));
--       srt text := case when p_sort = 'recent' then 'recent' else 'followers' end;
--       pg integer := greatest(coalesce(p_page, 1), 1);
--       sz integer := least(greatest(coalesce(p_size, 10), 1), 50);
--       pat text;
--       k text;
--       kpat text;
--     begin
--       if char_length(q) > 20 then
--         raise exception '검색어는 20자 이하로 적어 주세요.' using errcode = '22023';
--       end if;
--       if q <> '' then
--         pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
--         k := public.nickname_key(q);
--         if coalesce(k, '') <> '' then
--           kpat := '%' || replace(replace(replace(k, '\', '\\'), '%', '\%'), '_', '\_') || '%';
--         end if;
--       end if;
--       return (
--         with m as (
--           select p.id, p.nickname, p.influencer, p.photo_path,
--                  (select count(*) from public.influencer_follows f where f.influencer_id = p.id) as followers,
--                  b.n as builds, b.last_at
--             from public.profiles p
--             cross join lateral (
--               select count(*) as n, max(x.updated_at) as last_at
--                 from public.builds x join public.counters c on c.id = x.counter_id
--                where x.author_id = p.id and x.status = 'approved' and c.status = 'approved'
--             ) b
--            where p.influencer is not null and p.nickname is not null
--              and (q = '' or lower(p.nickname) like pat escape '\' or (kpat is not null and p.nickname_key like kpat escape '\'))
--         ), o as (
--           select m.*, row_number() over (order by
--                    case when srt = 'followers' then m.followers end desc nulls last,
--                    m.last_at desc nulls last,
--                    m.followers desc,
--                    m.nickname, m.id) as rn
--             from m
--         )
--         select jsonb_build_object(
--           'total', (select count(*) from m),
--           'page', pg, 'size', sz, 'sort', srt,
--           'items', coalesce((
--             select jsonb_agg(jsonb_build_object(
--                      'id', o.id, 'nickname', o.nickname, 'influencer', o.influencer, 'photo_path', o.photo_path,
--                      'follower_count', o.followers, 'build_count', o.builds, 'last_activity_at', o.last_at)
--                    order by o.rn)
--               from o where o.rn > (pg - 1) * sz and o.rn <= pg * sz
--           ), '[]'::jsonb))
--       );
--     end;
--     $$;
--     commit;
-- =====================================================================
begin;

do $chk$
begin
  if to_regprocedure('public.influencer_directory(text, text, integer, integer)') is null then
    raise exception '070이 아직 실행되지 않았습니다.';
  end if;
  if md5(replace((select prosrc from pg_proc where oid = 'public.influencer_directory(text, text, integer, integer)'::regprocedure), E'\r', ''))
     <> '7955c630a2b304baf7628375ca3f3940' then
    raise exception 'influencer_directory 본문이 070과 다릅니다(이미 078을 실행했거나 다른 변경이 있음). 실행을 멈춥니다. check_influencer_photo_sort_before.sql 1번을 알려 주세요.';
  end if;
end $chk$;

create or replace function public.influencer_directory(p_query text default null, p_sort text default 'followers', p_page integer default 1, p_size integer default 10)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  q text := btrim(coalesce(p_query, ''));
  srt text := case when p_sort = 'recent' then 'recent' else 'followers' end;
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 10), 1), 50);
  pat text;
  k text;
  kpat text;
begin
  if char_length(q) > 20 then
    raise exception '검색어는 20자 이하로 적어 주세요.' using errcode = '22023';
  end if;
  if q <> '' then
    pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
    k := public.nickname_key(q);
    if coalesce(k, '') <> '' then
      kpat := '%' || replace(replace(replace(k, '\', '\\'), '%', '\%'), '_', '\_') || '%';
    end if;
  end if;
  return (
    with m as (
      select p.id, p.nickname, p.influencer, p.photo_path,
             (select count(*) from public.influencer_follows f where f.influencer_id = p.id) as followers,
             b.n as builds, b.last_at
        from public.profiles p
        cross join lateral (
          select count(*) as n, max(x.updated_at) as last_at
            from public.builds x join public.counters c on c.id = x.counter_id
           where x.author_id = p.id and x.status = 'approved' and c.status = 'approved'
        ) b
       where p.influencer is not null and p.nickname is not null
         and (q = '' or lower(p.nickname) like pat escape '\' or (kpat is not null and p.nickname_key like kpat escape '\'))
    ), o as (
      select m.*, row_number() over (order by
               (m.photo_path is not null and btrim(m.photo_path) <> '') desc,  -- 078: 프로필 사진 있는 장인 먼저
               case when srt = 'followers' then m.followers end desc nulls last,
               m.last_at desc nulls last,
               m.followers desc,
               m.nickname, m.id) as rn
        from m
    )
    select jsonb_build_object(
      'total', (select count(*) from m),
      'page', pg, 'size', sz, 'sort', srt,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', o.id, 'nickname', o.nickname, 'influencer', o.influencer, 'photo_path', o.photo_path,
                 'follower_count', o.followers, 'build_count', o.builds, 'last_activity_at', o.last_at)
               order by o.rn)
          from o where o.rn > (pg - 1) * sz and o.rn <= pg * sz
      ), '[]'::jsonb))
  );
end;
$$;
-- create or replace는 권한·설명·소유자를 그대로 둔다 (확인 스크립트 6번)

commit;
