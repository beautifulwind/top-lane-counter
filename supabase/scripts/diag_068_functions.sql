-- 주의: 줄바꿈(CRLF)이 섞여 붙여 넣어진 DB에서는 함수 본문 지문이 파일 기준과 달라질 수 있다. 본문을 비교할 때는 CR(\r)을 뺀 값으로 보라(CR 개수 칸이 0보다 크면 이 경우).
-- =====================================================================
-- 068 뒤 진단 (읽기만 — 아무것도 바꾸지 않는다). check_restrictions_after.sql 23번이 실행 전 18번과 다를 때 쓴다.
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나(30줄)가 나온다. 0번 줄 = 29개 묶음 요약, 1~29번 = 함수 하나씩.
--
-- "기대" 값은 저장소(schema.sql + 마이그레이션 001~068을 차례로 실행한 로컬 DB)에서 계산해 이 파일에 적어 둔 것이다.
--   - 기대 본문 md5(검사 줄 뺌) = 001~067을 다 실행한 뒤의 본문과 같다(로컬에서 함수 29개 모두 확인).
--   - 기대 원본 md5 = 068 파일의 본문 그대로(검사 줄 포함).
--   - 기대 실행 권한 = 저장소의 revoke ... from public, anon / grant ... to authenticated.
-- 칸:
--   본문 같음      : 지금 본문에서 검사 줄을 뺀 md5 = 기대 (다르면 "다름")
--   원본 같음      : 검사 줄까지 포함한 본문 md5 = 068 파일 그대로 (붙여넣기 때 글자가 바뀌었는지)
--   검사 줄(정확히): check_restrictions_after.sql 23번이 지우는 줄과 글자까지 같은 줄이 있는지 (없으면 23번이 그 줄을 못 지워 지문이 달라짐)
--   검사 문장      : assert_can_write() 줄이 (주석이 조금 달라도) 있는지
--   CR 개수        : 본문 속 \r(윈도 줄바꿈) 수 — 저장소는 0
--   보안·search_path·anon·authenticated : 지금 / 기대
--   PUBLIC 실행    : 권한 목록에 PUBLIC(=X) 실행이 있는지 — 기대 없음
--   권한 원문      : proacl 그대로 (Supabase에는 service_role 등이 더 있을 수 있다 — 068은 이 함수들의 권한을 바꾸지 않는다)
-- =====================================================================
with expected(sig, body_md5, raw_md5, secdef, config, anon_x, auth_x) as (values
    ('apply_influencer(text, text, text, text, text, text)', '0ee667de5112dd5a24b0cb15aab8fb64', '4061723dda23b0ba61c934aee227bcd3', true, 'search_path=""', false, true),
    ('begin_edit(text, bigint)', '4e113574135e09f9a30322580b2a560a', '7b5c0a61dbeee2345c973cd949f446e8', true, 'search_path=""', false, true),
    ('create_build(bigint, jsonb)', 'c26a6027e7bb3889822e68bf84bcd986', '6a0a7806a00258f6be71ed8b0e63c93c', true, 'search_path=""', false, true),
    ('create_comment(bigint, text, text[], bigint)', '26bdc2911ae0ef5b01311ec419f439e2', '158cb89dd19c6c8aa806ac64e52c23d4', true, 'search_path=""', false, true),
    ('create_doc_comment(bigint, text, bigint)', 'a98a9aa3adcb5e0f2f91d495fe6b5238', '7573369a585c85508c587f2329229165', true, 'search_path=""', false, true),
    ('create_matchup(text, text, jsonb)', '08f6b834da613c7d2ca5b7d6b80af9b0', 'dee6039d02f122fe6dd6b6a65f727a8d', true, 'search_path=""', false, true),
    ('create_post(text, text, text[])', 'c7070b94972121e682f3d5a6fc550e71', 'f391e88e4b4165eb18c6f9e500afadee', true, 'search_path=""', false, true),
    ('edit_build(bigint, integer, jsonb)', 'e9c3f94df133a0771e5d428ed37a850e', '42a7574b2cff0d0c11a8c3c32b53b42c', true, 'search_path=""', false, true),
    ('edit_comment(bigint, text, text[])', '6cc61f0f4e173ce7c611b3e8fa30241d', '6bc43a542b2c5e3872f6b5d343b0a3c6', true, 'search_path=""', false, true),
    ('edit_doc_comment(bigint, text)', '5c0b2eb3553d35261afee6d7f54103ab', '79f1ed2ed119139289f45225e2c9a85a', true, 'search_path=""', false, true),
    ('edit_my_build(bigint, jsonb)', '5dc9850735829aab077005012cc4aedb', 'd1a4c0579fb1f4f8ce3f6a66621ad61a', true, 'search_path=""', false, true),
    ('edit_my_proposal(bigint, jsonb, jsonb)', '93811b0e407e04ddbca9a402c90cc103', '839723fb283f5ca3baaf239cdc65c238', true, 'search_path=""', false, true),
    ('edit_post(bigint, text, text, text[])', '5854671593c3c0d4d58cf478bfd61081', '17345701b24f072110ad84230bda3458', true, 'search_path=""', false, true),
    ('follow_influencer(uuid)', '09618198ac9da7f5d897ee5a0bc4b9f2', 'b16338d3dd1b963604277681856c3f54', true, 'search_path=""', false, true),
    ('report_comment(bigint, text, text)', '12246bfb1ec0d55d1450529911a77413', '07cec46235fb20f7b04b38879c00a987', true, 'search_path=""', false, true),
    ('report_doc_comment(bigint, text, text)', 'ff3d6bb5daa1fad83aea5400ca7e73b3', '30b3d802697f8d2f388058b593afc209', true, 'search_path=""', false, true),
    ('report_link(bigint, text, text)', '9cbc75560b25c2dbd69dd46bda5f4452', '95ebeb7a86d4ac63573397f171f31cf6', true, 'search_path=""', false, true),
    ('report_post(bigint, text, text)', '70994668ddb714d0addbc081735abf7a', 'e4732a864be1b58156b106e424a944dc', true, 'search_path=""', false, true),
    ('report_profile_photo(uuid, text, text)', 'dbaea0f12db76fc1e30022861a5e928f', '54134fc64dd34247067a2a52ad3e2eb9', true, 'search_path=""', false, true),
    ('report_wiki(bigint, bigint, text, text)', '6ca4d4ed2762ea0449c516d7b7c6f090', '10eab5fca3c501abfde6a6b8d842c167', true, 'search_path=""', false, true),
    ('resubmit_build(bigint, jsonb)', 'be4c397312b5ee9127a6a807c49d8e7b', '5b45b271505b8252d44004d2d0ec41bc', true, 'search_path=""', false, true),
    ('resubmit_proposal(bigint, jsonb, jsonb)', '99a85fac69a4502157d0bb180b6e6368', '160c9966be13180a46992b445d576495', true, 'search_path=""', false, true),
    ('save_build(bigint)', 'c50f37a67d0edc28e82cfab6b4f833df', '5f56b9580415d8596a2e033493d3e8c4', true, 'search_path=""', false, true),
    ('set_application_photo(text)', 'c2f256a5ac6b20872d1a89f10aa58f5b', '64b8b1f2d7551882298857e7d5d836fb', true, 'search_path=""', false, true),
    ('set_build_link(bigint, text)', '0228b90baa5153f9471e7622684f35fe', 'f83cc6f0a5b6e9277149240da22aa6e6', true, 'search_path=""', false, true),
    ('set_profile_links(text[])', '0fff15ba44aadf1f48d09fc41a9b1481', '1f693dc77017d5be5aa072c9fe1a17f1', true, 'search_path=""', false, true),
    ('set_profile_photo(text)', '58c6b4a2ecfa2085eaf266484fe1becb', '7d8df24df7561a97c9c8e98956d43655', true, 'search_path=""', false, true),
    ('vote_build(bigint, smallint)', '14d37a8678f5abee33408ae4584fd1e1', '705487943c086d1b8168566e377a566e', true, 'search_path=""', false, true),
    ('vote_post(bigint)', 'ed983397e852f5dc03edb256bee35cd0', '9506e7e15d983e5ceea3077d9f9ced85', true, 'search_path=""', false, true)
), cur as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.oid, p.prosrc, p.prosecdef, p.proacl, p.proowner,
         coalesce(array_to_string(p.proconfig, ','), '') as config
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('apply_influencer','begin_edit','create_build','create_comment','create_doc_comment','create_matchup','create_post','edit_build','edit_comment','edit_doc_comment','edit_my_build','edit_my_proposal','edit_post','follow_influencer','report_comment','report_doc_comment','report_link','report_post','report_profile_photo','report_wiki','resubmit_build','resubmit_proposal','save_build','set_application_photo','set_build_link','set_profile_links','set_profile_photo','vote_build','vote_post')
), j as (
  select coalesce(c.sig, e.sig) as fsig, c.oid, c.prosrc, c.prosecdef, c.proacl, c.proowner, c.config, e.body_md5 as e_body, e.raw_md5 as e_raw, e.secdef as e_secdef, e.config as e_config,
         e.anon_x as e_anon, e.auth_x as e_auth, c.sig is not null as in_db, e.sig is not null as in_repo
  from cur c full join expected e on e.sig = c.sig
)
select 0 as "번호", '29개 묶음 (권한 빼고)' as "함수",
  (select count(*) from cur) || ' / ' || (select md5(string_agg(sig || replace(prosrc, E'\n  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)', '') || prosecdef::text || config, '|' order by sig)) from cur) as "본문 같음",
  '기대: 29 / bea9db431ac83a33a603ac70a740b7d0 (같으면 지금 29개의 본문·보안·search_path가 저장소와 같음)' as "원본 같음",
  null::text as "검사 줄(정확히)", null::text as "검사 문장", null::text as "CR 개수", null::text as "보안 지금/기대", null::text as "search_path 지금/기대",
  null::text as "anon 실행 지금/기대", null::text as "authenticated 실행 지금/기대", null::text as "PUBLIC 실행", null::text as "소유자", null::text as "권한 원문"
union all
select row_number() over (order by fsig), fsig,
  case when not in_db then '운영 DB에 없음' when not in_repo then '저장소 기대값 없음(이름·인수가 다름)'
       when md5(replace(prosrc, E'\n  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)', '')) = e_body then '같음' else '다름 ' || md5(replace(prosrc, E'\n  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)', '')) end,
  case when not in_db or not in_repo then null when md5(prosrc) = e_raw then '같음' else '다름 ' || md5(prosrc) end,
  case when in_db then (strpos(prosrc, E'\n  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)') > 0)::text end,
  case when in_db then (prosrc ~ '_can_write constant boolean := public\.assert_can_write\(\);')::text end,
  case when in_db then (length(prosrc) - length(replace(prosrc, E'\r', '')))::text end,
  case when in_db then prosecdef::text || ' / ' || coalesce(e_secdef::text, '?') end,
  case when in_db then config || ' / ' || coalesce(e_config, '?') end,
  case when in_db then has_function_privilege('anon', oid, 'execute')::text || ' / ' || coalesce(e_anon::text, '?') end,
  case when in_db then has_function_privilege('authenticated', oid, 'execute')::text || ' / ' || coalesce(e_auth::text, '?') end,
  case when in_db then (proacl is null or exists (select 1 from aclexplode(proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text end,
  case when in_db then pg_get_userbyid(proowner) end,
  case when in_db then coalesce(proacl::text, '(기본 권한 = PUBLIC 실행 가능)') end
from j
order by 1;
