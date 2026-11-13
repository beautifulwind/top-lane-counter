-- =====================================================================
-- 테스트 데이터 비우기: 확인용 (읽기만 함 — 아무것도 바꾸지 않는다)
-- reset_test_data.sql을 실행하기 전에 SQL Editor에서 먼저 실행해 지워질 개수와 남을 개수를 본다.
-- "남길 카운터" 줄의 남는 개수가 1이 아니거나 "profiles 중 운영자" 줄이 0이면 reset_test_data.sql은 아무것도 지우지 않고 멈춘다.
-- 계정(운영자·테스트용 구글 계정 포함)은 하나도 지우지 않는다. 운영자 모드 켜짐/꺼짐과 role도 그대로다.
-- =====================================================================

with keep as (
  select c.id as counter_id, c.status, public.origin_proposal_id(c.id) as proposal_id
  from public.counters c
  where c.target_champion = 'Tryndamere' and c.counter_champion = 'Malphite'
),
kept_builds as (
  select b.id from public.builds b join keep k on k.counter_id = b.counter_id where b.status = 'approved'
),
rows (ord, what, to_delete, to_keep, note) as (
  select 0, '남길 카운터: 트린다미어 상대 말파이트',
         0::bigint, (select count(*) from keep),
         coalesce((select format('카운터 id %s · 상태 %s · 처음 제안 id %s', counter_id, status, coalesce(proposal_id::text, '없음')) from keep), '못 찾음 — 이대로는 실행되지 않습니다')
  union all select 1, 'counters (카운터)',
         (select count(*) from public.counters where id not in (select counter_id from keep)),
         (select count(*) from public.counters where id in (select counter_id from keep)), null
  union all select 2, 'matchup_docs (매치업 문서)',
         (select count(*) from public.matchup_docs where counter_id not in (select counter_id from keep)),
         (select count(*) from public.matchup_docs where counter_id in (select counter_id from keep)), null
  union all select 3, 'doc_revisions (문서 수정 기록)',
         (select count(*) from public.doc_revisions),
         (select count(*) from public.matchup_docs where counter_id in (select counter_id from keep)),
         '말파 문서는 지금 내용 1줄(처음 버전)로 새로 남김'
  union all select 4, 'edit_proposals (제안)',
         (select count(*) from public.edit_proposals where id is distinct from (select proposal_id from keep)),
         (select count(*) from public.edit_proposals where id = (select proposal_id from keep)),
         '말파 카운터를 만든 처음 제안 1개만 남김'
  union all select 5, 'builds (빌드)',
         (select count(*) from public.builds where id not in (select id from kept_builds)),
         (select count(*) from kept_builds),
         '말파 카운터의 공개 빌드만 남김 (대기·거절·숨김 빌드는 지움)'
  union all select 5.1, 'build_revisions (빌드 수정 기록, 038)',
         case when to_regclass('public.build_revisions') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.build_revisions', false, true, '')))[1]::text::bigint end,
         case when to_regclass('public.build_revisions') is null then 0 else (select count(*) from kept_builds) end,
         '모두 지우고 남는 말파 공개 빌드마다 지금 내용으로 "이전" 1줄 (038 실행 전이면 0)'
  union all select 5.2, 'build_editors (빌드 기여자, 038)',
         case when to_regclass('public.build_editors') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.build_editors', false, true, '')))[1]::text::bigint end,
         0, '모두 지움 (문서 수정 제안도 지워지므로)'
  union all select 6, 'build_votes (추천·비추천)', (select count(*) from public.build_votes), 0, '남는 빌드의 추천·비추천 수도 0'
  union all select 7, 'build_vote_log (빌드 추천·비추천 기록)', (select count(*) from public.build_vote_log), 0, null
  union all select 8, 'build_status_log (빌드 승인·숨김 기록)', (select count(*) from public.build_status_log), 0, null
  union all select 9, 'counter_status_log (카운터 숨김 기록)', (select count(*) from public.counter_status_log), 0, null
  union all select 10, 'counter_deletions (완전 삭제 기록)', (select count(*) from public.counter_deletions), 0, null
  union all select 11, 'posts (자유게시판 글)', (select count(*) from public.posts), 0, null
  union all select 12, 'post_comments (자유게시판 댓글)', (select count(*) from public.post_comments), 0, null
  union all select 13, 'post_votes (글 추천)', (select count(*) from public.post_votes), 0, null
  union all select 13.1, 'board_attachments (글·댓글에 붙은 사진, 023)', (select count(*) from public.board_attachments), 0,
         '사진 파일은 정리 대기열(storage_trash)로 → 매일 사진 정리(media-cleanup)가 Storage에서 지움'
  union all select 13.2, 'Storage board-media (사진 파일)', 0, (select count(*) from storage.objects where bucket_id = 'board-media'),
         '이 스크립트는 바로 못 지움 — 다음 사진 정리 때 대기열·안 붙은 지 24시간 지난 파일이 지워짐'
  union all select 14, 'doc_comments (문서 댓글)', (select count(*) from public.doc_comments), 0, null
  union all select 15, 'reports (신고)', (select count(*) from public.reports), 0, null
  union all select 15.1, 'wiki_reports (상대법·빌드 오류 신고, 043)',
         case when to_regclass('public.wiki_reports') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.wiki_reports', false, true, '')))[1]::text::bigint end,
         0, '처리 전·처리된 것 모두 지움 (043 실행 전이면 0)'
  union all select 15.2, 'influencer_applications (장인 인증 신청, 046)',
         case when to_regclass('public.influencer_applications') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.influencer_applications', false, true, '')))[1]::text::bigint end,
         0, '전부 지움 (046 실행 전이면 0). 처리 전 신청은 먼저 취소 처리해 신청 전 닉네임으로 되돌린다'
  union all select 15.3, '  └ 장인 표시 / 인증 대기 / 닉네임 변경 예정 프로필 (046)', 0,
         case when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'influencer') then 0
              else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.profiles where influencer is not null or nickname_state is not null', false, true, '')))[1]::text::bigint end,
         '프로필은 남지만 장인 표시·상태는 지움 (변경 예정인 회원은 임시 닉네임으로)'
  union all select 15.4, 'ext_links + link_reports (장인 외부 링크 + 링크 신고, 047)',
         case when to_regclass('public.ext_links') is null then 0 else (xpath('/row/c/text()', query_to_xml('select (select count(*) from public.ext_links) + (select count(*) from public.link_reports) as c', false, true, '')))[1]::text::bigint end,
         0, '전부 지움 (047 실행 전이면 0). 허용 사이트 표 link_domains는 설정이라 남김'
  union all select 15.5, 'influencer_follows + follow_rate + follow_notify_queue (장인 팔로우 / 호출 횟수 / 알림 대기 줄, 050)',
         case when to_regclass('public.influencer_follows') is null then 0 else (xpath('/row/c/text()', query_to_xml('select (select count(*) from public.influencer_follows) + (select count(*) from public.follow_rate) + (select count(*) from public.follow_notify_queue) as c', false, true, '')))[1]::text::bigint end,
         0, '전부 지움 (050 실행 전이면 0). 푸시 설정의 follow_builds 칸은 그대로'
  union all select 15.6, 'notice_notify_queue (공지 알림 대기 줄, 051)',
         case when to_regclass('public.notice_notify_queue') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.notice_notify_queue', false, true, '')))[1]::text::bigint end,
         0, '전부 지움 (051 실행 전이면 0). 공지 글은 자유게시판 글과 함께 지워진다. 푸시 설정의 notice 칸은 그대로'
  union all select 15.7, 'new_follower_counted (새 팔로워 알림에서 센 기록, 052)',
         case when to_regclass('public.new_follower_counted') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.new_follower_counted', false, true, '')))[1]::text::bigint end,
         0, '전부 지움 (052 실행 전이면 0). 푸시 설정의 new_followers 칸은 그대로'
  union all select 16, 'hide_log (숨김 기록)', (select count(*) from public.hide_log), 0, null
  union all select 16.1, 'moderation_log (운영진 처리 기록)', (select count(*) from public.moderation_log), 0, '감독관 지정·해제 기록 포함 전부 지움 (역할 자체는 profiles에 그대로)'
  union all select 16.2, 'proposal_reviewing (검토 중 표시)', (select count(*) from public.proposal_reviewing), 0, '임시 표시라 모두 비움'
  union all select 17, 'board_last_write (도배 방지 시각)', (select count(*) from public.board_last_write), 0, null
  union all select 17.1, 'wiki_last_write (상대법·빌드 등록·수정 간격, 038)',
         case when to_regclass('public.wiki_last_write') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.wiki_last_write', false, true, '')))[1]::text::bigint end,
         0, null
  union all select 18, 'notifications (알림)', (select count(*) from public.notifications), 0, null
  union all select 18.05, '  └ 그중 게시판 신고 알림 (report_received, 045 실행 전이면 0)', (select count(*) from public.notifications where kind = 'report_received'), 0, '알림과 함께 모두 지움'
  union all select 18.1, 'inquiries (문의하기 문의·답변)', (select count(*) from public.inquiries), 0, '모두 비움'
  union all select 18.2, 'inquiry_quota (문의 하루 개수)', (select count(*) from public.inquiry_quota), 0, '모두 비움'
  union all select 19, 'xp_events (경험치 기록)', (select count(*) from public.xp_events), 0, '남은 데이터로 다시 계산해 새로 쌓음'
  union all select 20, 'user_titles (칭호)', 0, (select count(*) from public.user_titles), '지우지 않고 다시 계산 — 조건이 깨진 칭호만 회수 (알림 없음)'
  union all select 21, 'profiles (계정·닉네임·역할) — 전체', 0, (select count(*) from public.profiles), '지우지 않음. 테스트용 구글 계정도 그대로(데이터만 비움). 경험치·레벨만 다시 계산'
  union all select 21.1, 'profiles 중 운영자 (role = admin)', 0, (select count(*) from public.profiles where role = 'admin'), '반드시 남음. 0이면 실행해도 아무것도 지우지 않고 멈춤'
  union all select 21.2, '운영자 모드 켜짐 / 꺼짐', 0, (select count(*) from public.profiles where role = 'admin' and operator_mode),
         format('켜짐 %s · 꺼짐 %s — 상태 그대로 (스크립트가 끝에서 확인)', (select count(*) from public.profiles where role = 'admin' and operator_mode), (select count(*) from public.profiles where role = 'admin' and not operator_mode))
  union all select 21.3, 'profiles 중 감독관 (role = moderator)', 0, (select count(*) from public.profiles where role = 'moderator'), '지우지도 해제하지도 않음. 테스트 감독관이면 공개 전에 따로 해제'
  union all select 21.4, 'profiles 중 비회원 (is_guest)', 0, (select count(*) from public.profiles where is_guest), '그대로 (기존 비회원 정리 일정이 따로 지움)'
  union all select 22, 'nickname_changes (닉네임 변경 기록)', 0, (select count(*) from public.nickname_changes), '계정 정보라 그대로'
  union all select 22.1, 'push_subscriptions (휴대폰 알림을 켠 기기, 037)', 0,
         case when to_regclass('public.push_subscriptions') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.push_subscriptions', false, true, '')))[1]::text::bigint end,
         '계정 설정이라 그대로 (037 실행 전이면 0). 비우는 동안에는 푸시를 보내지 않음'
  union all select 22.2, 'push_settings (알림 종류 켜기/끄기, 037)', 0,
         case when to_regclass('public.push_settings') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.push_settings', false, true, '')))[1]::text::bigint end,
         '계정 설정이라 그대로'
  union all select 23, '설정값 (xp_rules · item_prices · offmeta_champions · xp_levels)', 0,
         (select count(*) from public.xp_rules) + (select count(*) from public.item_prices)
         + (select count(*) from public.offmeta_champions) + (select count(*) from public.xp_levels), '그대로'
)
select what as "표", to_delete as "지울 개수", to_keep as "남는 개수", note as "메모"
from rows order by ord;
