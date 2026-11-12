-- =====================================================================
-- 048: 장인 외부 링크 삭제를 감독관도 (2026-11-12, SPEC 6-34 3b)
--
-- 바꾸는 것은 바깥 함수 remove_link(링크, 사유) 하나뿐이다. 안쪽 remove_link_unchecked(047)는 그대로라
-- 사유 필수 / 링크와 그 신고 줄 삭제 / 올린 장인에게 link_removed 알림 / 처리 기록 remove_link(메모에 지운 주소/사유)는 047과 같다.
--   - 운영자: 모든 링크 (운영자 모드가 꺼져 있으면 거부 - require_staff가 "운영자만 할 수 있습니다.")
--   - 감독관: 일반 장인(role = user)의 링크만. 운영진(운영자/감독관 본인/다른 감독관)이 올린 링크는 거부
--     ("운영진이 올린 링크는 운영자만 삭제할 수 있습니다." 42501) - 게시판 숨기기/빌드 숨기기와 같은 기준(030 moderatable_author).
--     감독관에게는 운영자 모드가 없다(늘 켜진 셈 - 034 is_staff 그대로).
--   - 일반 회원/비로그인: 거부.
--   처리 기록의 처리자 역할(actor_role)에 moderator가 남는다.
-- 그대로인 것: 신고 목록 admin_link_reports / 신고 기각 dismiss_link_reports / 허용 사이트 더하기/빼기는 운영자만(047).
--   새 표/칸/설정값/알림 종류는 없다. pg_cron 필요 없음. Edge Function 재배포 필요 없음.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다 (047의 "운영자만" 으로 돌아간다).
--     begin;
--     create or replace function public.remove_link(p_link bigint, p_note text)
--     returns void language plpgsql security definer set search_path = ''
--     as $f$
--     begin
--       perform public.require_operator();
--       perform public.remove_link_unchecked(p_link, p_note);
--     end;
--     $f$;
--     commit;
--   (감독관이 이미 지운 링크/처리 기록/알림은 그대로 남는다.)
--
-- 하위 호환: 함수 이름/인자/반환 그대로. 지금 화면과 그대로 동작한다.
-- 순서: check_link_moderation.sql(실행 전) -> 이 파일 실행 -> check_link_moderation.sql(실행 후).
-- 047까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.ext_links') is null then
    raise exception '047이 아직 실행되지 않았습니다. 047_influencer_links.sql을 먼저 실행해 주세요.';
  end if;
  if (select prosrc from pg_proc where oid = 'public.remove_link(bigint, text)'::regprocedure) like '%moderatable_author%' then
    raise exception '048을 이미 실행했습니다.';
  end if;
end $$;

create or replace function public.remove_link(p_link bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  owner uuid;
begin
  perform public.require_staff();  -- 운영자(모드 켜짐) 또는 감독관
  if not public.is_admin() then
    select l.owner_id into owner from public.ext_links l where l.id = p_link;
    if not found then
      raise exception '링크를 찾지 못했습니다. 이미 지워졌을 수 있습니다.' using errcode = 'P0002';
    end if;
    if owner is null or not public.moderatable_author(owner) then
      raise exception '운영진이 올린 링크는 운영자만 삭제할 수 있습니다.' using errcode = '42501';
    end if;
  end if;
  perform public.remove_link_unchecked(p_link, p_note);
end;
$$;
comment on function public.remove_link(bigint, text) is
  E'장인 외부 링크 삭제 (047, 048) \u2014 운영자(모드 켜짐)는 전부, 감독관은 일반 장인의 링크만. 사유 필수, link_removed 알림, 처리 기록 remove_link';

revoke execute on function public.remove_link(bigint, text) from public, anon;
grant execute on function public.remove_link(bigint, text) to authenticated;  -- 운영진인지는 함수 안에서

commit;

-- 확인 (실행 뒤): supabase/scripts/check_link_moderation.sql
