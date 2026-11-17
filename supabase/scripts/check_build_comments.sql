-- =====================================================================
-- 060(빌드 댓글 정리) 전에 운영 DB의 빌드 댓글이 얼마나 쌓였는지 보는 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 모든 줄이 0이면 060은 지울 것이 없다 (그대로 실행해도 된다).
--   - 0이 아닌 줄이 있으면 [지금 값]을 알려 주세요. 지울지 문서 댓글로 옮길지 정한 뒤 060을 그에 맞춰 만든다.
--   - 내용(본문)은 읽지 않는다. 개수만 센다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", memo as "메모"
from (
  select 1 as ord, '058 실행됨 (build_comments 표가 있음)' as what,
    coalesce(to_regclass('public.build_comments')::text, '없음') as now_value,
    '없음이면 아래 줄은 모두 실패한다 - 알려 주세요' as memo
  union all select 2, '빌드 댓글 전체 (최상위 / 답글)',
    (select count(*) || ' (' || count(*) filter (where parent_id is null) || ' / ' || count(*) filter (where parent_id is not null) || ')'
       from public.build_comments), null
  union all select 3, '그중 보이는 것 / 숨긴 것 / 지운 것 (작성자 지움 / 운영진 삭제)',
    (select count(*) filter (where deleted_at is null and status = 'visible') || ' / '
            || count(*) filter (where deleted_at is null and status = 'hidden') || ' / '
            || count(*) filter (where deleted_at is not null)
            || ' (' || count(*) filter (where delete_kind = 'author') || ' / ' || count(*) filter (where delete_kind = 'staff') || ')'
       from public.build_comments), '옮긴다면 보이는 것·숨긴 것이 대상'
  union all select 4, '탈퇴 껍데기 (작성자 빈 것)',
    (select count(*)::text from public.build_comments where author_id is null), null
  union all select 5, '쓴 사람 수 (그중 비회원)',
    (select count(distinct c.author_id) || ' (' || count(distinct c.author_id) filter (where p.is_guest) || ')'
       from public.build_comments c left join public.profiles p on p.id = c.author_id), null
  union all select 6, '댓글이 달린 빌드 수 / 그 빌드들이 속한 상대법 수',
    (select count(distinct c.build_id) || ' / ' || count(distinct b.counter_id)
       from public.build_comments c join public.builds b on b.id = c.build_id), null
  union all select 7, '빌드 댓글 수 칸: 0이 아닌 빌드 수 / 합계 (builds.comment_count)',
    (select count(*) filter (where comment_count <> 0) || ' / ' || coalesce(sum(comment_count), 0) from public.builds),
    '합계는 2·3번의 "보이는 것"과 같아야 함'
  union all select 8, '빌드 댓글 신고 (전체 / 처리 전)',
    (select count(*) || ' / ' || count(*) filter (where status = 'open') from public.reports where build_comment_id is not null), null
  union all select 9, '숨김 기록 hide_log (build_comment, 전체 / 아직 숨김)',
    (select count(*) || ' / ' || count(*) filter (where unhidden_at is null) from public.hide_log where kind = 'build_comment'),
    '작성자의 "최근 숨김 횟수"에 들어가는 기록'
  union all select 10, '처리 기록 moderation_log (build_comment)',
    (select count(*)::text from public.moderation_log where target_kind = 'build_comment'), null
  union all select 11, '알림: 내 빌드에 새 댓글 build_comment (전체 / 안 읽음)',
    (select count(*) || ' / ' || count(*) filter (where read_at is null) from public.notifications where kind = 'build_comment'), null
  union all select 12, '알림: 빌드 댓글 숨김·다시 공개·운영진 삭제 (전체 / 안 읽음)',
    (select count(*) || ' / ' || count(*) filter (where read_at is null) from public.notifications
      where kind in ('build_comment_hidden', 'build_comment_restored', 'build_comment_deleted')), null
  union all select 13, '알림: 빌드 댓글의 답글 comment_reply (build_id 있음, 전체 / 안 읽음)',
    (select count(*) || ' / ' || count(*) filter (where read_at is null) from public.notifications
      where kind = 'comment_reply' and build_id is not null), null
  union all select 14, '참고: 커뮤니티 글의 답글 알림 comment_reply (post_id 있음)',
    (select count(*)::text from public.notifications where kind = 'comment_reply' and post_id is not null), '060에서 건드리지 않음'
  union all select 15, '경험치 기록 xp_events (build_comment: 줄 수 / 받은 사람 수 / 합계)',
    (select count(*) || ' / ' || count(distinct user_id) || ' / ' || coalesce(sum(amount), 0) from public.xp_events where type = 'build_comment'),
    '합계가 0보다 크면 지금 빌드 댓글로 받은 경험치가 남아 있음'
  union all select 16, '참고: 지금 문서 댓글 수 (전체 / 보이는 것)',
    (select count(*) || ' / ' || count(*) filter (where deleted_at is null and status = 'visible') from public.doc_comments), null
) rows
order by ord;
