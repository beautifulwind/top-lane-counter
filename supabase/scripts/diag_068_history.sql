-- 주의: 줄바꿈(CRLF)이 섞여 붙여 넣어진 DB에서는 함수 본문 지문이 파일 기준과 달라질 수 있다. 본문을 비교할 때는 CR(\r)을 뺀 값으로 보라(CR 개수 칸이 0보다 크면 이 경우).
-- =====================================================================
-- 068 뒤 진단 3 (읽기만, 되면 보너스). Supabase는 pg_stat_statements(extensions 스키마)를 기본으로 켜 둔다.
-- 지금까지 이 DB에서 실행된 "create (or replace) function public.<29개 중 하나>" 문장이 남아 있으면 보여 준다.
--   - 마이그레이션 파일에 없는 문장(직접 고친 흔적)이 있는지 볼 수 있다. 통계가 초기화됐거나 오래돼 밀려났으면 안 나온다.
--   - 결과의 query 칸에는 실행한 SQL 문장이 그대로 들어 있다(이 저장소의 함수 정의라 개인정보는 없다).
--   - 확장이 없거나 권한이 없으면 오류(relation ... does not exist / permission denied)가 나는데, 그것도 읽기만 하다 멈춘 것이다.
-- =====================================================================
select s.calls as "실행 횟수",
       substring(s.query from '(?i)function\s+public\.(apply_influencer|begin_edit|create_build|create_comment|create_doc_comment|create_matchup|create_post|edit_build|edit_comment|edit_doc_comment|edit_my_build|edit_my_proposal|edit_post|follow_influencer|report_comment|report_doc_comment|report_link|report_post|report_profile_photo|report_wiki|resubmit_build|resubmit_proposal|save_build|set_application_photo|set_build_link|set_profile_links|set_profile_photo|vote_build|vote_post)\s*\(') as "함수",
       md5(s.query) as "문장 md5",
       length(s.query) as "길이",
       (s.query ~ 'assert_can_write') as "068 문장",
       left(regexp_replace(s.query, '\s+', ' ', 'g'), 400) as "앞부분"
from extensions.pg_stat_statements s
where s.query ~* 'create\s+(or\s+replace\s+)?function\s+public\.(apply_influencer|begin_edit|create_build|create_comment|create_doc_comment|create_matchup|create_post|edit_build|edit_comment|edit_doc_comment|edit_my_build|edit_my_proposal|edit_post|follow_influencer|report_comment|report_doc_comment|report_link|report_post|report_profile_photo|report_wiki|resubmit_build|resubmit_proposal|save_build|set_application_photo|set_build_link|set_profile_links|set_profile_photo|vote_build|vote_post)\s*\('
order by 2, 5, 1 desc;
