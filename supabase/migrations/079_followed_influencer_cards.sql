-- =====================================================================
-- 079: 내가 팔로우한 장인 카드 읽기 함수 my_following_cards (2026-11-25, SPEC 6-115, 1.3 패치 2-G) - 새 읽기 함수 1개.
--
-- 무엇을: /lists·/following의 「팔로우한 장인」 카드에 사진·빌드 수를 보이려고, 기존 my_following(063)과 같은 순서·같은 쪽 크기로
--   장인 카드 칸을 돌려주는 새 읽기 함수를 더한다.
--   my_following은 칸이 { id, nickname, influencer, follower_count }뿐이라 사진(photo_path)·빌드 수가 없다.
--   기존 함수의 반환 형태를 바꾸지 않으려고(옛 앱 1.1·1.2가 my_following을 그대로 부른다) 고치지 않고 새 함수를 만든다.
--
-- 새 읽기 함수 my_following_cards(p_page integer default 1) returns jsonb (stable, security definer, search_path '',
--   authenticated만 실행 - anon·public 회수, my_following과 같은 권한).
--   부른 사람: 로그인(auth.uid) + 비회원(게스트) 아님 - my_following과 같은 문장으로 거부. 다른 사람 id를 받는 인자가 없다(언제나 "나" 것만).
--   돌려주는 값: { total, page, size(20), items: [{ id, nickname, influencer, photo_path, follower_count, build_count }] }
--     - 순서·쪽: my_following과 같다 - 최근에 팔로우한 순(팔로우한 때 내림, 같으면 장인 id), 20개씩. 팔로우한 때는 돌려주지 않는다(063).
--     - 칸: 장인 목록(influencer_directory)·장인 페이지에 이미 공개된 것만. follower_count = 그 장인의 전체 팔로워 수,
--       build_count = 공개 빌드 수(승인 빌드 + 승인 상대법 - influencer_directory·public_profile과 같은 식).
--     - 이메일·가입일시·역할·레벨·경험치·운영 정보·제한·경고·닉네임 상태·팔로우한 때는 돌려주지 않는다.
--   빼는 장인 (목록과 total 모두에서): 장인 인증이 없음(해제되면 050 트리거가 팔로우를 지우지만 한 번 더 막음) / 닉네임 없음 /
--     지금 활동 제한(정지) 중(active_restriction_id - 풀리면 팔로우가 남아 있으므로 다시 나온다). 탈퇴하면 팔로우 줄이 cascade로 지워진다.
--     my_following은 정지 중인 장인도 그대로 보인다(고치지 않음).
--
-- 바꾸지 않는 것: 기존 함수(my_following·my_following_unchecked 포함)·표·트리거·정책·권한·데이터 전부.
--   새 함수는 stable이라 068 쓰기 함수 검사 대상이 아니다 → 쓰기 함수 103 / 첫 줄 검사 30 / 허용 목록 73 그대로, 읽기 함수 66 → 67.
-- 옛 앱 1.1·1.2: 이 함수를 부르지 않으므로 달라지는 것 없음. 새 웹은 이 함수가 없으면(079 전 DB) my_following으로 되돌아간다.
--
-- 실행 전 supabase/scripts/check_followed_cards_before.sql, 실행 뒤 check_followed_cards_after.sql.
-- 078까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
--
-- >> 되돌리기 (rollback) - SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 078 상태로 돌아간다.
--    (079는 기존 함수를 고치지 않았으므로 "변경 전 본문"이 없다 - 새로 만든 함수 1개만 지운다. 데이터는 바꾸지 않았다.)
--    되돌린 뒤 check_followed_cards_before.sql 1번이 「없음」이면 정상. 새 웹은 my_following으로 되돌아가 사진만 첫 글자 원으로 보인다.
--     begin;
--     drop function public.my_following_cards(integer);
--     commit;
-- =====================================================================
begin;

do $chk$
begin
  if to_regprocedure('public.my_following_cards(integer)') is not null then
    raise exception 'my_following_cards가 이미 있습니다(079를 이미 실행함). 실행을 멈춥니다.';
  end if;
  if to_regprocedure('public.my_following(integer)') is null or to_regprocedure('public.active_restriction_id(uuid)') is null then
    raise exception '063·068이 아직 실행되지 않았습니다.';
  end if;
end $chk$;

create function public.my_following_cards(p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  if public.is_guest(me) then
    raise exception '비회원은 팔로우한 장인 목록을 볼 수 없습니다. 마이페이지에서 구글·카카오를 연결해 주세요.' using errcode = '42501';
  end if;
  return (
    with f as (
      select x.influencer_id, x.created_at, p.nickname, p.influencer, p.photo_path
        from public.influencer_follows x
        join public.profiles p on p.id = x.influencer_id
       where x.follower_id = me
         and p.influencer is not null and p.nickname is not null
         and public.active_restriction_id(p.id) is null
    ), pagef as (
      select * from f order by f.created_at desc, f.influencer_id limit sz offset (pg - 1) * sz
    )
    select jsonb_build_object(
      'total', (select count(*) from f),
      'page', pg, 'size', sz,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', g.influencer_id, 'nickname', g.nickname, 'influencer', g.influencer, 'photo_path', g.photo_path,
                 'follower_count', (select count(*) from public.influencer_follows h where h.influencer_id = g.influencer_id),
                 'build_count', (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                                  where b.author_id = g.influencer_id and b.status = 'approved' and c.status = 'approved'))
               order by g.created_at desc, g.influencer_id)
          from pagef g
      ), '[]'::jsonb))
  );
end;
$$;
comment on function public.my_following_cards(integer) is
  '내가 팔로우한 장인 카드 (079): my_following과 같은 순서·쪽(20). 사진·장인 유형·팔로워 수·공개 빌드 수. 인증 없음·닉네임 없음·정지 중인 장인 제외. 로그인·비회원 아님';
revoke execute on function public.my_following_cards(integer) from public, anon;
grant execute on function public.my_following_cards(integer) to authenticated;

commit;
