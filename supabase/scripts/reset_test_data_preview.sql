-- =====================================================================
-- 테스트 데이터 비우기: 확인용 (읽기만 함 — 아무것도 바꾸지 않는다)
-- reset_test_data.sql을 실행하기 전에 SQL Editor에서 먼저 실행해 지워질 개수와 남을 개수를 본다.
-- 맨 위 줄 "남길 카운터"의 남는 개수가 1이 아니면 reset_test_data.sql은 아무것도 지우지 않고 멈춘다.
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
         coalesce((select format('카운터 id %s · 상태 %s · 처음 제안 id %s', counter_id, status, coalesce(proposal_id::text, '없음')) from keep), '못 찾음 — 이대로는 실행되지 않아요')
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
  union all select 6, 'build_votes (따봉·비추)', (select count(*) from public.build_votes), 0, '남는 빌드의 따봉 수도 0'
  union all select 7, 'build_vote_log (따봉 기록)', (select count(*) from public.build_vote_log), 0, null
  union all select 8, 'build_status_log (빌드 승인·숨김 기록)', (select count(*) from public.build_status_log), 0, null
  union all select 9, 'counter_status_log (카운터 숨김 기록)', (select count(*) from public.counter_status_log), 0, null
  union all select 10, 'counter_deletions (완전 삭제 기록)', (select count(*) from public.counter_deletions), 0, null
  union all select 11, 'posts (노가리방 글)', (select count(*) from public.posts), 0, null
  union all select 12, 'post_comments (노가리방 댓글)', (select count(*) from public.post_comments), 0, null
  union all select 13, 'post_votes (글 추천)', (select count(*) from public.post_votes), 0, null
  union all select 14, 'doc_comments (문서 댓글)', (select count(*) from public.doc_comments), 0, null
  union all select 15, 'reports (신고)', (select count(*) from public.reports), 0, null
  union all select 16, 'hide_log (숨김 기록)', (select count(*) from public.hide_log), 0, null
  union all select 17, 'board_last_write (도배 방지 시각)', (select count(*) from public.board_last_write), 0, null
  union all select 18, 'notifications (알림)', (select count(*) from public.notifications), 0, null
  union all select 19, 'xp_events (경험치 기록)', (select count(*) from public.xp_events), 0, '남은 데이터로 다시 계산해 새로 쌓음'
  union all select 20, 'user_titles (칭호)', 0, (select count(*) from public.user_titles), '지우지 않고 다시 계산 — 조건이 깨진 칭호만 회수 (알림 없음)'
  union all select 21, 'profiles (계정·닉네임·운영자)', 0, (select count(*) from public.profiles), '그대로. 경험치·레벨만 다시 계산'
  union all select 22, 'nickname_changes (닉네임 변경 기록)', 0, (select count(*) from public.nickname_changes), '계정 정보라 그대로'
  union all select 23, '설정값 (xp_rules · item_prices · offmeta_champions · xp_levels)', 0,
         (select count(*) from public.xp_rules) + (select count(*) from public.item_prices)
         + (select count(*) from public.offmeta_champions) + (select count(*) from public.xp_levels), '그대로'
)
select what as "표", to_delete as "지울 개수", to_keep as "남는 개수", note as "메모"
from rows order by ord;
