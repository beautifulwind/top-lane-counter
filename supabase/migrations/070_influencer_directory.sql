-- =====================================================================
-- 070: 공개 장인 목록 조회 influencer_directory (2026-11-24, SPEC 6-92) - 새 함수 1개(읽기 전용). 표·칸·기존 함수·데이터는 바꾸지 않는다.
--
-- 1. influencer_directory(p_query, p_sort, p_page, p_size) - 로그인 없이도 부른다(anon·authenticated). 1.3 웹 /influencers(1-B1)가 쓴다.
--    - p_query: 비면 전체. 있으면 닉네임 부분 일치(대소문자 무시, %·_는 글자 그대로) - search_influencers와 같은 규칙
--      (소문자 비교 + 비슷한 글자 열쇠 nickname_key). 앞뒤 빈칸은 뺀다. 20자를 넘으면 거부(search_influencers와 같은 문장).
--    - p_sort: 'followers'(기본) | 'recent'. 그 밖의 값·null은 'followers'.
--    - p_page: 1부터(1 미만·null은 1). p_size: 기본 10, 1~50으로 맞춘다(50 넘으면 50, 1 미만이면 1).
--    - 돌려주는 값: { total, page, size, sort, items: [{ id, nickname, influencer, photo_path, follower_count, build_count, last_activity_at }] }
-- 2. 대상: profiles.influencer가 있고 닉네임이 있는 사람(search_influencers와 같음). 탈퇴하면 프로필이 지워지므로 저절로 빠진다.
-- 3. 개수: follower_count·build_count는 search_influencers와 같은 기준
--    (팔로워 = influencer_follows 줄 수, 빌드 = 처음 만든 공개 빌드(status 'approved')이고 그 상대법도 공개(approved)인 것).
--    팔로워 목록(누가 팔로우했는지)은 돌려주지 않는다.
--    last_activity_at = 그 공개 빌드 중 가장 최근 updated_at. 숨긴·대기·거절 빌드, 숨긴 상대법의 빌드는 개수·시각 모두에서 빠진다
--    (숨긴 빌드가 있다는 것이 드러나지 않게). 공개 빌드가 없으면 null.
-- 4. 정렬 (마지막에 id까지 넣어 같은 값이어도 쪽 사이에 겹침·빠짐이 없다):
--    'followers': follower_count 내림 → last_activity_at 내림(null은 맨 뒤) → nickname → id
--    'recent'   : last_activity_at 내림(null은 맨 뒤) → follower_count 내림 → nickname → id
-- 5. 보안: security definer + search_path '' (다른 공개 함수와 같음). 돌려주는 칸은 위 7개뿐(이메일·로그인 방식·역할·경험치 등 없음).
--    읽기 함수(stable)라 068 활동 제한 빠뜨림 방지 검사(volatile 쓰기 함수만 봄)의 대상이 아니다 → 허용 목록에 넣지 않는다.
-- 6. 옛 앱(1.1·1.2)이 쓰는 search_influencers 등 기존 함수는 이름·인자·반환형·동작을 바꾸지 않는다.
--
-- 실행 전 supabase/scripts/check_influencer_directory_before.sql, 실행 뒤 check_influencer_directory_after.sql
-- (함수 본문 지문은 줄바꿈 CR을 뺀 값으로 비교 - c5333b1과 같은 방식). 069까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- 웹(1-B1)은 운영 DB에서 확인한 뒤에 따로 배포한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 069 상태로 돌아간다(함수만 지움).
--     begin;
--     drop function if exists public.influencer_directory(text, text, integer, integer);
--     commit;
-- =====================================================================
begin;

create function public.influencer_directory(p_query text default null, p_sort text default 'followers', p_page integer default 1, p_size integer default 10)
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
comment on function public.influencer_directory(text, text, integer, integer) is
  '공개 장인 목록 (070): 검색(선택)·정렬 followers|recent·쪽(크기 1~50). 팔로워·빌드 수는 search_influencers와 같은 기준, 최근 활동 = 공개 빌드의 최근 updated_at';

revoke execute on function public.influencer_directory(text, text, integer, integer) from public;
grant execute on function public.influencer_directory(text, text, integer, integer) to anon, authenticated;

commit;
