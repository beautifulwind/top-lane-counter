-- =====================================================================
-- 034(제안자 알림 보강 + 운영자 모드 켜기/끄기) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 034 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
--
-- 사이트에서 눈으로 확인할 것 (034 실행 + 새 코드 push 뒤):
--  1) 운영자 계정 → 마이페이지 → [계정 설정] 맨 위 "운영자 모드  지금 켜짐" → [운영자 모드 끄기]
--     → ☰ 메뉴에 [관리]가 없고, /admin 주소로 가면 "운영자만 볼 수 있습니다."
--     → [알림]에 "새 … 제안이 들어왔습니다" 같은 운영진 알림이 안 보임
--  2) 끈 채로 문서 수정 제안을 하나 낸다 → 마이페이지 [내 제안]에 "승인 대기"
--  3) 같은 [계정 설정]에서 [운영자 모드 켜기] → [관리]·운영진 알림이 돌아오고, 2)의 제안을 처리할 수 있다
--     (자기 제안을 처리하면 본인에게는 승인·반려 알림이 가지 않는다)
--  4) 숨긴 카운터를 [다시 공개] → 그 카운터를 제안한 회원의 [알림]에 "숨겨졌던 내 카운터가 다시 공개됐습니다"
-- 이 표의 "운영자 모드" 줄이 false로 남아 있으면, 사이트에서 [운영자 모드 켜기]를 누르면 된다.
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc, p.pronargs from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('is_admin', 'is_staff', 'operator_mode_off', 'set_operator_mode', 'mark_all_notifications_read', 'request_revision', 'restore_counter', 'notify_staff')
), col as (
  select column_name, data_type, is_nullable, column_default from information_schema.columns
  where table_schema = 'public' and table_name = 'profiles' and column_name = 'operator_mode'
), kinds as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
), pol as (
  select qual from pg_policies where schemaname = 'public' and tablename = 'notifications' and policyname = 'notifications: 본인 읽기'
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '033 실행됨 (034의 전제: 운영진 알림 함수 notify_staff)' as what,
    (exists (select 1 from fn where proname = 'notify_staff'))::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, 'profiles.operator_mode 칸 (종류 · 빈 값 허용 · 기본값)',
    coalesce((select data_type || ' · ' || is_nullable || ' · ' || column_default from col), '칸 없음'), '칸 없음', 'boolean · NO · true'
  union all select 3, '운영자 계정의 운영자 모드 (실행 직후에는 켜짐 = true)',
    -- 칸 이름을 직접 쓰면 실행 전에는 오류가 나므로 행 전체(to_jsonb)에서 꺼낸다
    coalesce((select string_agg(coalesce(to_jsonb(p) ->> 'operator_mode', '칸 없음'), ', ') from public.profiles p where p.role = 'admin'), '운영자 없음'),
    '칸 없음', 'true'
  union all select 4, '운영자 계정 수 (1이어야 함)', (select count(*)::text from public.profiles where role = 'admin'), '1', '1'
  union all select 5, '일반 사용자가 operator_mode를 직접 고칠 수 있나 (false여야 함 — 함수로만 바뀜)',
    case when exists (select 1 from col) then has_column_privilege('authenticated', 'public.profiles', 'operator_mode', 'UPDATE')::text else '칸 없음' end, '칸 없음', 'false'
  union all select 6, '일반 사용자가 role을 직접 고칠 수 있나 (false여야 함, 원래 그대로)',
    has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')::text, 'false', 'false'
  union all select 7, 'is_admin()이 운영자 모드를 함께 보나',
    coalesce((select (prosrc like '%operator_mode%')::text from fn where proname = 'is_admin'), '함수 없음'), 'false', 'true'
  union all select 8, 'is_staff()가 운영자 모드를 함께 보나 (감독관은 그대로)',
    coalesce((select (prosrc like '%operator_mode%' and prosrc like '%moderator%')::text from fn where proname = 'is_staff'), '함수 없음'), 'false', 'true'
  union all select 9, '켜기/끄기 함수 set_operator_mode: 비로그인 호출 불가(false) / 로그인 호출 가능(true — 운영자인지는 함수 안에서 검사)',
    coalesce((select has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text from fn where proname = 'set_operator_mode'), '함수 없음'), '함수 없음', 'false / true'
  union all select 10, 'set_operator_mode가 "운영자 계정만" 검사를 하고 본인 행(auth.uid)만 바꾸나',
    coalesce((select (prosrc like '%운영자 계정만%' and prosrc like '%auth.uid()%' and prosrc like '%where id = me%')::text from fn where proname = 'set_operator_mode'), '함수 없음'), '함수 없음', 'true'
  union all select 11, '알림 읽기 정책: 모드를 끈 운영자에게 운영진 알림 숨김',
    coalesce((select (qual like '%operator_mode_off%')::text from pol), '정책 없음'), 'false', 'true'
  union all select 12, '[모두 읽음]이 숨긴 운영진 알림은 건드리지 않나',
    coalesce((select (prosrc like '%hide_staff%')::text from fn where proname = 'mark_all_notifications_read'), '함수 없음'), 'false', 'true'
  union all select 13, '알림 종류에 counter_restored 추가 (예전 종류도 그대로)',
    (select (def like '%counter_restored%')::text || ' / ' || (def like '%inquiry_received%' and def like '%revision_cancelled%' and def like '%moderator_granted%')::text from kinds), 'false / true', 'true / true'
  union all select 14, '숨긴 카운터 재검토 요청: 처리한 본인 제외 도우미(notify)로 보내나',
    coalesce((select (prosrc like '%public.notify(who, ''revision_request''%' and prosrc not like '%insert into public.notifications%')::text from fn where proname = 'request_revision'), '함수 없음'), 'false', 'true'
  union all select 15, '[다시 공개]: 제안자에게 counter_restored 알림',
    coalesce((select (prosrc like '%counter_restored%')::text from fn where proname = 'restore_counter'), '함수 없음'), 'false', 'true'
  union all select 16, '모드 판정 도우미 operator_mode_off 함수',
    (exists (select 1 from fn where proname = 'operator_mode_off'))::text, 'false', 'true'
  union all select 17, '기존 알림 수 (실행 전후 같아야 함)', (select count(*)::text from public.notifications), '-', '실행 전과 같음'
  union all select 18, '최근 7일 "다시 공개" 알림 수 (실행 뒤 [다시 공개]를 해 보면 늘어남)',
    (select count(*)::text from public.notifications where kind = 'counter_restored' and created_at > now() - interval '7 days'), '0', '-'
) x
order by ord;
