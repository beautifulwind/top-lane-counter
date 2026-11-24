-- =====================================================================
-- 074: 댓글·답글 알림에 휴대폰 알림 - 푸시 묶음 comments 추가 (2026-11-24, SPEC 6-107, 1.3 패치 2-F) - 칸 1개 + 함수 2개 본문.
--
-- 지금: 댓글 알림 3종(아래)은 앱 안 알림 목록에만 쌓이고 푸시 묶음이 없어(push_group = null → push_wanted = false)
--   트리거 notifications_push가 Edge Function을 부르지 않았다.
--     post_comment  : 내 글에 새 댓글            (받는 사람 = 글 작성자)
--     doc_comment   : 내가 제안한 상대법 문서에 새 댓글 (받는 사람 = 상대법을 처음 제안한 사람)
--     comment_reply : 내 댓글에 새 답글(글·문서)  (받는 사람 = 부모 댓글 작성자)
--   세 종류 모두 notify_new_comment(061)가 만든다. 받는 사람·차단 규칙·문장은 이 파일이 바꾸지 않는다(새 수신 대상 없음).
--
-- 바꾸는 것 (이것만):
-- 1. push_settings에 칸 comments boolean not null default true (설정 줄이 없거나 옛 줄이어도 켜짐) + 로그인 사용자 update 칸 권한
--    (050·051·052·067과 같은 방식 - 본인 줄만, RLS 그대로).
-- 2. push_group(text) 본문: 줄 하나 더함 → when p_kind in ('post_comment', 'doc_comment', 'comment_reply') then 'comments'
--    (다른 종류의 결과는 그대로 - 세 종류는 지금 null이라 다른 묶음과 겹치지 않는다)
-- 3. push_wanted(uuid, text) 본문: case에 줄 하나 더함 → when 'comments' then coalesce(push_settings.comments, true)
--    (다른 묶음·운영자 모드·마지막 기기 조건(073)은 그대로)
--   두 함수의 이름·인자·반환·volatile·security definer·search_path·소유자·실행 권한은 create or replace라 그대로.
--   다른 함수(notify_new_comment·push_on_notification·push_targets 포함)·표·트리거·정책·데이터는 바꾸지 않는다.
--
-- 푸시가 언제 몇 번 가나: 트리거는 알림 줄이 "새로 생길 때(after insert)"만 부른다. notify_new_comment는 같은 대상의
--   안 읽은 알림이 있으면 새 줄을 만들지 않고 그 줄의 문장을 「새 댓글 N개」로 고친다(update) → 안 읽은 동안 댓글이 더 달려도
--   휴대폰 알림은 다시 울리지 않는다. 그 알림을 읽은 뒤 달린 댓글은 새 줄 → 그때 한 번 더 울린다.
--
-- 옛 앱 1.1·1.2: 설정 화면에 「댓글」 칸이 없어도 저장은 그대로 된다(아는 칸만 upsert → comments는 건드리지 않음, 새 줄이면 기본 켜짐).
--   그래서 옛 앱 사용자도 댓글 푸시를 받는다(끄려면 새 앱·웹에서). Edge Function을 다시 배포하기 전에는 제목 「탑신병자」·누르면
--   알림 목록으로 간다(새 Edge Function은 「새 댓글」·「새 답글」 + 그 글·상대법 댓글 칸으로).
--
-- 실행 전 supabase/scripts/check_comment_push_before.sql, 실행 뒤 check_comment_push_after.sql
-- (함수 본문 지문은 줄바꿈 CR을 뺀 값으로 비교). 073까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 073 상태로 돌아간다.
--    !! 칸 comments를 지우면 댓글 알림을 끈 기록도 사라진다(다시 074를 실행하면 모두 켜짐으로 시작).
--    알림 줄은 지우지 않는다(댓글 알림 종류는 074 전부터 있었다). 되돌린 뒤 check_comment_push_before.sql 2번이 「073 본문」이면 정상.
--     begin;
--     create or replace function public.push_group(p_kind text)
--     returns text language sql immutable set search_path = ''
--     as $$
--       select case
--         when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
--                         'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
--         when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--                         'revision_request', 'counter_restored', 'build_restored',
--                         'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--                         'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
--                         'profile_photo_removed',
--                         'warning_received') then 'my_results'  -- 062: 링크 삭제와 같은 묶음, 069: 운영자 경고도
--         when p_kind in ('followed_build_created') then 'follow_builds'
--         when p_kind in ('notice_posted') then 'notice'
--         when p_kind in ('new_followers') then 'new_followers'
--         when p_kind in ('build_edited') then 'build_edits'  -- 067 빌드 수정 알림
--       end;
--     $$;
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
--       and (exists (select 1 from public.push_subscriptions where user_id = p_user)
--            or exists (select 1 from public.device_push_tokens where user_id = p_user));  -- 073: 웹 구독 또는 앱 기기 토큰
--     $$;
--     alter table public.push_settings drop column if exists comments;  -- 칸 권한(grant update)도 함께 없어짐
--     commit;
-- =====================================================================
begin;

-- 다시 실행 방지 + 앞 단계 확인: 두 함수가 정확히 069·073 본문이고 칸이 아직 없을 때만 바꾼다
do $$
declare
  g text := (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.push_group(text)'));
  w text := (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.push_wanted(uuid, text)'));
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name = 'comments')
     or g = '2be75ed999aa158e20557beda4db0814' or w = 'fa8eb83cd5786a7155e5f2439917b04e' then
    raise exception '074를 이미 실행했습니다 (push_settings.comments 칸이 있음). 다시 실행하지 마세요. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if w is distinct from 'e6f1723ae3a6b0126ece4b51488a067c' then
    raise exception '073을 먼저 실행해 주세요 (push_wanted 지문 %, 073이면 e6f1723a…). 아무것도 바뀌지 않았습니다.', coalesce(w, '함수 없음') using errcode = 'P0001';
  end if;
  if g is distinct from 'ba44f97f41cc99cbb3590c8528ace024' then
    raise exception 'push_group 본문이 069와 다릅니다 (지문 %). 실행하지 말고 알려 주세요. 아무것도 바뀌지 않았습니다.', coalesce(g, '함수 없음') using errcode = 'P0001';
  end if;
end $$;

-- 1. 알림 설정 칸: 댓글·답글 (기본 켜짐)
alter table public.push_settings add column comments boolean not null default true;
comment on column public.push_settings.comments is '댓글·답글 휴대폰 알림 (074: post_comment·doc_comment·comment_reply). 기본 켜짐';
grant update (comments) on public.push_settings to authenticated;  -- 본인 줄만 (RLS 그대로, 050·051·052·067과 같은 방식)

-- 2. 알림 종류 → 묶음: 줄 하나 더함 (나머지는 069 본문 그대로)
create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored',
                    'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
                    'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
                    'profile_photo_removed',
                    'warning_received') then 'my_results'  -- 062: 링크 삭제와 같은 묶음, 069: 운영자 경고도
    when p_kind in ('followed_build_created') then 'follow_builds'
    when p_kind in ('notice_posted') then 'notice'
    when p_kind in ('new_followers') then 'new_followers'
    when p_kind in ('build_edited') then 'build_edits'  -- 067 빌드 수정 알림
    when p_kind in ('post_comment', 'doc_comment', 'comment_reply') then 'comments'  -- 074 댓글·답글
  end;
$$;

-- 3. 묶음별 설정: 줄 하나 더함 (나머지는 073 본문 그대로)
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
    when 'comments' then
      coalesce((select s.comments from public.push_settings s where s.user_id = p_user), true)  -- 074 댓글·답글
    else false
  end
  and (exists (select 1 from public.push_subscriptions where user_id = p_user)
       or exists (select 1 from public.device_push_tokens where user_id = p_user));  -- 073: 웹 구독 또는 앱 기기 토큰
$$;

commit;
