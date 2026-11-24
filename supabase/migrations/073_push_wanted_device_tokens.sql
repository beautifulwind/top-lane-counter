-- =====================================================================
-- 073: 앱 토큰만 있는 사람도 앱 푸시를 받게 - push_wanted() 마지막 조건 하나만 바꾼다 (2026-11-24, SPEC 6-106, 1.3 패치 P-2b)
--
-- 문제: 알림 줄이 생기면 트리거 notifications_push(→ push_on_notification)가 push_wanted(받는 사람, 종류)가 true일 때만
--   Edge Function web-push를 부른다. 그런데 push_wanted 최신 본문(067)은 마지막에
--     and exists (select 1 from public.push_subscriptions where user_id = p_user)
--   즉 "웹 푸시 구독이 하나라도 있음"을 요구한다. 그래서 웹 알림을 한 번도 켜지 않고 앱(iOS·Android)에서만 알림을 켠
--   사람(device_push_tokens에만 줄이 있음)은 Edge Function이 아예 불리지 않아 앱 푸시가 조용히 건너뛰어졌다.
--   (072 머리 주석 7번의 "웹 구독이 없는 사람에게도 부른다"는 틀린 설명이었다 - 이 파일이 그 동작을 실제로 만든다)
--
-- 바꾸는 것: push_wanted(uuid, text)의 마지막 조건 하나
--     전) and exists (select 1 from public.push_subscriptions where user_id = p_user);
--     후) and (exists (select 1 from public.push_subscriptions where user_id = p_user)
--              or exists (select 1 from public.device_push_tokens where user_id = p_user));
--   = "웹 구독이 있거나 앱 기기 토큰이 있음". 그 위의 판단(알림 종류별 묶음 push_group, 운영진 알림의 감독관/운영자 모드,
--   push_settings 종류별 켜기·끄기와 설정 줄이 없을 때의 기본값)은 한 글자도 바꾸지 않았다.
--   이름·인자·반환(boolean)·stable·security definer·search_path ''·소유자·실행 권한은 create or replace라 그대로 남는다.
--
-- 함수가 device_push_tokens를 읽을 수 있는 이유: push_wanted는 security definer라 소유자(postgres) 권한으로 돈다.
--   device_push_tokens(072)도 postgres가 만든 표라 소유자가 같고, 표 소유자는 FORCE ROW LEVEL SECURITY가 아니면 RLS를 거치지 않는다
--   (072는 RLS를 켰지만 FORCE는 하지 않았다). 072의 revoke는 public·anon·authenticated·service_role에서만 걷었으므로 소유자 권한은 그대로.
--   → 아래 "다시 실행 방지" 블록이 실행 때 소유자 일치·FORCE 꺼짐·소유자 select 권한을 확인하고, 아니면 멈춘다.
--
-- 영향: 앱 토큰만 있는 사람에게 알림이 생기면 이제 Edge Function이 불린다. push_targets(같은 push_wanted를 씀)는 그 사람에게
--   웹 구독 목록 [](빈 목록)을 돌려주므로 웹 발송은 0건으로 끝나고(오류 없음), 앱 발송이 이어진다(Edge Function 코드 변경·재배포 불필요).
--   웹 구독이 있는 사람·둘 다 없는 사람의 결과는 전과 같다. 다른 함수·표·트리거·정책·권한·데이터는 바꾸지 않는다.
--   068 쓰기 함수 수(103 / 첫 줄 검사 30 / 허용 목록 73)도 그대로 (push_wanted는 일반 사용자가 부를 수 없는 stable 함수).
--
-- 실행 전 supabase/scripts/check_push_wanted_before.sql, 실행 뒤 check_push_wanted_after.sql
-- (함수 본문 지문은 줄바꿈 CR을 뺀 값으로 비교). 072까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 072 상태(067 본문)로 돌아간다.
--    데이터는 아무것도 지우지 않는다. 되돌리면 앱 토큰만 있는 사람은 다시 앱 푸시를 못 받는다.
--    되돌린 뒤 check_push_wanted_before.sql의 2번이 「067 본문」이면 정상.
--     begin;
--     create or replace function public.push_wanted(p_user uuid, p_kind text)
--     returns boolean language sql stable security definer set search_path = ''
--     as $$
--       select case public.push_group(p_kind)
--         when 'staff_new' then
--           exists (select 1 from public.profiles p
--                    where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
--           and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
--         when 'my_results' then
--           coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
--         when 'follow_builds' then
--           coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
--         when 'notice' then
--           coalesce((select s.notice from public.push_settings s where s.user_id = p_user), true)
--         when 'new_followers' then
--           coalesce((select s.new_followers from public.push_settings s where s.user_id = p_user), false)  -- 설정 줄이 없으면 꺼짐
--         when 'build_edits' then
--           coalesce((select s.build_edits from public.push_settings s where s.user_id = p_user), true)  -- 067
--         else false
--       end
--       and exists (select 1 from public.push_subscriptions where user_id = p_user);
--     $$;
--     commit;
-- =====================================================================
begin;

-- 다시 실행 방지 + 앞 단계 확인 + 소유자 권한 확인: 하나라도 아니면 아무것도 바꾸지 않고 멈춘다
do $$
declare
  src text := (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.push_wanted(uuid, text)'));
begin
  if to_regclass('public.device_push_tokens') is null then
    raise exception '072를 먼저 실행해 주세요 (device_push_tokens 표가 없음). 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if src is null then
    raise exception 'push_wanted(uuid, text) 함수가 없습니다. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if src = 'e6f1723ae3a6b0126ece4b51488a067c' then
    raise exception '073을 이미 실행했습니다 (push_wanted가 이미 앱 토큰을 봄). 다시 실행하지 마세요. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if src <> 'bfb8e95016ca726a7dade1b76bb56fce' then
    raise exception 'push_wanted 본문이 067과 다릅니다 (지문 %). 실행하지 말고 알려 주세요. 아무것도 바뀌지 않았습니다.', src using errcode = 'P0001';
  end if;
  if (select p.proowner from pg_proc p where p.oid = 'public.push_wanted(uuid, text)'::regprocedure)
       <> (select c.relowner from pg_class c where c.oid = 'public.device_push_tokens'::regclass)
     or (select c.relforcerowsecurity from pg_class c where c.oid = 'public.device_push_tokens'::regclass)
     or not has_table_privilege((select p.proowner from pg_proc p where p.oid = 'public.push_wanted(uuid, text)'::regprocedure),
                                'public.device_push_tokens', 'select') then
    raise exception 'push_wanted 소유자가 device_push_tokens를 읽을 수 없습니다 (소유자 다름·FORCE RLS·select 권한 없음 중 하나). 실행하지 말고 알려 주세요. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
end $$;

-- 마지막 조건만 바뀜 (웹 구독 → 웹 구독 또는 앱 기기 토큰). 나머지는 067 본문 그대로
create or replace function public.push_wanted(p_user uuid, p_kind text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case public.push_group(p_kind)
    when 'staff_new' then
      exists (select 1 from public.profiles p
               where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
      and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
    when 'my_results' then
      coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
    when 'follow_builds' then
      coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
    when 'notice' then
      coalesce((select s.notice from public.push_settings s where s.user_id = p_user), true)
    when 'new_followers' then
      coalesce((select s.new_followers from public.push_settings s where s.user_id = p_user), false)  -- 설정 줄이 없으면 꺼짐
    when 'build_edits' then
      coalesce((select s.build_edits from public.push_settings s where s.user_id = p_user), true)  -- 067
    else false
  end
  and (exists (select 1 from public.push_subscriptions where user_id = p_user)
       or exists (select 1 from public.device_push_tokens where user_id = p_user));  -- 073: 웹 구독 또는 앱 기기 토큰
$$;

commit;
