-- =====================================================================
-- 075: 일반 사용자 개인 페이지 읽기 함수 member_page (2026-11-25, SPEC 6-108, 1.3 패치 2-B) - 설정값 1줄 + 새 읽기 함수 1개.
--
-- 무엇을: 장인이 아닌 일반 사용자의 "공개 빌드"가 5개(xp_rules.member_page_min_builds) 이상이면 개인 페이지를 연다.
--   공개 빌드 = builds.status = 'approved' and 그 상대법 counters.status = 'approved'
--   (= builds 읽기 정책의 "누구나 보는 빌드", public_profile·influencer_builds·influencer_directory의 빌드 수와 같은 기준.
--    숨김(hidden)·대기(pending)·거절·재검토 요청 빌드, 숨기거나 대기 중인 상대법의 빌드는 세지 않는다)
--   개수는 security definer 안에서 표를 직접 세므로 로그인 여부·부른 사람과 관계없이 같다.
--
-- 새 읽기 함수 member_page(p_user text, p_page integer default 1) returns jsonb (stable, security definer, search_path '',
--   anon·authenticated 실행, public 회수). influencer_builds(장인 페이지)와 같은 인자 모양·같은 쪽 크기 20·같은 빌드 카드(follow_build_card).
--   돌려주는 값: { member: { id, nickname, photo_path, main_title, titles: [칭호 키...] }, total, page, size, items: [빌드 카드...] }
--     - titles: 그 사람이 가진 칭호 중 도감에서 숨김이 아닌 것(비밀 칭호는 대표 칭호로 단 것만). 이름·그림은 화면이 public_title_info로.
--     - photo_path: 지금은 장인만 사진을 올릴 수 있어(profiles_photo_influencer 제약) 일반 사용자는 항상 null.
--   null(장인 프로필과 같은 방식 - "없는 페이지"와 구별 불가): 모양이 틀린 id / 없는 사람(탈퇴하면 profiles 줄이 지워짐) /
--     닉네임 없음 / 비회원(is_guest) / 운영자(role admin) / 장인(장인 페이지 public_profile이 따로 있음) /
--     지금 활동 제한(정지) 중(active_restriction_id) / 공개 빌드 5개 미만.
--   이메일·가입일시·역할·레벨·경험치·운영 정보·제한·경고·닉네임 상태·인증 배지·유튜브·링크·팔로우는 돌려주지 않는다.
--
-- 바꾸지 않는 것: 기존 함수(public_profile·influencer_builds·follow_build_card 포함)·표·트리거·정책·권한·데이터 전부.
--   새 함수는 stable이라 068 쓰기 함수 검사 대상이 아니다 → 쓰기 함수 103 / 첫 줄 검사 30 / 허용 목록 73 그대로, 읽기 함수 65 → 66.
-- 옛 앱 1.1·1.2: 이 함수를 부르지 않으므로 달라지는 것 없음.
--
-- 실행 전 supabase/scripts/check_member_page_before.sql, 실행 뒤 check_member_page_after.sql.
-- 074까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 076(칭호)과는 따로 실행·확인한다(순서는 075 → 076).
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 074 상태로 돌아간다.
--    (075는 기존 함수를 고치지 않았으므로 "변경 전 본문"이 없다 - 새로 만든 함수 1개와 설정값 1줄만 지운다.)
--    되돌린 뒤 check_member_page_before.sql 1번이 「없음」이면 정상.
--     begin;
--     drop function if exists public.member_page(text, integer);
--     delete from public.xp_rules where key = 'member_page_min_builds';
--     commit;
-- =====================================================================
begin;

do $$
begin
  if to_regclass('public.device_push_tokens') is null
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'push_settings' and column_name = 'comments') then
    raise exception '074가 아직 실행되지 않았습니다. 074를 먼저 실행해 주세요.';
  end if;
  if to_regprocedure('public.member_page(text, integer)') is not null
     or exists (select 1 from public.xp_rules where key = 'member_page_min_builds') then
    raise exception '075를 이미 실행했습니다.';
  end if;
end $$;

-- 개인 페이지가 열리는 공개 빌드 수 (나중에 바꾸려면 이 줄의 value만 고친다)
insert into public.xp_rules (key, value, note)
values ('member_page_min_builds', 5, '개인 페이지(075 member_page): 일반 사용자의 공개 빌드가 이 수 이상이면 열림');

create function public.member_page(p_user text, p_page integer default 1)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  uid uuid;
  p public.profiles%rowtype;
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
  n integer;
begin
  if p_user is null or p_user !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  uid := p_user::uuid;
  -- 일반 사용자만: 닉네임 있음, 비회원 아님, 운영자 아님, 장인 아님(장인은 public_profile)
  select * into p from public.profiles
   where id = uid and nickname is not null and not is_guest and role <> 'admin' and influencer is null;
  if not found then
    return null;
  end if;
  -- 지금 활동 제한(정지) 중이면 닫는다 (제한이 끝나거나 풀리면 다시 열림)
  if public.active_restriction_id(p.id) is not null then
    return null;
  end if;
  -- 공개 빌드 수 (숨김·대기 빌드, 숨긴 상대법의 빌드 제외)
  select count(*) into n
    from public.builds b join public.counters c on c.id = b.counter_id
   where b.author_id = p.id and b.status = 'approved' and c.status = 'approved';
  if n < coalesce(public.xp_rule('member_page_min_builds'), 5) then
    return null;
  end if;
  return jsonb_build_object(
    'member', jsonb_build_object(
      'id', p.id,
      'nickname', p.nickname,
      'photo_path', p.photo_path,
      'main_title', p.main_title,
      'titles', coalesce((
        select jsonb_agg(ut.title_key order by case tc.kind when 'activity' then 1 else 3 end, tc.sort_order, tc.key)
          from public.user_titles ut join public.title_catalog tc on tc.key = ut.title_key
         where ut.user_id = p.id and not tc.hidden and (not tc.secret or tc.key = p.main_title)
      ), '[]'::jsonb)),
    'total', n,
    'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(public.follow_build_card(x.id) order by x.t desc, x.id desc)
        from (select b.id, coalesce(b.updated_at, b.created_at) as t
                from public.builds b join public.counters c on c.id = b.counter_id
               where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'
               order by coalesce(b.updated_at, b.created_at) desc, b.id desc
               limit sz offset (pg - 1) * sz) x
    ), '[]'::jsonb));
end;
$$;
comment on function public.member_page(text, integer) is
  '075 일반 사용자 개인 페이지 (SPEC 6-108): 공개 빌드 member_page_min_builds개 이상인 일반 사용자만, 아니면 null. 닉네임·사진·칭호·공개 빌드만';
revoke all on function public.member_page(text, integer) from public;
grant execute on function public.member_page(text, integer) to anon, authenticated;

commit;
