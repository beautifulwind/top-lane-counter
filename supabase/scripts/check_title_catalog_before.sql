-- =====================================================================
-- 053(칭호 도감) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 053을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~9번: [지금 값]이 [정상 값]과 모두 맞으면 053을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 10~14번은 "적어 둘 값"이다. 053 실행 뒤 check_title_catalog_after.sql의 같은 이름 줄과 비교한다.
--     053은 회원의 칭호와 대표 칭호를 바꾸지 않으므로 실행 직후에는 같아야 한다
--     (그 사이 사이트에서 누가 글을 쓰거나 지우면 바뀔 수 있다 - 그때는 알려 주세요).
-- 053이 만드는 표/함수가 아직 없어도 오류 없이 돌도록 to_regclass/to_regprocedure만 쓴다.
-- =====================================================================
with fn as (
  select pg_get_functiondef('public.sync_rewards'::regproc) as src,
         '  for t in select title_key from public.user_titles where user_id = p_user and not (title_key = any (want)) loop'::text as target
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
  select 1 as ord, '052까지 실행됨 (센 기록 표 new_follower_counted)' as what,
    (to_regclass('public.new_follower_counted') is not null)::text as now_value, 'true' as ok_value, 'false면 052부터 실행' as memo
  union all select 2, '053 아직 안 함: 도감 표 title_catalog',
    (to_regclass('public.title_catalog') is not null)::text, 'false', 'true면 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '053 아직 안 함: 함수 my_title_book / grant_title / revoke_title',
    (to_regprocedure('public.my_title_book()') is not null)::text || ' / '
      || (to_regprocedure('public.grant_title(uuid,text,text)') is not null)::text || ' / '
      || (to_regprocedure('public.revoke_title(uuid,text,text)') is not null)::text,
    'false / false / false', ''
  union all select 4, '053 아직 안 함: 처리 기록 종류 grant_title / 있던 종류 grant_influencer',
    (select (def like '%grant_title%')::text || ' / ' || (def like '%grant_influencer%')::text from con),
    'false / true', ''
  union all select 5, '053이 바꿀 sync_rewards 회수 줄이 나온 횟수',
    (select ((char_length(src) - char_length(replace(src, target, ''))) / char_length(target))::text from fn),
    '1', '1이 아니면 053이 멈춘다 - 실행하지 말고 알려 주세요'
  union all select 6, '모르는 칭호 키를 가진 줄 수 (외래 키를 걸 수 있는지)',
    (select count(*)::text from public.user_titles, six where not (title_key = any (six.keys))),
    '0', '0이 아니면 053이 멈춘다'
  union all select 7, '대표 칭호인데 가진 칭호가 아닌 회원 수',
    (select count(*)::text from public.profiles p
      where p.main_title is not null
        and not exists (select 1 from public.user_titles t where t.user_id = p.id and t.title_key = p.main_title)),
    '0', '외래 키가 있어 늘 0'
  union all select 8, '운영자 계정이 가진 칭호 줄 수',
    (select count(*)::text from public.user_titles t join public.profiles p on p.id = t.user_id where p.role = 'admin'),
    '0', '운영자는 칭호가 없다'
  union all select 9, '지금 칭호 이름 (title_name)',
    (select string_agg(public.title_name(k), ' / ' order by n) from six, unnest(six.keys) with ordinality u(k, n)),
    '탑신병자 / 도구혐오자 / 단단묵직 / 백정주인 / 장군 / 비주류', ''
  union all select 10, '적어 둘 값: 회원 칭호 줄 수 (user_titles)', (select count(*)::text from public.user_titles),
    '(이 값을 적어 둠)', '053 뒤 같아야 함'
  union all select 11, '적어 둘 값: 칭호별 줄 수',
    (select string_agg(k || '=' || (select count(*) from public.user_titles t where t.title_key = k), ' / ' order by n)
       from six, unnest(six.keys) with ordinality u(k, n)),
    '(이 값을 적어 둠)', '053 뒤 같아야 함'
  union all select 12, '적어 둘 값: 대표 칭호를 고른 회원 수', (select count(*)::text from public.profiles where main_title is not null),
    '(이 값을 적어 둠)', '053 뒤 같아야 함'
  union all select 13, '적어 둘 값: 칭호 얻은 회원 수 (한 개 이상)', (select count(distinct user_id)::text from public.user_titles),
    '(이 값을 적어 둠)', '053 뒤 같아야 함'
  union all select 14, '적어 둘 값: 처리 기록 수 / 칭호 알림 수(얻음+회수)',
    (select count(*)::text from public.moderation_log) || ' / '
      || (select count(*)::text from public.notifications where kind in ('title_earned', 'title_revoked')),
    '(이 값을 적어 둠)', '053은 둘 다 늘리지 않는다 (사이트 사용으로는 늘 수 있음)'
) rows
order by ord;
