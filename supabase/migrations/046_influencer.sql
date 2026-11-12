-- =====================================================================
-- 046: 장인 인증 - 1단계 DB (2026-11-12, SPEC 6-32)
--   화면 문구는 "장인", 코드/DB 이름은 influencer 그대로.
--
-- 1. 신청 표 influencer_applications - 장인은 두 유형
--    (a) 크리에이터 creator / 프로게이머 pro: 채널/방송 링크 + 공식 이메일(필수). 운영자가 그 이메일로 확인 메일을 보내고(사이트 밖)
--        "본인입니다" 회신을 확인한 뒤 승인/반려.
--    (b) 그랜드마스터 이상 grandmaster: 라이엇 닉네임#태그 + op.gg 링크(필수). 신청자가 운영자의 인증 전용 라이엇 계정에 친구 요청을 보내고,
--        운영자는 수락하지 않고 보낸 사람 이름과 op.gg 티어만 확인한 뒤 승인/반려. (운영자 계정 닉네임은 DB에 두지 않는다 - 화면 문구 상수 한 곳)
--    - 14일(influencer_review_days) 안에 처리되지 않으면 만료(influencer-daily). 운영자는 만료일을 7일 늘릴 수 있다.
--    - 같은 채널 주소/같은 라이엇 닉네임#태그(대소문자/공백 정규화)로 처리 전/승인된 신청이 겹치지 않는다(부분 unique 인덱스).
--    - 공식 이메일/라이엇 닉네임#태그는 심사가 끝나면(승인/반려/만료/취소/탈퇴) 트리거가 바로 지운다.
--      승인된 (b)는 겹침 검사용 해시(riot_key, sha256)만 남고, 해제/탈퇴 때 그것도 지운다. 읽기는 본인/운영자만(감독관 제외).
--    - 반려 뒤 7일, 180일 동안 운영자 반려 3번이면 180일 동안 다시 신청할 수 없다(만료/취소는 세지 않음).
--      반려하면 그 라이엇 닉네임#태그/채널은 바로 풀려 다른 사람이 즉시 신청할 수 있다(선점 방해 막기).
--      운영자가 [바로 다시 신청 허용]으로 반려하면 7일 제한도 없고 3번에도 세지 않는다.
--    - 가입 뒤 최소 기간 influencer_min_account_days = 0(끔, xp_rules로 조절).
-- 2. 닉네임
--    - nickname_key: 비슷한 글자(대소문자/전각/키릴/그리스 글자/0/o/1/l/I/rn/m/띄어쓰기/구분 기호)를 같은 글자로 본 열쇠.
--      닉네임 유일성 인덱스를 lower(nickname) -> nickname_key 부분 인덱스 2개로 바꾼다:
--        profiles_nickname_key_unique  (nickname_state is null)       - 보통 닉네임끼리 겹치지 않음
--        profiles_nickname_key_pending (nickname_state = 'pending')   - 인증 대기끼리 겹치지 않음
--      그래서 "보통 닉네임 1명 + 같은 닉네임으로 신청한 인증 대기 1명"만 잠깐 함께 있을 수 있다.
--      승인되면 원래 쓰던 사람은 'yielding'(닉네임 변경 예정, 3일)이 되고 장인이 보통 닉네임이 된다. 3일이 지나면 임시 닉네임 탑신병자#xxxxxx.
--    - 신청하면 닉네임이 희망 닉네임으로 바뀌고 "인증 대기"(nickname_state 'pending'). 심사 중에는 직접 못 바꾼다.
--      반려/만료/취소 때 다른 사람과 겹쳐 있으면(또는 운영자가 [닉네임도 되돌리기]를 고르면) 되돌린다:
--      이전 닉네임이 비어 있으면(아무도 안 쓰면) 이전 것, 아니면 임시 닉네임.
--    - 인증된 장인은 닉네임을 직접 못 바꾸고 운영자가 바꾼다(admin_set_nickname). "닉네임 변경 예정"인 사람은 30일 제한 없이 바로 바꿀 수 있다.
--      임시 닉네임/되돌린 닉네임/운영자가 바꾼 닉네임 뒤에도 30일 제한 없이 바꿀 수 있다(nickname_changes.kind).
--    - 사칭 막기: "[장인]"/"(장인)"(괄호 모양 변형 포함)이 든 닉네임, "장인 "으로 시작하는 닉네임 금지 (nickname_reserved, 기존 (운)/(감)과 함께).
-- 3. 알림 - 운영자용 influencer_applied(푸시 staff_new, 운영자 모드를 끄면 가림) / 신청자/회원용(푸시 my_results):
--    influencer_received / influencer_expiring / influencer_approved / influencer_rejected / influencer_expired / influencer_revoked /
--    nickname_reset_soon(닉네임 변경 예정, 유예 시작) / nickname_reset / link_removed(3단계 047에서 씀 - 종류만 미리).
--    influencer_received/influencer_expiring의 (b) 문장에는 "{운영자 닉네임}" 자리표시가 들어 있고 화면/푸시가 문구 상수로 채운다(조사는 josa.js).
-- 4. 처리 기록 approve_influencer / reject_influencer / extend_influencer / revoke_influencer / rename_member (대상 influencer_application / user)
--    처리 대기 건수 admin_pending_counts()에 influencers(운영자만, 감독관 0).
-- 5. 회원 관리: admin_new_members(시간 기본 24, 쪽, 크기) - 운영자 전용(_unchecked + require_operator), 정식 회원만(비회원 제외),
--    돌려주는 값은 id/닉네임/가입일/가입 방식/역할뿐(이메일/로그인 ID 없음). 24시간은 보여 주는 기간일 뿐 지우지 않는다.
-- 6. 사람 json 칸: profiles에 influencer(유형)/influencer_at/nickname_state/nickname_reset_at (누구나 읽음, 직접 못 고침).
--    사람을 json으로 돌려주는 함수(build_contributors/admin_build_revisions/board_page/open_reports_for_moderator/admin_member_list/
--    admin_search_members/admin_member_info)에 influencer/nickname_state를 더한다.
--    장인 빌드 라벨용 build_editor_counts(상대법): 빌드마다 시초를 뺀 기여자 수 ("이후 N명이 수정했습니다").
-- 7. influencer_daily(): 만료 처리 / 만료 3일 전 알림(한 신청에 한 번) / 유예가 끝난 닉네임을 임시 닉네임으로 / 끝난 지 1년 지난 신청 정리.
--    pg_cron으로 하루 한 번 (등록 SQL은 작업 보고에 따로 - 이 파일에는 없다).
--
-- 만들지 않는 것: 빌드 수정 잠금(edit_lock - 장인 빌드도 위키처럼 누구나 고침, build_edit_check 그대로), 증빙 파일 버킷/인증 코드, 외부 링크(047).
--
-- >> 실행 전 확인 (필수): supabase/scripts/check_influencer.sql을 먼저 실행해 1번 줄 "닉네임 열쇠 중복"이 0인지 본다.
--   0이 아니면 같은 줄 메모의 닉네임들 중 한쪽에 닉네임 변경을 부탁하고 다시 확인한다.
--   (이 파일도 맨 앞에서 같은 검사를 하고, 겹치면 아무것도 바꾸지 않고 멈춘다.)
--
-- >> 되돌리기 (닉네임 인덱스 롤백) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다.
--   인증 대기/닉네임 변경 예정 상태가 남아 있으면 같은 닉네임이 둘일 수 있어 옛 인덱스가 만들어지지 않으므로 먼저 상태를 정리한다.
--   (장인 기능 전체를 지우는 것이 아니라 닉네임 유일성 규칙만 예전 lower(nickname)으로 되돌린다.)
--     begin;
--     select public.influencer_close(id, 'cancelled', null, true, false) from public.influencer_applications where status = 'pending';
--     select public.system_set_nickname(id, public.influencer_temp_nickname(), null, null, 'reset')
--       from public.profiles where nickname_state = 'yielding';
--     drop index public.profiles_nickname_key_unique;
--     drop index public.profiles_nickname_key_pending;
--     create unique index profiles_nickname_unique on public.profiles (lower(nickname));
--     commit;
--   다시 046의 인덱스로 돌아가려면:
--     begin;
--     drop index public.profiles_nickname_unique;
--     create unique index profiles_nickname_key_unique on public.profiles (nickname_key) where nickname_state is null;
--     create unique index profiles_nickname_key_pending on public.profiles (nickname_key) where nickname_state = 'pending';
--     commit;
--
-- 하위 호환: 있던 표/함수의 이름/인자/반환은 그대로(사람 json에 키 둘이 늘 뿐, 처리 대기 건수에 키 하나). 새 표/칸/함수/알림 종류만 더한다.
--   지금 배포된 화면과 그대로 동작한다(옛 화면은 모르는 알림 종류를 종 모양 + 문장으로 보여 준다. 신청 화면이 없으니 신청도 안 들어온다).
--   닉네임 중복 판정만 바뀐다: "Faker"와 "FakerI"/"Fa ker"처럼 비슷한 닉네임은 이제 새로 정할 수 없다(이미 있는 닉네임은 그대로).
--   중복 오류는 예전과 같은 23505라 지금 화면이 "이미 사용 중인 닉네임입니다."로 보여 준다.
-- 순서: check_influencer.sql(실행 전) -> 이 파일 실행 -> check_influencer.sql(실행 후) -> pg_cron 일정 등록 -> (2단계) 화면 push/web-push 재배포.
-- 045까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
                    and pg_get_constraintdef(oid) like '%report_received%') then
    raise exception '045가 아직 실행되지 않았습니다. 045_report_received_notify.sql을 먼저 실행해 주세요.';
  end if;
  if to_regclass('public.influencer_applications') is not null then
    raise exception '046을 이미 실행했습니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 0. 설정값
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('influencer_min_account_days',    0, '장인 인증: 가입 뒤 이 일수가 지나야 신청 (0 = 제한 없음, 046)'),
  ('influencer_review_days',        14, '장인 인증: 신청 뒤 이 일수 안에 처리되지 않으면 만료 (046)'),
  ('influencer_extend_days',         7, '장인 인증: 운영자 [만료일 늘리기] 한 번에 늘리는 일수 (046)'),
  ('influencer_expiring_days',       3, '장인 인증: 만료 이 일수 전에 신청자에게 알림 (한 신청에 한 번, 046)'),
  ('influencer_retry_days',          7, '장인 인증: 운영자가 반려한 뒤 이 일수가 지나야 다시 신청 (046)'),
  ('influencer_reject_window_days', 180, '장인 인증: 이 일수 안에 반려가 influencer_reject_limit번이면 신청 금지 (046)'),
  ('influencer_reject_limit',        3, E'장인 인증: 신청 금지가 되는 반려 횟수 (만료\u00B7취소\u00B7[바로 다시 신청 허용] 반려는 안 셈, 046)'),
  ('influencer_ban_days',          180, '장인 인증: 반려가 쌓였을 때 신청 금지 일수 (마지막 반려부터, 046)'),
  ('influencer_nickname_grace_days', 3, E'장인 인증: 장인과 같은 닉네임을 쓰던 회원이 새 닉네임을 정할 유예 일수 \u2014 지나면 임시 닉네임 (046)'),
  ('influencer_keep_days',         365, E'장인 인증: 끝난 신청(반려\u00B7만료\u00B7취소\u00B7탈퇴\u00B7해제) 보관 일수 \u2014 지나면 influencer_daily가 지움 (046)')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 1. 닉네임 열쇠 (비슷한 글자 사칭 막기)
-- ---------------------------------------------------------------------
create function public.nickname_key(p text)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  n text;
begin
  if p is null then
    return null;
  end if;
  n := normalize(p, NFKC);
  -- 대문자 모양이 같은 키릴/그리스 글자 -> 라틴 대문자 (소문자로 바꾸기 전에)
  n := pg_catalog.translate(n, E'\u0410\u0412\u0415\u041A\u041C\u041D\u041E\u0420\u0421\u0422\u0425\u0406\u0408\u0405\u0391\u0392\u0395\u0396\u0397\u0399\u039A\u039C\u039D\u039F\u03A1\u03A4\u03A5\u03A7', 'ABEKMHOPCTXIJSABEZHIKMNOPTYX');
  n := pg_catalog.lower(n);
  -- 공백류/보이지 않는 글자/결합 기호/구분 기호(_ - . / U+30FB U+2027 U+2022 U+318D)는 지운다
  n := pg_catalog.regexp_replace(n,
    '[\s\u00A0\u00AD\u034F\u115F\u1160\u17B4\u17B5\u180E\u2000-\u200F\u2028-\u202F\u205F-\u206F\u3000\u3164\uFEFF\uFFA0\u0300-\u036F_.\u00B7\u30FB\u2027\u2022\u318D-]', '', 'g');
  -- 소문자 모양이 같은 글자 -> 라틴 글자, 숫자/기호 -> 비슷한 글자 (i/I/1/| -> l, 0 -> o)
  n := pg_catalog.translate(n, E'\u0430\u0435\u043E\u0440\u0441\u0443\u0445\u0458\u0455\u0501\u04BB\u03BF\u03B1\u03BD\u03C1\u03C4\u03BA\u03C5\u0261\u0456\u03B9\u0131i1|0', 'aeopcyxjsdhoavptkugllllllo');
  n := pg_catalog.replace(n, 'rn', 'm');
  n := pg_catalog.replace(n, 'vv', 'w');
  return n;
end;
$$;
comment on function public.nickname_key(text) is E'닉네임 겹침 판정 열쇠 (046) \u2014 비슷한 글자를 같은 글자로. 화면에 보이는 값이 아니다';

-- 실행 전 중복 확인: 지금 닉네임끼리 열쇠가 겹치면 아무것도 바꾸지 않고 멈춘다
do $$
declare
  dup text;
begin
  select string_agg(format('[%s]', names), ' ') into dup
    from (select string_agg(nickname, ' / ' order by nickname) as names
            from public.profiles where nickname is not null
           group by public.nickname_key(nickname) having count(*) > 1) d;
  if dup is not null then
    raise exception '비슷한 닉네임이 겹쳐 046을 실행할 수 없습니다. 한쪽에 닉네임 변경을 부탁한 뒤 다시 실행해 주세요: %', dup;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. 프로필 칸 / 닉네임 인덱스 교체 / 닉네임 변경 기록 종류
-- ---------------------------------------------------------------------
alter table public.profiles
  add column influencer        text check (influencer in ('creator', 'pro', 'grandmaster')),
  add column influencer_at     timestamptz,
  add column nickname_state    text check (nickname_state in ('pending', 'yielding')),
  add column nickname_reset_at timestamptz,
  add column nickname_key      text generated always as (public.nickname_key(nickname)) stored,
  add constraint profiles_influencer_at check ((influencer is null) = (influencer_at is null)),
  add constraint profiles_nickname_reset_at check ((nickname_state is not distinct from 'yielding') = (nickname_reset_at is not null));
comment on column public.profiles.influencer is E'인증된 장인 유형 creator\u00B7pro\u00B7grandmaster (046). null = 장인 아님. 함수로만 바뀐다';
comment on column public.profiles.nickname_state is
  'pending = 장인 인증 대기(신청하며 희망 닉네임으로 바뀜), yielding = 장인과 같은 닉네임이라 nickname_reset_at에 임시 닉네임으로 바뀜 (046)';
comment on column public.profiles.nickname_key is '닉네임 겹침 판정 열쇠 (public.nickname_key, 046)';

drop index public.profiles_nickname_unique;
create unique index profiles_nickname_key_unique on public.profiles (nickname_key) where nickname_state is null;
create unique index profiles_nickname_key_pending on public.profiles (nickname_key) where nickname_state = 'pending';
create index profiles_nickname_yielding on public.profiles (nickname_reset_at) where nickname_state = 'yielding';
create index profiles_created_at on public.profiles (created_at desc, id desc);

alter table public.nickname_changes
  add column kind text not null default 'user' check (kind in ('user', 'apply', 'revert', 'reset', 'admin'));
comment on column public.nickname_changes.kind is
  E'user 본인 \u00B7 apply 장인 신청 \u00B7 revert 신청이 끝나 되돌림 \u00B7 reset 임시 닉네임 \u00B7 admin 운영자 (046). revert\u00B7reset\u00B7admin 뒤에는 30일 제한 없이 바꿀 수 있다';

-- ---------------------------------------------------------------------
-- 3. 닉네임 바꾸기 규칙 (본인이 바꿀 때) / 겹침 검사 / 사칭 금지
-- ---------------------------------------------------------------------
-- 시스템(장인 신청/되돌리기/임시 닉네임/운영자)이 바꿀 때는 system_set_nickname이 tl.nickname_system을 켜고 직접 기록한다
create or replace function public.keep_nickname()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  days integer := public.xp_rule('nickname_change_days');
  last_kind text;
  last_at timestamptz;
begin
  if old.nickname is not null and new.nickname is null then
    raise exception '닉네임은 비울 수 없습니다.' using errcode = '23514';
  end if;
  if old.nickname is null or new.nickname is not distinct from old.nickname then
    return new;  -- 처음 정하기 / 닉네임은 그대로 (대표 칭호만 바꿈 등)
  end if;
  if coalesce(current_setting('tl.nickname_system', true), '') = 'on' then
    return new;  -- 시스템이 바꿈 (기록은 system_set_nickname이)
  end if;
  if old.influencer is not null then
    raise exception '인증된 장인은 닉네임을 직접 바꿀 수 없습니다. 바꾸려면 [문의하기]로 운영자에게 알려 주세요.' using errcode = '42501';
  end if;
  if old.nickname_state = 'pending' then
    raise exception '장인 인증 신청을 심사하는 동안에는 닉네임을 바꿀 수 없습니다. 신청을 취소하면 바꿀 수 있습니다.' using errcode = '42501';
  end if;
  if old.nickname_state = 'yielding' then
    -- 장인과 같은 닉네임이라 바뀔 예정인 사람: 기다리지 않고 바로 새 닉네임을 정할 수 있다
    new.nickname_state := null;
    new.nickname_reset_at := null;
  else
    select c.kind into last_kind from public.nickname_changes c where c.user_id = old.id order by c.changed_at desc, c.id desc limit 1;
    if last_kind is null or last_kind in ('user', 'apply') then
      select max(changed_at) into last_at from public.nickname_changes where user_id = old.id and kind in ('user', 'apply');
      if last_at is not null and now() < last_at + make_interval(days => days) then
        raise exception '닉네임은 %일에 한 번 바꿀 수 있습니다. %부터 다시 바꿀 수 있습니다.', days,
          to_char((last_at + make_interval(days => days)) at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI')
          using errcode = 'P0001';
      end if;
    end if;
  end if;
  insert into public.nickname_changes (user_id, old_nickname, new_nickname, kind) values (old.id, old.nickname, new.nickname, 'user');
  return new;
end;
$$;

-- 비슷한 닉네임 겹침: 인증 대기/변경 예정인 사람의 닉네임도 새로 못 가져간다 (인덱스는 보통 닉네임끼리만 막으므로)
create function public.check_nickname_key()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  k text := public.nickname_key(new.nickname);
begin
  if new.nickname is null or (tg_op = 'UPDATE' and new.nickname is not distinct from old.nickname)
     or coalesce(current_setting('tl.nickname_system', true), '') = 'on' then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('nickname_key:' || k));
  if exists (select 1 from public.profiles p where p.nickname_key = k and p.id <> new.id) then
    raise exception '이미 사용 중인 닉네임입니다. 비슷한 닉네임도 쓸 수 없습니다.' using errcode = '23505';
  end if;
  return new;
end;
$$;
create trigger profiles_nickname_key before insert or update of nickname on public.profiles
  for each row execute function public.check_nickname_key();

-- "장인" 표시 흉내: [장인]/(장인) (괄호 모양/띄어쓰기/보이지 않는 글자 변형 포함), "장인 "으로 시작 (구분 기호 포함)
create function public.nickname_mimics_influencer(p text)
returns boolean language plpgsql immutable set search_path = ''
as $$
declare
  n text := normalize(coalesce(p, ''), NFKC);
  open_chars constant text := E'[{<\u3014\u3010\u3008\u300A\u300C\u300E\u3016\uFE59\u207D\u208D\u2768\u276A\u276C\u276E\u2770\u2772\u2774\u27E6\u27E8\u27EA\u27EC\u2985\u3018\u301A\uFE5B\uFE5D\uFF1C';
  close_chars constant text := E']}>\u3015\u3011\u3009\u300B\u300D\u300F\u3017\uFE5A\u207E\u208E\u2769\u276B\u276D\u276F\u2771\u2773\u2775\u27E7\u27E9\u27EB\u27ED\u2986\u3019\u301B\uFE5C\uFE5E\uFF1E';
  m text;
begin
  n := pg_catalog.regexp_replace(n, '[\u00AD\u034F\u115F\u1160\u17B4\u17B5\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\u3164\uFEFF\uFFA0\u0300-\u036F]', '', 'g');
  n := pg_catalog.btrim(pg_catalog.regexp_replace(n, '[\s\u00A0\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+', ' ', 'g'));
  if n ~ E'^장인[ _|\u00B7.:/~-]' then
    return true;
  end if;
  m := pg_catalog.regexp_replace(n, ' ', '', 'g');
  m := pg_catalog.translate(m, open_chars, pg_catalog.repeat('(', pg_catalog.char_length(open_chars)));
  m := pg_catalog.translate(m, close_chars, pg_catalog.repeat(')', pg_catalog.char_length(close_chars)));
  return m ~ '\(장인\)';
end;
$$;

-- 029의 (운)/(감) 검사 그대로 + 장인 흉내
create or replace function public.check_nickname_reserved()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.nickname is not null
     and (tg_op = 'INSERT' or new.nickname is distinct from old.nickname) then
    if public.nickname_reserved(new.nickname) then
      raise exception E'닉네임에는 (운)\u00B7(감)을 쓸 수 없습니다.' using errcode = '23514';
    end if;
    if public.nickname_mimics_influencer(new.nickname) then
      raise exception E'닉네임에는 [장인]\u00B7(장인)을 쓸 수 없고, "장인 "으로 시작할 수 없습니다.' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- 시스템이 닉네임/상태를 함께 바꾼다 (본인 규칙/겹침 트리거를 건너뛰고, 변경 기록은 여기서 kind와 함께)
create function public.system_set_nickname(p_user uuid, p_nickname text, p_state text, p_reset_at timestamptz, p_kind text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  old_name text;
begin
  select nickname into old_name from public.profiles where id = p_user for update;
  perform set_config('tl.nickname_system', 'on', true);
  update public.profiles
     set nickname = p_nickname, nickname_state = p_state, nickname_reset_at = p_reset_at
   where id = p_user;
  perform set_config('tl.nickname_system', '', true);
  if old_name is not null and p_nickname is distinct from old_name then
    insert into public.nickname_changes (user_id, old_nickname, new_nickname, kind) values (p_user, old_name, p_nickname, p_kind);
  end if;
end;
$$;

-- 임시 닉네임 탑신병자#xxxxxx (아무도 안 쓰는 것)
create function public.influencer_temp_nickname()
returns text language plpgsql volatile security definer set search_path = ''
as $$
declare
  cand text;
begin
  loop
    cand := '탑신병자#' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
    exit when not exists (select 1 from public.profiles where nickname_key = public.nickname_key(cand));
  end loop;
  return cand;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 신청 표
-- ---------------------------------------------------------------------
create table public.influencer_applications (
  id                   bigint generated always as identity primary key,
  user_id              uuid references public.profiles (id) on delete set null,  -- 탈퇴하면 비우고 상태 withdrawn (트리거)
  kind                 text not null check (kind in ('creator', 'pro', 'grandmaster')),
  nickname             text not null check (nickname = btrim(nickname) and char_length(nickname) between 1 and 20),  -- 희망 닉네임
  old_nickname         text,                                                      -- 신청 직전 닉네임 (되돌리기용)
  channel_url          text check (channel_url is null or (char_length(channel_url) <= 300 and channel_url ~* '^https?://[^\s/]+\.[^\s]+$')),
  channel_key          text,                                                      -- 겹침 판정용 (scheme/www/m./쿼리/끝 / 뺀 소문자)
  official_email       text check (official_email is null or (char_length(official_email) <= 254 and official_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  riot_id              text check (riot_id is null or char_length(riot_id) <= 30),  -- 라이엇 닉네임#태그 (심사 중에만)
  riot_key             text,                                                      -- sha256(정규화한 닉네임#태그) - 처리 전/승인된 동안만
  opgg_url             text check (opgg_url is null or (char_length(opgg_url) <= 300 and opgg_url ~* '^https?://([a-z0-9-]+\.)*op\.gg(/\S*)?$')),
  status               text not null default 'pending'
                       check (status in ('pending', 'approved', 'rejected', 'expired', 'cancelled', 'withdrawn', 'revoked')),
  created_at           timestamptz not null default now(),
  expires_at           timestamptz not null,
  extended_count       integer not null default 0 check (extended_count >= 0),
  expiring_notified_at timestamptz,                                               -- 만료 전 알림을 보낸 때 (한 번만)
  ended_at             timestamptz,                                               -- 승인/반려/만료/취소/탈퇴된 때
  reviewed_by          uuid references public.profiles (id) on delete set null,   -- 승인/반려한 운영자
  review_note          text check (review_note is null or char_length(review_note) between 1 and 500),
  retry_now            boolean not null default false,                            -- 반려하며 [바로 다시 신청 허용]
  nickname_reverted    text,                                                      -- 끝나며 되돌린 닉네임 (안 되돌렸으면 null)
  revoked_at           timestamptz,
  revoke_note          text check (revoke_note is null or char_length(revoke_note) between 1 and 500),
  constraint influencer_applications_fields check (
    case when kind in ('creator', 'pro')
         then channel_url is not null and channel_key is not null and riot_id is null and riot_key is null and opgg_url is null
              and (status <> 'pending' or official_email is not null)
         else official_email is null and channel_url is null and channel_key is null and opgg_url is not null
              and (status <> 'pending' or (riot_id is not null and riot_key is not null))
    end),
  constraint influencer_applications_private check (status = 'pending' or (official_email is null and riot_id is null)),
  constraint influencer_applications_riot_key check (riot_key is null or status in ('pending', 'approved')),
  constraint influencer_applications_ended check ((status = 'pending') = (ended_at is null)),
  constraint influencer_applications_revoked check ((status = 'revoked') = (revoked_at is not null))
);
create unique index influencer_applications_one_pending on public.influencer_applications (user_id) where status = 'pending';
create unique index influencer_applications_one_approved on public.influencer_applications (user_id) where status = 'approved';
create unique index influencer_applications_channel on public.influencer_applications (channel_key) where status in ('pending', 'approved');
create unique index influencer_applications_riot on public.influencer_applications (riot_key) where status in ('pending', 'approved');
create index influencer_applications_user on public.influencer_applications (user_id, created_at desc);
create index influencer_applications_open on public.influencer_applications (expires_at) where status = 'pending';
create index influencer_applications_ended on public.influencer_applications (ended_at) where status <> 'pending';
comment on table public.influencer_applications is
  E'장인 인증 신청 (046). 쓰기는 함수로만. 공식 이메일\u00B7라이엇 닉네임#태그는 심사가 끝나면 지움. 읽기: 본인\u00B7운영자(감독관 제외)';

alter table public.influencer_applications enable row level security;
revoke all on public.influencer_applications from anon, authenticated;
grant select on public.influencer_applications to authenticated;
create policy "influencer_applications: 본인과 운영자 읽기" on public.influencer_applications
  for select using (user_id = (select auth.uid()) or public.is_admin());

-- 개인정보 지우기: 심사가 끝나면(승인/반려/만료/취소/탈퇴/해제) 공식 이메일/라이엇 닉네임#태그를 바로 비운다.
-- 탈퇴(user_id가 비워짐)면 상태를 withdrawn으로. 승인된 (b)의 겹침 해시는 승인 동안만 남긴다.
create function public.influencer_applications_clear_private()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.user_id is not null and new.user_id is null and new.status in ('pending', 'approved') then
    new.status := 'withdrawn';
    new.ended_at := coalesce(new.ended_at, now());
  end if;
  if new.status <> 'pending' then
    new.official_email := null;
    new.riot_id := null;
  end if;
  if new.status not in ('pending', 'approved') then
    new.riot_key := null;
  end if;
  return new;
end;
$$;
create trigger influencer_applications_clear_private before update on public.influencer_applications
  for each row execute function public.influencer_applications_clear_private();

-- ---------------------------------------------------------------------
-- 5. 처리 기록 종류 / 알림 종류 / 운영자 모드 / 푸시 묶음
-- ---------------------------------------------------------------------
alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action = any (array[
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report', 'dismiss_report',
  'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member'  -- 046
]));
alter table public.moderation_log drop constraint moderation_log_target_kind_check;
alter table public.moderation_log add constraint moderation_log_target_kind_check check (target_kind = any (array[
  'post', 'comment', 'doc_comment', 'proposal', 'user', 'inquiry', 'build', 'wiki_report',
  'influencer_application'  -- 046
]));

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
  'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
  'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
  'matchup_created', 'build_created',
  'post_deleted', 'comment_deleted', 'doc_comment_deleted',
  'post_created',
  'error_reported', 'error_report_handled',
  'report_received',
  -- 046 장인 인증
  'influencer_applied', 'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
  'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed'
]));

drop policy "notifications: 본인 읽기" on public.notifications;
create policy "notifications: 본인 읽기" on public.notifications
  for select using (
    user_id = (select auth.uid())
    and not (kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                      'error_reported', 'report_received', 'influencer_applied')
             and public.operator_mode_off())
  );

do $$
declare
  f oid := 'public.mark_all_notifications_read'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
    $s$'error_reported', 'report_received')$s$,
    $s$'error_reported', 'report_received', 'influencer_applied')$s$);
  if new_def = old_def then
    raise exception 'mark_all_notifications_read에서 바꿀 부분을 찾지 못했습니다. (정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored',
                    'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
                    'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed') then 'my_results'
  end;
$$;

-- ---------------------------------------------------------------------
-- 6. 도우미
-- ---------------------------------------------------------------------
create function public.influencer_kind_label(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case p_kind when 'creator' then '크리에이터' when 'pro' then '프로게이머' when 'grandmaster' then '그랜드마스터 이상' else p_kind end;
$$;

-- 채널 주소 겹침 판정: scheme/www./m./쿼리/조각/끝의 / 를 빼고 소문자
create function public.influencer_channel_key(p_url text)
returns text language sql immutable set search_path = ''
as $$
  select nullif(pg_catalog.regexp_replace(
           pg_catalog.regexp_replace(
             pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.btrim(p_url)), '^https?://(www\.|m\.)?', ''),
             '[?#].*$', ''),
           '/+$', ''), '');
$$;

-- 라이엇 닉네임#태그 겹침 판정 (원문은 남기지 않으므로 해시): NFKC/소문자/공백 제거 뒤 sha256
create function public.influencer_riot_key(p_riot text)
returns text language sql immutable set search_path = ''
as $$
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
           pg_catalog.regexp_replace(pg_catalog.lower(normalize(p_riot, NFKC)), '[\s\u00A0\u3000]', '', 'g'), 'UTF8')), 'hex');
$$;

-- 다시 신청할 수 있는 때 (지금 신청 가능하면 null)
--  / 가입 뒤 influencer_min_account_days
--  / 운영자 반려 뒤 influencer_retry_days ([바로 다시 신청 허용] 반려 제외)
--  / influencer_reject_window_days 안에 운영자 반려가 influencer_reject_limit번 -> 그 마지막 반려부터 influencer_ban_days
create function public.influencer_next_apply_at(p_user uuid)
returns timestamptz language plpgsql stable security definer set search_path = ''
as $$
declare
  t timestamptz;
  win interval := make_interval(days => coalesce(public.xp_rule('influencer_reject_window_days'), 180));
  lim integer := greatest(coalesce(public.xp_rule('influencer_reject_limit'), 3), 1);
  ban interval := make_interval(days => coalesce(public.xp_rule('influencer_ban_days'), 180));
begin
  select greatest(
    (select p.created_at + make_interval(days => coalesce(public.xp_rule('influencer_min_account_days'), 0))
       from public.profiles p where p.id = p_user),
    (select max(a.ended_at) + make_interval(days => coalesce(public.xp_rule('influencer_retry_days'), 7))
       from public.influencer_applications a where a.user_id = p_user and a.status = 'rejected' and not a.retry_now),
    (select max(r.ended_at) + ban
       from public.influencer_applications r
      where r.user_id = p_user and r.status = 'rejected' and not r.retry_now
        and (select count(*) from public.influencer_applications x
              where x.user_id = p_user and x.status = 'rejected' and not x.retry_now
                and x.ended_at > r.ended_at - win and x.ended_at <= r.ended_at) >= lim))
  into t;
  return case when t > now() then t end;
end;
$$;

-- 처리 전 신청을 끝낸다 (반려/만료/취소). 닉네임: 다른 사람과 겹쳐 있거나 p_revert면 되돌림
--   (이전 닉네임을 아무도 안 쓰면 이전 것, 아니면 임시 닉네임). 돌려주는 값: 되돌린 닉네임 (안 되돌렸으면 null)
create function public.influencer_close(p_app bigint, p_status text, p_note text, p_revert boolean, p_retry_now boolean)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  a public.influencer_applications;
  me public.profiles;
  back text;
begin
  select * into a from public.influencer_applications where id = p_app for update;
  if not found or a.status <> 'pending' then
    raise exception '이미 처리된 신청입니다.' using errcode = 'TL409';
  end if;
  if a.user_id is not null then
    select * into me from public.profiles where id = a.user_id for update;
    perform pg_advisory_xact_lock(hashtext('nickname_key:' || me.nickname_key));
    if p_revert or exists (select 1 from public.profiles o where o.nickname_key = me.nickname_key and o.id <> me.id) then
      back := a.old_nickname;
      if back is null or exists (select 1 from public.profiles o where o.nickname_key = public.nickname_key(back) and o.id <> me.id) then
        back := public.influencer_temp_nickname();
      end if;
      perform public.system_set_nickname(me.id, back, null, null, 'revert');
      if back is not distinct from me.nickname then
        back := null;
      end if;
    elsif me.nickname_state = 'pending' then
      perform public.system_set_nickname(me.id, me.nickname, null, null, 'revert');
    end if;
  end if;
  update public.influencer_applications
     set status = p_status, ended_at = now(),
         reviewed_by = case when p_status = 'rejected' then (select auth.uid()) end,
         review_note = case when p_status = 'rejected' then p_note end,
         retry_now = coalesce(p_retry_now, false) and p_status = 'rejected',
         nickname_reverted = back
   where id = a.id;
  return back;
end;
$$;

-- 되돌린 닉네임 안내 한 문장 (알림 끝에 붙임)
create function public.influencer_reverted_sentence(p_name text)
returns text language sql immutable set search_path = ''
as $$
  select case when p_name is null then ''
              when p_name like '탑신병자#%' then format(E' 닉네임은 임시 닉네임 \u300C%s\u300D(으)로 바뀌었습니다. 새 닉네임을 정해 주세요.', p_name)
              else format(E' 닉네임은 신청 전 닉네임 \u300C%s\u300D(으)로 되돌렸습니다.', p_name) end;
$$;

-- ---------------------------------------------------------------------
-- 7. 신청자: 신청 / 취소 / 내 상태
-- ---------------------------------------------------------------------
create function public.apply_influencer(p_kind text, p_nickname text, p_channel_url text default null, p_email text default null,
                                        p_riot_id text default null, p_opgg_url text default null)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();  -- 로그인 + 닉네임
  prof public.profiles;
  nick text := btrim(coalesce(p_nickname, ''));
  k text;
  chan text := nullif(btrim(coalesce(p_channel_url, '')), '');
  mail text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  riot text := nullif(regexp_replace(btrim(coalesce(p_riot_id, '')), '\s*#\s*', '#'), '');
  opgg text := nullif(btrim(coalesce(p_opgg_url, '')), '');
  days integer := coalesce(public.xp_rule('influencer_review_days'), 14);
  next_at timestamptz;
  holder public.profiles;
  aid bigint;
begin
  select * into prof from public.profiles where id = me for update;
  if prof.is_guest then
    raise exception E'장인 인증은 구글\u00B7카카오로 로그인한 회원만 신청할 수 있습니다.' using errcode = '42501';
  end if;
  if prof.role = 'admin' then
    raise exception '운영자 계정은 장인 인증을 신청할 수 없습니다.' using errcode = '42501';
  end if;
  if prof.influencer is not null then
    raise exception '이미 인증된 장인입니다.' using errcode = '23514';
  end if;
  if exists (select 1 from public.influencer_applications where user_id = me and status = 'pending') then
    raise exception '이미 심사 중인 신청이 있습니다.' using errcode = '23514';
  end if;
  if prof.nickname_state = 'yielding' then
    raise exception '지금 닉네임은 바뀔 예정입니다. 먼저 새 닉네임을 정한 뒤 신청해 주세요.' using errcode = '23514';
  end if;
  next_at := public.influencer_next_apply_at(me);
  if next_at is not null then
    raise exception '장인 인증은 %부터 다시 신청할 수 있습니다.',
      to_char(next_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') using errcode = 'P0001';
  end if;
  if p_kind is null or p_kind not in ('creator', 'pro', 'grandmaster') then
    raise exception '유형을 골라 주세요.' using errcode = '22023';
  end if;
  if char_length(nick) not between 1 and 20 then
    raise exception '희망 닉네임은 1~20자로 적어 주세요.' using errcode = '22023';
  end if;

  if p_kind in ('creator', 'pro') then
    if chan is null or char_length(chan) > 300 or chan !~* '^https?://[^\s/]+\.[^\s]+$' then
      raise exception E'채널\u00B7방송 링크를 https://로 시작하는 주소로 적어 주세요.' using errcode = '22023';
    end if;
    if mail is null or char_length(mail) > 254 or mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception '공식 이메일을 적어 주세요. (채널 소개란이나 팀 공식 페이지에 공개된 이메일)' using errcode = '22023';
    end if;
    riot := null;
    opgg := null;
    if exists (select 1 from public.influencer_applications
                where channel_key = public.influencer_channel_key(chan) and status in ('pending', 'approved')) then
      raise exception '이미 신청됐거나 인증된 채널입니다. 본인의 채널이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
    end if;
  else
    if riot is null or riot !~ '^[^#]{3,16}#[^#\s]{3,5}$' then
      raise exception '라이엇 닉네임#태그를 적어 주세요. (예: 닉네임#KR1)' using errcode = '22023';
    end if;
    if opgg is null or char_length(opgg) > 300 or opgg !~* '^https?://([a-z0-9-]+\.)*op\.gg(/\S*)?$' then
      raise exception E'op.gg 링크를 적어 주세요. (https://op.gg/\u2026)' using errcode = '22023';
    end if;
    chan := null;
    mail := null;
    if exists (select 1 from public.influencer_applications
                where riot_key = public.influencer_riot_key(riot) and status in ('pending', 'approved')) then
      raise exception '이미 신청됐거나 인증된 라이엇 닉네임입니다. 본인의 계정이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
    end if;
  end if;

  -- 희망 닉네임: 다른 보통 회원 1명과만 겹칠 수 있다 (승인되면 그 회원이 3일 유예 뒤 임시 닉네임으로)
  k := public.nickname_key(nick);
  perform pg_advisory_xact_lock(hashtext('nickname_key:' || k));
  if exists (select 1 from public.profiles o where o.nickname_key = k and o.id <> me and o.nickname_state = 'pending') then
    raise exception '이미 장인 인증을 신청 중인 닉네임입니다. 본인의 닉네임이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
  end if;
  select * into holder from public.profiles o where o.nickname_key = k and o.id <> me limit 1;
  if found and (holder.influencer is not null or holder.nickname_state = 'yielding') then
    raise exception '이미 인증된 장인이 쓰는 닉네임입니다.' using errcode = '23505';
  end if;
  if found and holder.role <> 'user' then
    raise exception '운영진이 쓰는 닉네임이라 신청할 수 없습니다.' using errcode = '23505';
  end if;

  insert into public.influencer_applications
    (user_id, kind, nickname, old_nickname, channel_url, channel_key, official_email, riot_id, riot_key, opgg_url, expires_at)
  values (me, p_kind, nick, prof.nickname, chan, public.influencer_channel_key(chan), mail, riot,
          case when riot is not null then public.influencer_riot_key(riot) end, opgg, now() + make_interval(days => days))
  returning id into aid;

  -- 닉네임을 희망 닉네임으로 + 인증 대기 (사칭 금지 검사는 트리거가 그대로 한다)
  perform public.system_set_nickname(me, nick, 'pending', null, 'apply');

  -- 신청자에게 접수 알림 (본인 알림이라 notify()를 거치지 않음), 운영자에게 새 신청 알림
  insert into public.notifications (user_id, kind, message)
  values (me, 'influencer_received', case when p_kind = 'grandmaster'
    then format('신청이 접수됐습니다. %s일 안에 운영자 계정 {운영자 닉네임}으로 친구 요청을 보내 주세요. '
                '요청이 도착하면 이 닉네임의 주인이 맞는지 확인합니다. 수락은 하지 않습니다.', days)
    else format('신청이 접수됐습니다. 적어 주신 공식 이메일로 확인 메일을 보냅니다. %s일 안에 "본인입니다"라고 회신해 주세요.', days) end);
  insert into public.notifications (user_id, kind, message)
  select u.id, 'influencer_applied', format(E'장인 인증 신청이 들어왔습니다. (%s \u00B7 %s)', nick, public.influencer_kind_label(p_kind))
    from public.profiles u where u.role = 'admin' and u.id <> me;
  return aid;
end;
$$;

create function public.cancel_influencer_application(p_id bigint)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.influencer_applications where id = p_id and user_id = me) then
    raise exception '신청을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  return public.influencer_close(p_id, 'cancelled', null, false, false);
end;
$$;

-- 내 장인 상태: 마지막 신청(본인 것이라 심사 중이면 공식 이메일/라이엇 닉네임#태그 포함), 다시 신청할 수 있는 때
create function public.my_influencer_status()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  p public.profiles;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  select * into p from public.profiles where id = me;
  return jsonb_build_object(
    'influencer', p.influencer, 'influencer_at', p.influencer_at,
    'nickname_state', p.nickname_state, 'nickname_reset_at', p.nickname_reset_at,
    'is_guest', coalesce(p.is_guest, false),
    'next_apply_at', public.influencer_next_apply_at(me),
    'application', (
      select jsonb_build_object('id', a.id, 'kind', a.kind, 'nickname', a.nickname, 'old_nickname', a.old_nickname,
                                'channel_url', a.channel_url, 'official_email', a.official_email, 'riot_id', a.riot_id,
                                'opgg_url', a.opgg_url, 'status', a.status, 'created_at', a.created_at, 'expires_at', a.expires_at,
                                'ended_at', a.ended_at, 'review_note', a.review_note, 'retry_now', a.retry_now,
                                'nickname_reverted', a.nickname_reverted, 'revoked_at', a.revoked_at, 'revoke_note', a.revoke_note)
        from public.influencer_applications a where a.user_id = me order by a.created_at desc, a.id desc limit 1));
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 운영자: 목록 / 승인 / 반려 / 만료일 늘리기 / 인증 해제 / 닉네임 바꾸기
-- ---------------------------------------------------------------------
-- p_status: 'pending'(처리 전, 오래된 순) / 'done'(끝난 것, 최근 순)
create function public.admin_influencer_applications_unchecked(p_status text, p_page integer, p_size integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  st text := coalesce(p_status, 'pending');
  win interval := make_interval(days => coalesce(public.xp_rule('influencer_reject_window_days'), 180));
begin
  if st not in ('pending', 'done') then
    raise exception '목록 종류를 다시 골라 주세요.' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'total', (select count(*) from public.influencer_applications a where (a.status = 'pending') = (st = 'pending')),
    'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'kind', x.kind, 'kind_label', public.influencer_kind_label(x.kind),
               'nickname', x.nickname, 'old_nickname', x.old_nickname,
               'channel_url', x.channel_url, 'official_email', x.official_email, 'riot_id', x.riot_id, 'opgg_url', x.opgg_url,
               'status', x.status, 'created_at', x.created_at, 'expires_at', x.expires_at, 'extended_count', x.extended_count,
               'ended_at', x.ended_at, 'review_note', x.review_note, 'retry_now', x.retry_now,
               'nickname_reverted', x.nickname_reverted, 'revoked_at', x.revoked_at, 'revoke_note', x.revoke_note,
               'reviewer', (select r.nickname from public.profiles r where r.id = x.reviewed_by),
               'user', (select jsonb_build_object('id', u.id, 'nickname', u.nickname, 'role', u.role, 'level', u.level,
                                                  'main_title', u.main_title, 'is_guest', u.is_guest, 'created_at', u.created_at,
                                                  'influencer', u.influencer, 'nickname_state', u.nickname_state)
                          from public.profiles u where u.id = x.user_id),
               -- 처리 전: 같은 닉네임(비슷한 글자)을 지금 쓰는 다른 회원 - 승인하면 그 회원이 3일 뒤 임시 닉네임으로 바뀐다
               'overlap', case when x.status = 'pending' then (
                   select jsonb_build_object('id', o.id, 'nickname', o.nickname, 'role', o.role)
                     from public.profiles o join public.profiles me on me.id = x.user_id
                    where o.nickname_key = me.nickname_key and o.id <> me.id limit 1) end,
               'recent_rejections', (select count(*) from public.influencer_applications r
                                      where r.user_id = x.user_id and r.status = 'rejected' and not r.retry_now and r.ended_at > now() - win))
             order by x.ord1, x.ord2 desc nulls last, x.id)
      from (
        select a.*,
               case when st = 'pending' then extract(epoch from a.created_at) end as ord1,
               case when st = 'done' then coalesce(a.revoked_at, a.ended_at) end as ord2
          from public.influencer_applications a
         where (a.status = 'pending') = (st = 'pending')
         order by case when st = 'pending' then a.created_at end, coalesce(a.revoked_at, a.ended_at) desc nulls last, a.id
         limit sz offset (pg - 1) * sz
      ) x
    ), '[]'::jsonb));
end;
$$;

create function public.admin_influencer_applications(p_status text default 'pending', p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_influencer_applications_unchecked(p_status, p_page, p_size);
end;
$$;

create function public.approve_influencer_unchecked(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  a public.influencer_applications;
  u public.profiles;
  note text := nullif(btrim(coalesce(p_note, '')), '');
  grace integer := coalesce(public.xp_rule('influencer_nickname_grace_days'), 3);
  h record;
begin
  if note is null or char_length(note) > 500 then
    raise exception '승인 메모를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into a from public.influencer_applications where id = p_id for update;
  if not found then
    raise exception '신청을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if a.status <> 'pending' or a.user_id is null then
    raise exception '이미 처리된 신청입니다.' using errcode = 'TL409';
  end if;
  select * into u from public.profiles where id = a.user_id for update;
  perform pg_advisory_xact_lock(hashtext('nickname_key:' || u.nickname_key));
  if exists (select 1 from public.profiles o where o.nickname_key = u.nickname_key and o.id <> u.id
                and (o.role <> 'user' or o.influencer is not null or o.nickname_state is not null)) then
    raise exception E'같은 닉네임을 운영진\u00B7장인\u00B7다른 신청자가 쓰고 있어 승인할 수 없습니다. 반려하거나 닉네임을 정리해 주세요.' using errcode = '23505';
  end if;
  -- 같은 닉네임을 쓰던 보통 회원: 닉네임 변경 예정 (유예 뒤 임시 닉네임) + 미리 알림
  for h in select o.id from public.profiles o where o.nickname_key = u.nickname_key and o.id <> u.id for update loop
    update public.profiles set nickname_state = 'yielding', nickname_reset_at = now() + make_interval(days => grace) where id = h.id;
    perform public.notify(h.id, 'nickname_reset_soon',
      format('운영 원칙에 따라 %s일 뒤 닉네임이 임시 닉네임으로 바뀝니다. 그 전에 새 닉네임을 정해 주세요.', grace), null, null);
  end loop;
  update public.profiles set influencer = a.kind, influencer_at = now(), nickname_state = null, nickname_reset_at = null where id = u.id;
  update public.influencer_applications
     set status = 'approved', ended_at = now(), reviewed_by = (select auth.uid()), review_note = note
   where id = a.id;
  perform public.notify(u.id, 'influencer_approved', '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.', null, null);
  perform public.log_moderation('approve_influencer', 'influencer_application', a.id::text, note, u.nickname);
end;
$$;

create function public.approve_influencer(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.approve_influencer_unchecked(p_id, p_note);
end;
$$;

-- p_revert_nickname: 겹치지 않았어도 닉네임을 되돌림 / p_retry_now: 바로 다시 신청 허용 (7일 제한 없음, 3번에 안 셈)
create function public.reject_influencer_unchecked(p_id bigint, p_note text, p_revert_nickname boolean, p_retry_now boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  a public.influencer_applications;
  note text := nullif(btrim(coalesce(p_note, '')), '');
  back text;
  next_at timestamptz;
  tail text;
begin
  if note is null or char_length(note) > 500 then
    raise exception '반려 사유를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into a from public.influencer_applications where id = p_id;
  if not found then
    raise exception '신청을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  back := public.influencer_close(p_id, 'rejected', note, coalesce(p_revert_nickname, false), coalesce(p_retry_now, false));
  if a.user_id is not null then
    next_at := public.influencer_next_apply_at(a.user_id);
    tail := case
      when next_at is null then '바로 다시 신청할 수 있습니다.'
      when next_at <= now() + make_interval(days => coalesce(public.xp_rule('influencer_retry_days'), 7)) + interval '1 minute'
        then format('%s일 뒤 다시 신청할 수 있습니다.', coalesce(public.xp_rule('influencer_retry_days'), 7))
      else format('%s부터 다시 신청할 수 있습니다.', to_char(next_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI')) end;
    perform public.notify(a.user_id, 'influencer_rejected',
      format(E'장인 인증이 반려됐습니다. 사유: %s \u00B7 %s', note, tail) || public.influencer_reverted_sentence(back), null, null);
  end if;
  perform public.log_moderation('reject_influencer', 'influencer_application', a.id::text, note, a.nickname);
end;
$$;

create function public.reject_influencer(p_id bigint, p_note text, p_revert_nickname boolean default false, p_retry_now boolean default false)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.reject_influencer_unchecked(p_id, p_note, p_revert_nickname, p_retry_now);
end;
$$;

-- 만료일을 influencer_extend_days(7)일 늘린다. 돌려주는 값: 새 만료 시각
create function public.extend_influencer_application_unchecked(p_id bigint)
returns timestamptz language plpgsql security definer set search_path = ''
as $$
declare
  a public.influencer_applications;
  d integer := coalesce(public.xp_rule('influencer_extend_days'), 7);
begin
  select * into a from public.influencer_applications where id = p_id for update;
  if not found then
    raise exception '신청을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if a.status <> 'pending' then
    raise exception '이미 처리된 신청입니다.' using errcode = 'TL409';
  end if;
  update public.influencer_applications
     set expires_at = expires_at + make_interval(days => d), extended_count = extended_count + 1
   where id = a.id returning expires_at into a.expires_at;
  perform public.log_moderation('extend_influencer', 'influencer_application', a.id::text, format('만료일 +%s일', d), a.nickname);
  return a.expires_at;
end;
$$;

create function public.extend_influencer_application(p_id bigint)
returns timestamptz language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.extend_influencer_application_unchecked(p_id);
end;
$$;

-- 인증 해제: "장인" 표시만 없앤다 (닉네임은 그대로, 이제 본인이 바꿀 수 있음)
create function public.revoke_influencer_unchecked(p_user uuid, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  u public.profiles;
  note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if note is null or char_length(note) > 500 then
    raise exception '해제 사유를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into u from public.profiles where id = p_user for update;
  if not found or u.influencer is null then
    raise exception '인증된 장인이 아닙니다.' using errcode = 'P0002';
  end if;
  update public.profiles set influencer = null, influencer_at = null where id = u.id;
  update public.influencer_applications set status = 'revoked', revoked_at = now(), revoke_note = note
   where user_id = u.id and status = 'approved';
  perform public.notify(u.id, 'influencer_revoked', format('장인 인증이 해제됐습니다. 사유: %s', note), null, null);
  perform public.log_moderation('revoke_influencer', 'user', u.id::text, note, u.nickname);
end;
$$;

create function public.revoke_influencer(p_user uuid, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.revoke_influencer_unchecked(p_user, p_note);
end;
$$;

-- 운영자가 회원 닉네임을 바꾼다 (장인은 직접 못 바꾸므로). 비슷한 닉네임과 겹치면 거부, 사칭 금지 검사는 트리거가 그대로
create function public.admin_set_nickname_unchecked(p_user uuid, p_nickname text, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  u public.profiles;
  nick text := btrim(coalesce(p_nickname, ''));
  note text := nullif(btrim(coalesce(p_note, '')), '');
  k text;
begin
  if note is null or char_length(note) > 500 then
    raise exception '바꾸는 사유를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  if char_length(nick) not between 1 and 20 then
    raise exception '닉네임은 1~20자로 적어 주세요.' using errcode = '22023';
  end if;
  select * into u from public.profiles where id = p_user for update;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if u.role = 'admin' then
    raise exception '운영자 닉네임은 [계정 설정]에서 바꿔 주세요.' using errcode = '42501';
  end if;
  if u.nickname_state = 'pending' then
    raise exception '장인 인증 신청을 심사 중인 회원입니다. 신청을 먼저 처리해 주세요.' using errcode = '23514';
  end if;
  if nick = u.nickname then
    raise exception '지금 닉네임과 같습니다.' using errcode = '22023';
  end if;
  k := public.nickname_key(nick);
  perform pg_advisory_xact_lock(hashtext('nickname_key:' || k));
  if exists (select 1 from public.profiles o where o.nickname_key = k and o.id <> u.id) then
    raise exception '이미 사용 중인 닉네임입니다. 비슷한 닉네임도 쓸 수 없습니다.' using errcode = '23505';
  end if;
  perform public.system_set_nickname(u.id, nick, null, null, 'admin');
  perform public.log_moderation('rename_member', 'user', u.id::text, format(E'%s \u2192 %s \u00B7 %s', u.nickname, nick, note), nick);
end;
$$;

create function public.admin_set_nickname(p_user uuid, p_nickname text, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.admin_set_nickname_unchecked(p_user, p_nickname, p_note);
end;
$$;

-- ---------------------------------------------------------------------
-- 9. 하루 한 번 (pg_cron influencer-daily): 만료 / 만료 전 알림 / 임시 닉네임 / 1년 정리
-- ---------------------------------------------------------------------
create function public.influencer_daily()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  back text;
  n_expired integer := 0;
  n_warned integer := 0;
  n_reset integer := 0;
  n_purged integer := 0;
  warn_days integer := coalesce(public.xp_rule('influencer_expiring_days'), 3);
  left_days integer;
begin
  -- 1) 만료: 기한이 지난 처리 전 신청
  for r in select id, user_id, created_at, expires_at from public.influencer_applications
            where status = 'pending' and expires_at <= now() order by id loop
    back := public.influencer_close(r.id, 'expired', null, false, false);
    if r.user_id is not null then
      insert into public.notifications (user_id, kind, message)
      values (r.user_id, 'influencer_expired',
              format('%s일 안에 확인이 끝나지 않아 신청이 만료됐습니다. 다시 신청할 수 있습니다.',
                     round(extract(epoch from (r.expires_at - r.created_at)) / 86400)::integer)
              || public.influencer_reverted_sentence(back));
    end if;
    n_expired := n_expired + 1;
  end loop;

  -- 2) 만료 전 알림: 남은 기간이 warn_days 이하, 아직 안 보낸 신청만 (한 신청에 한 번)
  for r in select id, user_id, kind, expires_at from public.influencer_applications
            where status = 'pending' and expiring_notified_at is null and user_id is not null
              and expires_at <= now() + make_interval(days => warn_days) for update loop
    left_days := greatest(ceil(extract(epoch from (r.expires_at - now())) / 86400)::integer, 1);
    insert into public.notifications (user_id, kind, message)
    values (r.user_id, 'influencer_expiring', case when r.kind = 'grandmaster'
      then format('신청이 %s일 뒤 만료됩니다. 아직 친구 요청을 보내지 않았다면 {운영자 닉네임}으로 보내 주세요.', left_days)
      else format('신청이 %s일 뒤 만료됩니다. 확인 메일에 아직 회신하지 않았다면 만료되기 전에 회신해 주세요.', left_days) end);
    update public.influencer_applications set expiring_notified_at = now() where id = r.id;
    n_warned := n_warned + 1;
  end loop;

  -- 3) 유예가 끝난 "닉네임 변경 예정" 회원 -> 임시 닉네임
  for r in select id from public.profiles where nickname_state = 'yielding' and nickname_reset_at <= now() for update loop
    perform public.system_set_nickname(r.id, public.influencer_temp_nickname(), null, null, 'reset');
    insert into public.notifications (user_id, kind, message)
    values (r.id, 'nickname_reset', '운영 원칙에 따라 닉네임이 임시 닉네임으로 바뀌었습니다. 새 닉네임을 정해 주세요.');
    n_reset := n_reset + 1;
  end loop;

  -- 4) 끝난 지 influencer_keep_days(365)일 지난 신청 정리 (처리 전/승인 중인 것은 남김)
  delete from public.influencer_applications
   where status not in ('pending', 'approved')
     and coalesce(revoked_at, ended_at) < now() - make_interval(days => coalesce(public.xp_rule('influencer_keep_days'), 365));
  get diagnostics n_purged = row_count;

  return jsonb_build_object('expired', n_expired, 'expiring_notified', n_warned, 'nickname_reset', n_reset, 'purged', n_purged);
end;
$$;

-- ---------------------------------------------------------------------
-- 10. 처리 대기 건수에 장인 신청 (운영자만, 감독관 0)
-- ---------------------------------------------------------------------
create or replace function public.admin_pending_counts()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  perform public.require_staff();
  if public.is_admin() then
    return jsonb_build_object(
      'proposals', (select count(*) from public.edit_proposals where status = 'pending'),
      'builds', (select count(*) from public.builds where status = 'pending'),
      'inquiries', (select count(*) from public.inquiries where answer is null and user_id <> me),
      'wiki_reports', (select count(*) from public.wiki_reports where status = 'open'),
      'influencers', (select count(*) from public.influencer_applications where status = 'pending'));
  end if;
  return jsonb_build_object(
    'proposals', (select count(*) from public.edit_proposals
                   where status = 'pending' and type = 'new_counter' and counter_id is null
                     and proposer_id <> me and public.moderatable_author(proposer_id)),
    'builds', 0,
    'inquiries', (select count(*) from public.inquiries where answer is null and user_id <> me and category <> 'account'),
    'wiki_reports', (select count(*) from public.wiki_reports where status = 'open' and reporter_id is distinct from me),
    'influencers', 0);
end;
$$;

-- ---------------------------------------------------------------------
-- 11. 회원 관리: 신규 가입자 (운영자 전용, 정식 회원만)
-- ---------------------------------------------------------------------
-- p_hours: 최근 몇 시간 안에 가입한 사람 (1~720, 기본 24) - 보여 주는 기간일 뿐 지우지 않는다.
-- 돌려주는 값: { total, hours, page, size, members: [{ id, nickname, created_at, providers, role }] } - 이메일/로그인 ID 없음
create function public.admin_new_members_unchecked(p_hours integer, p_page integer, p_size integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  hrs integer := least(greatest(coalesce(p_hours, 24), 1), 720);
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  since timestamptz := now() - make_interval(hours => hrs);
begin
  return jsonb_build_object(
    'total', (select count(*) from public.profiles p where not p.is_guest and p.created_at >= since),
    'hours', hrs, 'page', pg, 'size', sz,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'nickname', x.nickname, 'created_at', x.created_at, 'role', x.role,
               -- 가입 방식: provider 이름만 (구글/카카오). 로그인 ID/이메일은 읽지 않는다
               'providers', coalesce((
                 select jsonb_agg(s.provider order by s.provider)
                   from (select distinct i.provider from auth.identities i where i.user_id = x.id and i.provider in ('google', 'kakao')) s
               ), '[]'::jsonb))
             order by x.created_at desc, x.id desc)
      from (
        select p.id, p.nickname, p.created_at, p.role
          from public.profiles p
         where not p.is_guest and p.created_at >= since
         order by p.created_at desc, p.id desc
         limit sz offset (pg - 1) * sz
      ) x
    ), '[]'::jsonb));
end;
$$;

create function public.admin_new_members(p_hours integer default 24, p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_new_members_unchecked(p_hours, p_page, p_size);
end;
$$;

-- ---------------------------------------------------------------------
-- 12. 사람 json 칸에 장인 유형/닉네임 상태 / 장인 빌드 라벨용 기여자 수
-- ---------------------------------------------------------------------
do $$
declare
  spec record;
  old_def text;
  new_def text;
  n integer;
begin
  for spec in
    select * from (values
      ('public.build_contributors(bigint)', 2, null::text, null::text),
      ('public.admin_build_revisions_unchecked(bigint, bigint, integer)', 2, null, null),
      ('public.board_page(text, integer, integer)', 1, null, null),
      ('public.open_reports_for_moderator()', 1, null, null),
      ('public.admin_member_info(uuid)', 1, null, null),
      ('public.admin_member_list_unchecked(text, text, integer, integer)', 1,
         'select p.id, p.nickname, p.role, p.level, p.main_title, p.is_guest, p.created_at',
         'select p.id, p.nickname, p.role, p.level, p.main_title, p.is_guest, p.created_at, p.influencer, p.nickname_state'),
      ('public.admin_search_members(text)', 1,
         'select id, nickname, role, level, main_title, is_guest, created_at',
         'select id, nickname, role, level, main_title, is_guest, created_at, influencer, nickname_state')
    ) v (fn, expected, sel_old, sel_new)
  loop
    if to_regprocedure(spec.fn) is null then
      raise exception '함수 %를 찾지 못했습니다.', spec.fn;
    end if;
    old_def := pg_get_functiondef(to_regprocedure(spec.fn));
    select count(*) into n from regexp_matches(old_def, '''main_title'', (\w+\.)?main_title', 'g');
    if n <> spec.expected then
      raise exception '%: 사람 json 자리를 %곳 기대했는데 %곳입니다. (정의가 달라졌습니다)', spec.fn, spec.expected, n;
    end if;
    new_def := regexp_replace(old_def, '''main_title'', (\w+\.)?main_title',
                              '''main_title'', \1main_title, ''influencer'', \1influencer, ''nickname_state'', \1nickname_state', 'g');
    if spec.sel_old is not null then
      if position(spec.sel_old in new_def) = 0 then
        raise exception '%: 고칠 select 목록을 찾지 못했습니다.', spec.fn;
      end if;
      new_def := replace(new_def, spec.sel_old, spec.sel_new);
    end if;
    execute new_def;
  end loop;
end $$;

-- 상대법의 빌드마다 시초를 뺀 기여자 수 {"빌드 id": 수} - 장인 빌드 라벨 "이후 N명이 수정했습니다" (build_contributors와 같은 기준/같은 공개 범위)
create function public.build_editor_counts(p_counter bigint)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_object_agg(b.id::text, (
           select count(*) from public.build_editors e where e.build_id = b.id and e.user_id is distinct from b.author_id)), '{}'::jsonb)
    from public.builds b join public.counters c on c.id = b.counter_id
   where b.counter_id = p_counter
     and (public.is_admin() or (b.status = 'approved' and c.status = 'approved'));
$$;

-- ---------------------------------------------------------------------
-- 13. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.check_nickname_key() from public, anon, authenticated;
revoke execute on function public.nickname_mimics_influencer(text) from public, anon, authenticated;
revoke execute on function public.system_set_nickname(uuid, text, text, timestamptz, text) from public, anon, authenticated;
revoke execute on function public.influencer_temp_nickname() from public, anon, authenticated;
revoke execute on function public.influencer_applications_clear_private() from public, anon, authenticated;
revoke execute on function public.influencer_kind_label(text) from public, anon, authenticated;
revoke execute on function public.influencer_channel_key(text) from public, anon, authenticated;
revoke execute on function public.influencer_riot_key(text) from public, anon, authenticated;
revoke execute on function public.influencer_next_apply_at(uuid) from public, anon, authenticated;
revoke execute on function public.influencer_close(bigint, text, text, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.influencer_reverted_sentence(text) from public, anon, authenticated;
revoke execute on function public.influencer_daily() from public, anon, authenticated;
revoke execute on function public.admin_influencer_applications_unchecked(text, integer, integer) from public, anon, authenticated;
revoke execute on function public.approve_influencer_unchecked(bigint, text) from public, anon, authenticated;
revoke execute on function public.reject_influencer_unchecked(bigint, text, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.extend_influencer_application_unchecked(bigint) from public, anon, authenticated;
revoke execute on function public.revoke_influencer_unchecked(uuid, text) from public, anon, authenticated;
revoke execute on function public.admin_set_nickname_unchecked(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.admin_new_members_unchecked(integer, integer, integer) from public, anon, authenticated;
-- nickname_key는 profiles 생성 칸이 쓰므로(회원이 닉네임을 바꿀 때 그 권한으로 계산) 실행 권한을 그대로 둔다 - 읽기만 하는 함수

revoke execute on function public.apply_influencer(text, text, text, text, text, text) from public, anon;
revoke execute on function public.cancel_influencer_application(bigint) from public, anon;
revoke execute on function public.my_influencer_status() from public, anon;
revoke execute on function public.admin_influencer_applications(text, integer, integer) from public, anon;
revoke execute on function public.approve_influencer(bigint, text) from public, anon;
revoke execute on function public.reject_influencer(bigint, text, boolean, boolean) from public, anon;
revoke execute on function public.extend_influencer_application(bigint) from public, anon;
revoke execute on function public.revoke_influencer(uuid, text) from public, anon;
revoke execute on function public.admin_set_nickname(uuid, text, text) from public, anon;
revoke execute on function public.admin_new_members(integer, integer, integer) from public, anon;
grant execute on function public.apply_influencer(text, text, text, text, text, text) to authenticated;  -- 정식 회원인지는 함수 안에서
grant execute on function public.cancel_influencer_application(bigint) to authenticated;
grant execute on function public.my_influencer_status() to authenticated;
grant execute on function public.admin_influencer_applications(text, integer, integer) to authenticated;  -- 운영자인지는 함수 안에서
grant execute on function public.approve_influencer(bigint, text) to authenticated;
grant execute on function public.reject_influencer(bigint, text, boolean, boolean) to authenticated;
grant execute on function public.extend_influencer_application(bigint) to authenticated;
grant execute on function public.revoke_influencer(uuid, text) to authenticated;
grant execute on function public.admin_set_nickname(uuid, text, text) to authenticated;
grant execute on function public.admin_new_members(integer, integer, integer) to authenticated;
grant execute on function public.build_editor_counts(bigint) to anon, authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_influencer.sql
