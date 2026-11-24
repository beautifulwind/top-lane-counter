-- =====================================================================
-- 072: 앱(iOS·Android) 푸시 기기 토큰 저장 - 표 device_push_tokens + 쓰기 함수 2개 (2026-11-24, SPEC 6-101, 1.3 패치 P-1) - "더하기만" 한다.
--
-- 1. 표 device_push_tokens: 한 줄 = 앱이 설치된 기기 하나의 푸시 토큰 (APNs 또는 FCM이 앱에 준 값).
--    - user_id → profiles(id) on delete cascade: push_subscriptions(037)와 같은 방식. 탈퇴·계정 삭제(auth.users 삭제 → profiles 삭제)
--      때 함께 지워진다. 탈퇴 함수(withdraw_account_unchecked)는 고치지 않는다(push_subscriptions도 이 cascade로만 지워진다).
--    - platform 'ios' | 'android'만. token은 32~1000자, 글자는 영문·숫자·: _ . - 만(APNs 16진수·FCM 토큰 모두 들어감, 공백·줄바꿈 없음).
--    - (platform, token)은 한 줄만: 같은 기기에서 다른 계정으로 로그인해 등록하면 새 줄이 아니라 그 줄의 소유자가 바뀐다
--      (앞 계정의 알림이 그 기기로 가지 않게).
--    - app_version은 null 허용, 1~32자(영문·숫자·. + _ -). created_at = 이 계정에 등록된 시각(소유자가 바뀌면 새로),
--      last_seen_at = 앱이 마지막으로 등록(확인)한 시각.
--    - RLS 켬 + 정책 없음 + 비로그인·로그인·public 권한 모두 회수 → 앱은 표를 직접 읽거나 쓸 수 없다(아래 함수로만).
--      발송은 Edge Function이 service_role로 이 표를 직접 읽는다(select). 무효 토큰 정리용으로 delete도 준다. 넣기·고치기는 함수로만.
-- 2. register_device_push_token(p_platform text, p_token text, p_app_version text) → jsonb { platform, devices } (로그인만, anon·public 없음)
--    - 본인 기기로 등록. 이미 있는 (platform, token)이면 소유자·app_version·last_seen_at을 갱신(소유자가 바뀌면 created_at도 새로).
--    - 한 사람 최대 10대: 넘으면 last_seen_at이 가장 오래된 것부터 지운다(방금 등록한 기기는 지우지 않는다).
--    - 비회원(게스트) 계정도 된다(push_subscriptions 넣기 정책과 같음 - 닉네임 없어도 됨).
-- 3. unregister_device_push_token(p_token text) → boolean (로그인만): 본인 소유의 그 토큰만 지운다. 없거나 남의 것이면 false(오류 없음).
--    로그아웃 때 쓴다.
-- 4. 토큰이 로그·오류 문장에 나오지 않게: 함수가 넣기 전에 표 제약과 같은 검사를 먼저 해서 고정 문장으로 거절한다
--    (제약 위반 오류의 "Failing row contains (…)" 상세에 토큰이 찍히는 일을 막는다). 오류 문장·반환값에 토큰을 넣지 않는다.
--    (platform, token) 중복은 on conflict로 처리해 중복 키 오류(상세에 값이 찍힘)도 나지 않는다.
-- 5. 068 활동 제한: 두 함수는 assert_can_write를 넣지 않고 허용 목록(restriction_exemptions)에 넣는다.
--    선례: 웹 푸시 켜기·끄기(push_subscriptions 넣기·지우기 정책)와 알림 읽음 처리(mark_notifications_read 등)가 허용 목록에 있다.
--    활동 제한 중인 사람도 알림(제한·경고 안내 포함)을 받아야 하고, 토큰 등록은 남에게 보이는 글쓰기가 아니다.
--    → 쓰기 함수 101 → 103, 첫 줄 검사 30 그대로, 허용 목록 함수 71 → 73.
-- 6. 그대로인 것: 기존 함수(이름·인자·반환·본문) 전부 - notifications_push 트리거·push_on_notification·push_targets·push_wanted·push_forget 포함,
--    push_subscriptions·push_settings·notifications 표·트리거·정책·권한·데이터. 옛 앱 1.1·1.2는 새 함수를 부르지 않으므로 그대로.
-- 7. 발송(다음 단계, 이 파일에는 없음): 지금도 알림 줄이 생기면 트리거가 push_wanted로 거른 뒤 Edge Function web-push를 알림 번호로 부른다
--    (웹 구독이 없는 사람에게도 부른다). Edge Function은 service_role로 notifications에서 그 번호의 user_id·created_at을 읽고
--    (push_targets와 같은 1시간 규칙), device_push_tokens에서 그 사람의 토큰을 읽어 보낸다. 무효 토큰은 이 표에서 지운다.
--
-- 실행 전 supabase/scripts/check_device_push_tokens_before.sql, 실행 뒤 check_device_push_tokens_after.sql
-- (함수 본문 지문은 줄바꿈 CR을 뺀 값으로 비교). 071까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- 화면(앱 등록·해제 호출)·Edge Function 발송은 이번에 없다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 071 상태로 돌아간다.
--    !! 표를 지우면 그때까지 저장된 기기 토큰이 모두 사라진다(되살릴 수 없음 - 앱을 다시 열어 등록해야 앱 푸시가 다시 간다).
--    !! 토큰을 남기고 등록·해제만 막으려면 아래 1)만 실행한다.
--     begin;
--     -- 1) 함수 + 허용 목록 두 줄만 지움 (토큰은 남는다. 앱이 함수를 부르면 「함수를 찾을 수 없음」 오류)
--     drop function if exists public.register_device_push_token(text, text, text);
--     drop function if exists public.unregister_device_push_token(text);
--     delete from public.restriction_exemptions where kind = 'function'
--        and name in ('register_device_push_token(text, text, text)', 'unregister_device_push_token(text)');
--     -- 2) 표까지 지움 - 저장된 기기 토큰 삭제 (제약·색인은 표와 함께 지워진다)
--     drop table if exists public.device_push_tokens;
--     commit;
-- =====================================================================
begin;

-- 다시 실행 방지: 이미 표나 함수가 있으면 아무것도 바꾸지 않고 멈춘다
do $$
begin
  if to_regclass('public.device_push_tokens') is not null
     or to_regprocedure('public.register_device_push_token(text, text, text)') is not null
     or to_regprocedure('public.unregister_device_push_token(text)') is not null then
    raise exception '072를 이미 실행했습니다 (device_push_tokens 표 또는 register/unregister_device_push_token 함수가 있음). 다시 실행하지 마세요. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if to_regprocedure('public.set_build_difficulty(bigint, numeric)') is null or to_regclass('public.push_subscriptions') is null
     or to_regclass('public.restriction_exemptions') is null then
    raise exception '071까지 먼저 실행해 주세요 (set_build_difficulty 함수·push_subscriptions 표·restriction_exemptions 표 중 없는 것이 있음). 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 표
-- ---------------------------------------------------------------------
create table public.device_push_tokens (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  platform     text not null constraint device_push_tokens_platform_check check (platform in ('ios', 'android')),
  token        text not null constraint device_push_tokens_token_check
                 check (length(token) between 32 and 1000 and token ~ '^[A-Za-z0-9:_.-]+$'),
  app_version  text constraint device_push_tokens_app_version_check
                 check (app_version is null or (length(app_version) between 1 and 32 and app_version ~ '^[A-Za-z0-9.+_-]+$')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint device_push_tokens_platform_token_key unique (platform, token)
);
create index device_push_tokens_user on public.device_push_tokens (user_id, last_seen_at desc);
comment on table public.device_push_tokens is
  '앱(iOS·Android) 푸시 기기 토큰 (072). 앱은 register/unregister_device_push_token 함수로만, 발송 Edge Function은 service_role로 읽기·무효 토큰 지우기. (platform, token) 한 줄, 한 사람 최대 10대, 탈퇴 때 함께 삭제';

alter table public.device_push_tokens enable row level security;  -- 정책 없음 = 비로그인·로그인은 한 줄도 못 봄
revoke all on public.device_push_tokens from public, anon, authenticated, service_role;
grant select, delete on public.device_push_tokens to service_role;  -- 발송(읽기)·무효 토큰 정리(지우기)만

-- ---------------------------------------------------------------------
-- 2. 등록 (로그인한 본인 기기로)
-- ---------------------------------------------------------------------
create function public.register_device_push_token(p_platform text, p_token text, p_app_version text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  plat text := lower(btrim(coalesce(p_platform, '')));
  tok text := btrim(coalesce(p_token, ''));
  ver text := nullif(btrim(coalesce(p_app_version, '')), '');
  row_id bigint;
  devices integer;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  -- 표 제약과 같은 검사를 먼저 한다 - 오류 문장에 토큰이 나오지 않게 (제약 위반 상세에는 줄 내용이 찍힌다)
  if plat not in ('ios', 'android') then
    raise exception '기기 종류는 ios 또는 android만 됩니다.' using errcode = '22023';
  end if;
  if length(tok) not between 32 and 1000 or tok !~ '^[A-Za-z0-9:_.-]+$' then
    raise exception '알림 토큰 형식이 올바르지 않습니다.' using errcode = '22023';
  end if;
  if ver is not null and (length(ver) > 32 or ver !~ '^[A-Za-z0-9.+_-]+$') then
    raise exception '앱 버전 형식이 올바르지 않습니다.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = me) then
    raise exception '계정 정보를 찾을 수 없습니다. 다시 로그인해 주세요.' using errcode = '42501';
  end if;

  -- 같은 사람의 등록을 한 줄로 세운다 (10대 제한이 동시에 두 번 계산되지 않게)
  perform pg_advisory_xact_lock(hashtextextended('device_push_tokens:' || me::text, 0));

  insert into public.device_push_tokens as d (user_id, platform, token, app_version)
  values (me, plat, tok, ver)
  on conflict (platform, token) do update
     set user_id = excluded.user_id,
         app_version = excluded.app_version,
         last_seen_at = now(),
         created_at = case when d.user_id = excluded.user_id then d.created_at else now() end  -- 소유자가 바뀌면 새로 등록한 것
  returning d.id into row_id;

  -- 한 사람 최대 10대: 방금 등록한 기기 + 최근에 확인된 9대만 남긴다
  delete from public.device_push_tokens
   where user_id = me and id <> row_id
     and id not in (select id from public.device_push_tokens
                     where user_id = me and id <> row_id
                     order by last_seen_at desc, id desc limit 9);

  select count(*) into devices from public.device_push_tokens where user_id = me;
  return jsonb_build_object('platform', plat, 'devices', devices);  -- 토큰은 돌려주지 않는다
end;
$$;
comment on function public.register_device_push_token(text, text, text) is
  '앱 푸시 기기 토큰 등록·갱신 (072). 로그인 본인, ios/android, 같은 (platform, token)이면 소유자 이전, 한 사람 10대(오래된 것부터 지움). 토큰은 반환·오류에 없음';

-- ---------------------------------------------------------------------
-- 3. 해제 (본인 소유만, 없으면 false)
-- ---------------------------------------------------------------------
create function public.unregister_device_push_token(p_token text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  n integer;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  delete from public.device_push_tokens where user_id = me and token = btrim(coalesce(p_token, ''));
  get diagnostics n = row_count;
  return n > 0;
end;
$$;
comment on function public.unregister_device_push_token(text) is
  '앱 푸시 기기 토큰 해제 (072, 로그아웃 때). 본인 소유만 지움, 없거나 남의 것이면 false (오류 없음)';

revoke execute on function public.register_device_push_token(text, text, text) from public, anon;
revoke execute on function public.unregister_device_push_token(text) from public, anon;
grant execute on function public.register_device_push_token(text, text, text) to authenticated;
grant execute on function public.unregister_device_push_token(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. 068 빠뜨림 방지 허용 목록: 활동 제한 중에도 알림을 받을 수 있어야 함 (웹 푸시 켜기·끄기 정책과 같은 이유)
-- ---------------------------------------------------------------------
insert into public.restriction_exemptions (kind, name, reason) values
  ('function', 'register_device_push_token(text, text, text)', '072 앱 휴대폰 알림 켜기 - 활동 제한 중에도 알림을 받아야 함 (웹 푸시 켜기와 같음)'),
  ('function', 'unregister_device_push_token(text)', '072 앱 휴대폰 알림 끄기·로그아웃 (웹 푸시 끄기와 같음)');

commit;
