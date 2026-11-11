-- =====================================================================
-- 테스트 데이터 비우기 (정식 공개 직전에 다시 쓸 수 있음 — 마이그레이션이 아니라 필요할 때 손으로 돌리는 스크립트)
--
-- 남김: 계정(auth.users)·프로필(닉네임·역할)·닉네임 변경 기록, 휴대폰 알림을 켠 기기·알림 종류 설정(037), 설정값(xp_rules·xp_levels·item_prices·offmeta_champions),
--       트린다미어 상대 말파이트 카운터 1개 — 지금 문서, 공개 빌드, 그 카운터를 만든 처음 제안 1개.
-- 지움: 그 밖의 카운터·문서·제안·빌드 전부, 빌드 추천·비추천과 그 기록, 자유게시판 글·댓글·추천, 문서 댓글, 신고, 알림, 문의하기 문의·답변(032),
--       빌드 수정 기록·기여자·등록 간격(038 — 남는 말파 공개 빌드마다 지금 내용으로 "이전" 기록 1줄을 새로 남김),
--       경험치 기록, 숨김 기록, 운영진 처리 기록(moderation_log, 감독관 지정·해제 기록 포함 전부), 빌드·카운터 상태 기록, 완전 삭제 기록, 도배 방지 시각, 018 백업 표의 내용,
--       자유게시판 사진(023): 붙은 사진 줄은 지우고 파일 경로는 정리 대기열(storage_trash)로 — SQL은 Storage 파일을 못 지우므로
--       실제 파일은 다음 사진 정리(Edge Function media-cleanup, 매일)가 지운다. 바로 지우려면 Storage → board-media에서 직접.
-- 계정은 하나도 지우지 않는다: 운영자 계정(role = 'admin')과 운영자 모드(켜짐/꺼짐) 상태는 그대로이고,
--   테스트용 구글 계정도 지우지 않고 데이터만 비운다. profiles의 role·operator_mode는 이 스크립트가 바꾸지 않으며,
--   끝에서 시작 때와 같은지 확인해 다르면 전부 되돌리고 멈춘다. (감독관 role도 그대로 — 필요하면 따로 해제)
-- 말파 카운터의 기록 정리:
--   - 수정 기록은 지우고 지금 문서를 "처음 버전" 1줄로 새로 남긴다 (되돌리기 기준점, 문서의 "최근 수정" 날짜는 그대로).
--   - 제안은 카운터를 만든 처음 제안만 남긴다 (카운터 제안자 경험치·칭호, 문서 댓글 알림 받는 사람, 첫 빌드 연결에 쓰임).
--     문서 수정 제안·거절·대기 제안은 지운다. 공개 빌드 중 대기·거절·숨김 빌드도 지운다.
-- 마지막에 모든 사람의 경험치·레벨·칭호를 남은 데이터로 다시 계산한다 (알림 없음, 원래 날짜로 다시 기록).
-- 비우는 동안에는 웹 푸시 트리거(037 notifications_push)를 꺼 두어 휴대폰으로 알림이 나가지 않게 하고, 끝에서 다시 켠다.
--
-- 실행 전: reset_test_data_preview.sql로 개수를 확인한다. 실행: SQL Editor에 통째로 붙여넣어 한 번.
-- SQL Editor가 "Run and enable RLS"를 물어보면 반드시 "Run without RLS"로 실행한다.
--   "Run and enable RLS"는 새로 만드는 표(여기서는 임시 표 reset_keep)에 RLS를 켜려다 에러가 난다.
--   (임시 표는 끝나면 사라지고, 실제 표의 RLS는 이 스크립트가 바꾸지 않는다.)
-- 중간에 오류가 나면 전부 되돌려진다 (begin … commit). 말파 카운터를 못 찾으면 아무것도 지우지 않고 멈춘다.
-- 되돌릴 수 없다 — 실행 전에 Supabase 백업(Database → Backups)을 확인한다. 한 번 commit되면 복구 방법은 백업뿐이다.
-- 순서: ① 백업 확인 → ② reset_test_data_preview.sql로 개수 확인(운영자 1명·말파 카운터 1개) → ③ 이 파일 실행
--       → ④ 맨 아래 결과 표 확인 → ⑤ Storage board-media의 사진 파일은 다음 사진 정리(매일 새벽 4:40)가 지운다.
-- =====================================================================

begin;

-- 비우는 동안 휴대폰 알림(웹 푸시)을 보내지 않는다 (037 실행 전이면 건너뜀). 맨 아래에서 다시 켠다
do $$ begin if exists (select 1 from pg_trigger where tgname = 'notifications_push') then execute 'alter table public.notifications disable trigger notifications_push'; end if; end $$;

-- ---------------------------------------------------------------------
-- 0. 남길 카운터 찾기 (없거나 여러 개면 멈춤)
-- ---------------------------------------------------------------------
create temp table reset_keep on commit drop as
select c.id as counter_id, public.origin_proposal_id(c.id) as proposal_id
from public.counters c
where c.target_champion = 'Tryndamere' and c.counter_champion = 'Malphite';

do $$
begin
  if (select count(*) from reset_keep) <> 1 then
    raise exception '트린다미어 상대 말파이트 카운터를 찾지 못했습니다. 아무것도 지우지 않았습니다.';
  end if;
end;
$$;

-- 운영자 계정·운영자 모드 상태 기록 (끝에서 그대로인지 확인). 운영자가 없으면 멈춘다
create temp table reset_admins on commit drop as
select id, role, operator_mode from public.profiles where role = 'admin';

do $$
begin
  if (select count(*) from reset_admins) = 0 then
    raise exception '운영자 계정(role = admin)을 찾지 못했습니다. 아무것도 지우지 않았습니다.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 1. 자유게시판·문서 댓글·신고
-- ---------------------------------------------------------------------
delete from public.reports;
delete from public.post_votes;
delete from public.board_attachments; -- 트리거가 파일 경로를 storage_trash에 넣는다 (023)
delete from public.post_comments;
delete from public.posts;
delete from public.doc_comments;
delete from public.board_last_write;

-- ---------------------------------------------------------------------
-- 2. 빌드 추천·비추천 (남는 빌드도 0표로)
-- ---------------------------------------------------------------------
delete from public.build_votes;
delete from public.build_vote_log;

-- ---------------------------------------------------------------------
-- 3. 빌드: 말파 카운터의 공개 빌드만 남김
-- ---------------------------------------------------------------------
delete from public.builds b
 where not (b.counter_id = (select counter_id from reset_keep) and b.status = 'approved');
update public.builds set up_count = 0, down_count = 0 where up_count <> 0 or down_count <> 0;
delete from public.build_status_log;

-- ---------------------------------------------------------------------
-- 4. 제안: 말파 카운터를 만든 처음 제안만 남김
-- ---------------------------------------------------------------------
delete from public.edit_proposals where id is distinct from (select proposal_id from reset_keep);

-- ---------------------------------------------------------------------
-- 5. 카운터: 말파 카운터만 남김 (문서·수정 기록·상태 기록은 같이 지워짐)
-- ---------------------------------------------------------------------
delete from public.counters where id <> (select counter_id from reset_keep);
delete from public.counter_status_log;
delete from public.counter_deletions;

-- ---------------------------------------------------------------------
-- 6. 말파 문서의 수정 기록 → 지금 내용 1줄(처음 버전)
--    문서의 "최근 수정" 날짜가 오늘로 바뀌지 않게 updated_at 자동 갱신 트리거를 잠깐 끈다
-- ---------------------------------------------------------------------
delete from public.doc_revisions;
alter table public.matchup_docs disable trigger matchup_docs_touch;
with r as (
  insert into public.doc_revisions (counter_id, proposal_id, content, edited_by, approved_by, kind, created_at)
  select d.counter_id, k.proposal_id,
         jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions),
         coalesce(p.proposer_id, d.updated_by), p.reviewed_by, 'create', d.updated_at
  from public.matchup_docs d
  join reset_keep k on k.counter_id = d.counter_id
  left join public.edit_proposals p on p.id = k.proposal_id
  returning id, counter_id
)
update public.matchup_docs d set revision_id = r.id from r where d.counter_id = r.counter_id;
alter table public.matchup_docs enable trigger matchup_docs_touch;
update public.edit_proposals set base_revision_id = null where base_revision_id is not null;

-- 6.1 (038) 빌드 수정 기록·기여자·등록 간격: 비우고, 남은 말파 공개 빌드마다 지금 내용으로 "이전(migrate)" 1줄 (038 실행 전이면 건너뜀)
do $$
begin
  if to_regclass('public.build_revisions') is not null then
    execute 'delete from public.build_revisions';
    execute 'delete from public.build_editors';
    execute 'delete from public.wiki_last_write';
    perform public.wiki_backfill_matchups();
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 위에서 지운 것 때문에 트랜잭션 끝에 돌 경험치 계산을 지금 끝내 두고, 경험치 기록·알림·숨김 기록을 비운다
-- ---------------------------------------------------------------------
set constraints all immediate;
delete from public.xp_events;
delete from public.notifications;
delete from public.hide_log;
do $$ begin if to_regclass('public.proposal_reviewing') is not null then execute 'delete from public.proposal_reviewing'; end if; end $$; -- 031 "검토 중" 표시
delete from public.moderation_log; -- 운영진 처리 기록 전부 (감독관 지정·해제 기록 포함 — 1년 보관 삭제(035)와 같은 성격의 기록)
do $$ begin if to_regclass('public.inquiries') is not null then execute 'delete from public.inquiries'; execute 'delete from public.inquiry_quota'; end if; end $$; -- 032 문의하기

-- 018 백업 표 (지운 빌드의 예전 스킬 순서가 남아 있음): 있으면 비운다
do $$
begin
  if to_regclass('public.builds_skill_backup_018') is not null then
    execute 'delete from public.builds_skill_backup_018';
  end if;
  if to_regclass('public.proposal_build_backup_018') is not null then
    execute 'delete from public.proposal_build_backup_018';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 경험치·레벨·칭호 다시 계산 (운영자는 빼고, 알림 없음, 원래 날짜로)
-- ---------------------------------------------------------------------
select public.recalc_all_xp(true);
set constraints all immediate;
delete from public.notifications;

-- 운영자 계정·운영자 모드가 시작 때와 같은지 확인 (다르면 전체 되돌림)
do $$
begin
  if exists (
    select 1 from reset_admins a
    left join public.profiles p on p.id = a.id
    where p.id is null or p.role is distinct from a.role or p.operator_mode is distinct from a.operator_mode
  ) or (select count(*) from public.profiles where role = 'admin') <> (select count(*) from reset_admins) then
    raise exception '운영자 계정 또는 운영자 모드가 바뀌었습니다. 전부 되돌렸습니다.';
  end if;
end;
$$;

do $$ begin if exists (select 1 from pg_trigger where tgname = 'notifications_push') then execute 'alter table public.notifications enable trigger notifications_push'; end if; end $$;

-- ---------------------------------------------------------------------
-- 9. 결과 (이 표가 보이면 끝까지 실행된 것)
-- ---------------------------------------------------------------------
select '카운터' as "표", count(*) as "남은 개수" from public.counters
union all select '매치업 문서', count(*) from public.matchup_docs
union all select '문서 수정 기록', count(*) from public.doc_revisions
union all select '제안', count(*) from public.edit_proposals
union all select '빌드', count(*) from public.builds
union all select '빌드 추천·비추천', count(*) from public.build_votes
union all select '빌드 수정 기록 (038, 남은 공개 빌드마다 1줄 · 실행 전이면 0)', case when to_regclass('public.build_revisions') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.build_revisions', false, true, '')))[1]::text::integer end
union all select '빌드 기여자 (038, 실행 전이면 0)', case when to_regclass('public.build_editors') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.build_editors', false, true, '')))[1]::text::integer end
union all select '자유게시판 글', count(*) from public.posts
union all select '붙은 사진', count(*) from public.board_attachments
union all select '사진 정리 대기열 (다음 정리 때 파일 삭제)', count(*) from public.storage_trash
union all select '문서 댓글', count(*) from public.doc_comments
union all select '알림', count(*) from public.notifications
union all select '문의 (032 실행 전이면 0)', case when to_regclass('public.inquiries') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.inquiries', false, true, '')))[1]::text::integer end
union all select '경험치 기록 (다시 계산)', count(*) from public.xp_events
union all select '칭호 (다시 계산)', count(*) from public.user_titles
union all select '경험치가 있는 사람', count(*) from public.profiles where xp > 0
union all select '처리 기록 (moderation_log)', count(*) from public.moderation_log
union all select '휴대폰 알림을 켠 기기 (그대로, 037 실행 전이면 0)', case when to_regclass('public.push_subscriptions') is null then 0 else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.push_subscriptions', false, true, '')))[1]::text::integer end
union all select '웹 푸시 트리거 켜짐 (037 실행 전이면 0)', count(*) from pg_trigger where tgname = 'notifications_push' and tgenabled <> 'D'
union all select '프로필 (그대로)', count(*) from public.profiles
union all select '운영자 계정 (그대로)', count(*) from public.profiles where role = 'admin'
union all select '운영자 모드 켜짐 (그대로)', count(*) from public.profiles where role = 'admin' and operator_mode;

commit;
