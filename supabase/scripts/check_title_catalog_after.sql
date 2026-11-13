-- =====================================================================
-- 053(칭호 도감) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 053을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~13번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 14~18번: 실행 전 check_title_catalog_before.sql의 10~14번에 적어 둔 값과 같아야 한다.
--     (053은 회원의 칭호와 대표 칭호를 바꾸지 않는다. 그 사이 사이트 사용으로 바뀌었을 수는 있다.)
-- =====================================================================
with fn as (
  select pg_get_functiondef('public.sync_rewards'::regproc) as src,
         '  for t in select title_key from public.user_titles where user_id = p_user and not (title_key = any (want)) loop'::text as old_line
),
con as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'moderation_log_action_check' and conrelid = 'public.moderation_log'::regclass
),
six as (
  select array['top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta'] as keys
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '도감 줄 수: 전체 / 활동 / 장인 / 한정판' as what,
    (select count(*)::text from public.title_catalog) || ' / '
      || (select count(*)::text from public.title_catalog where kind = 'activity') || ' / '
      || (select count(*)::text from public.title_catalog where kind = 'influencer') || ' / '
      || (select count(*)::text from public.title_catalog where kind = 'limited') as now_value,
    '7 / 6 / 1 / 0' as ok_value, '한정판은 나중에 INSERT로 추가' as memo
  union all select 2, '도감 순서와 이름',
    (select string_agg(key || '=' || name, ' / ' order by sort_order) from public.title_catalog),
    'top_addict=탑신병자 / tool_hater=도구혐오자 / solid_heavy=단단묵직 / butcher_owner=백정주인 / general=장군 / offmeta=비주류 / influencer=장인', ''
  union all select 3, '장착 가능한 칭호 수 (활동 6개만) / 그림이나 색이 있는 줄 수',
    (select count(*)::text from public.title_catalog where equippable) || ' / '
      || (select count(*)::text from public.title_catalog where icon is not null or color is not null),
    '6 / 0', '기존 6개는 모양 그대로'
  union all select 4, '표 RLS 켬 / 회원이 읽을 수 있음 / 비로그인이 읽을 수 있음',
    (select relrowsecurity::text from pg_class where oid = 'public.title_catalog'::regclass) || ' / '
      || has_table_privilege('authenticated', 'public.title_catalog', 'select')::text || ' / '
      || has_table_privilege('anon', 'public.title_catalog', 'select')::text,
    'true / false / false', '화면은 my_title_book()으로만 읽는다'
  union all select 5, '외래 키 user_titles -> title_catalog',
    exists (select 1 from pg_constraint where conname = 'user_titles_title_key_fkey' and conrelid = 'public.user_titles'::regclass)::text,
    'true', ''
  union all select 6, '트리거: 장인 칭호 줄 막기 / 대표 칭호는 장착 가능한 것만',
    exists (select 1 from pg_trigger where tgname = 'user_titles_kind_guard')::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'profiles_main_title_equippable')::text,
    'true / true', ''
  union all select 7, 'sync_rewards: 053 줄 있음 / 예전 회수 줄 남은 횟수',
    (select (src like '%053: 활동 칭호만 회수%')::text || ' / '
            || ((char_length(src) - char_length(replace(src, old_line, ''))) / char_length(old_line))::text from fn),
    'true / 0', '회수는 활동 칭호만'
  union all select 8, 'sync_rewards: 지급/알림 문장은 그대로',
    (select ((src like '%칭호 ''''%s''''%s 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.%')
             and (src like '%회수됐습니다. (승인 취소%'))::text from fn),
    'true', ''
  union all select 9, '칭호 이름 (title_name) 6개 + 장인',
    (select string_agg(public.title_name(k), ' / ' order by n) from six, unnest(six.keys) with ordinality u(k, n))
      || ' / ' || public.title_name('influencer'),
    '탑신병자 / 도구혐오자 / 단단묵직 / 백정주인 / 장군 / 비주류 / 장인', '실행 전 9번 + 장인'
  union all select 10, '회원이 부를 수 있음: my_title_book / grant_title / revoke_title',
    has_function_privilege('authenticated', 'public.my_title_book()', 'execute')::text || ' / '
      || has_function_privilege('authenticated', 'public.grant_title(uuid,text,text)', 'execute')::text || ' / '
      || has_function_privilege('authenticated', 'public.revoke_title(uuid,text,text)', 'execute')::text,
    'true / true / true', '지급/회수는 함수 안에서 운영자인지 확인'
  union all select 11, '비로그인이 부를 수 있음: my_title_book / grant_title / revoke_title / title_name',
    has_function_privilege('anon', 'public.my_title_book()', 'execute')::text || ' / '
      || has_function_privilege('anon', 'public.grant_title(uuid,text,text)', 'execute')::text || ' / '
      || has_function_privilege('anon', 'public.revoke_title(uuid,text,text)', 'execute')::text || ' / '
      || has_function_privilege('anon', 'public.title_name(text)', 'execute')::text,
    'false / false / false / false', ''
  union all select 12, '처리 기록 종류 grant_title / revoke_title / 있던 grant_influencer',
    (select (def like '%grant_title%')::text || ' / ' || (def like '%revoke_title%')::text || ' / ' || (def like '%grant_influencer%')::text from con),
    'true / true / true', ''
  union all select 13, '대표 칭호가 장착 불가 칭호인 회원 수 / 장인 칭호 줄 수',
    (select count(*)::text from public.profiles p join public.title_catalog c on c.key = p.main_title where not c.equippable) || ' / '
      || (select count(*)::text from public.user_titles t join public.title_catalog c on c.key = t.title_key where c.kind = 'influencer'),
    '0 / 0', ''
  union all select 14, '같아야 함 (실행 전 10번): 회원 칭호 줄 수', (select count(*)::text from public.user_titles),
    '(실행 전 10번과 같음)', ''
  union all select 15, '같아야 함 (실행 전 11번): 칭호별 줄 수',
    (select string_agg(k || '=' || (select count(*) from public.user_titles t where t.title_key = k), ' / ' order by n)
       from six, unnest(six.keys) with ordinality u(k, n)),
    '(실행 전 11번과 같음)', ''
  union all select 16, '같아야 함 (실행 전 12번): 대표 칭호를 고른 회원 수', (select count(*)::text from public.profiles where main_title is not null),
    '(실행 전 12번과 같음)', ''
  union all select 17, '같아야 함 (실행 전 13번): 칭호 얻은 회원 수', (select count(distinct user_id)::text from public.user_titles),
    '(실행 전 13번과 같음)', ''
  union all select 18, '같아야 함 (실행 전 14번): 처리 기록 수 / 칭호 알림 수',
    (select count(*)::text from public.moderation_log) || ' / '
      || (select count(*)::text from public.notifications where kind in ('title_earned', 'title_revoked')),
    '(실행 전 14번과 같음)', '사이트 사용으로는 늘 수 있음'
) rows
order by ord;
