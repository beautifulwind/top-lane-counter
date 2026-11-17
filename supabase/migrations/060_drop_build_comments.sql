-- =====================================================================
-- 060: 빌드 댓글 정리(삭제) (2026-11-17, SPEC 6-60) - 문서 댓글 답글(059) + 새 화면 배포 "뒤"에 실행한다
--
-- 058의 빌드 댓글을 없애고 문서 댓글("4. 댓글", 059부터 답글 2단계)로 통일한 마무리.
-- 운영 DB 확인(check_build_comments.sql) 결과 빌드 댓글·신고·숨김 기록·처리 기록·알림·경험치 기록이 모두 0 -> A안(지움)이지만 지울 행이 없다.
-- 그래서 행을 지우는 단계는 두지 않고, 맨 앞 안전장치가 그 행들을 다시 세어 하나라도 있으면 아무것도 바꾸지 않고 멈춘다.
--
-- 1. 빌드 댓글 분기만 더했던 함수를 057 내용으로: dismiss_reports(인자 5개 -> 4개), begin_edit, open_reports_for_moderator,
--    notify_staff_new_report, xp_should_have, xp_reason, has_visible_writing, guest_has_records, admin_member_info,
--    admin_deleted_writings, admin_member_detail_unchecked, log_hide.
-- 2. 커뮤니티·문서 댓글 답글과 함께 바꿨던 함수는 빌드 부분만 뺀다: check_comment_depth, notify_new_comment(글·문서만),
--    board_on_profile_delete(커뮤니티·문서 댓글 껍데기는 그대로), purge_deleted_writings(결과에서 build_comments 키 빠짐).
-- 3. 지우는 것: 표 build_comments(트리거 4개·읽기 정책·인덱스와 함께), builds.comment_count, reports.build_comment_id(+ 중복 신고 막기 인덱스,
--    신고 대상 검사는 3개 칸으로), 함수 build_open·build_comments_after·build_label·require_moderate_open_build·build_comment_for_update·
--    notify_build_comment와 화면 함수 7개(create/edit/delete_my/report/hide/restore/staff_delete_build_comment).
-- 4. 종류 목록: 숨김 기록·처리 기록에서 build_comment, 알림에서 build_comment·_hidden·_restored·_deleted를 뺀다 (comment_reply는 남김).
-- 그대로인 것: block_guest_comment(커뮤니티 댓글 비회원 막기), 문서 댓글 답글(059) 전부, 경험치 설정값, 새 pg_cron·Edge Function 없음.
--
-- 실행 전 supabase/scripts/check_build_cleanup_before.sql, 실행 뒤 check_build_cleanup_after.sql.
-- 059를 실행하고 새 화면(빌드 댓글 칸이 없는 화면)이 배포된 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- !! 옛 화면이 아직 떠 있으면 안 된다: 옛 화면은 builds.comment_count를 읽으므로 상대법 화면이 깨진다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 059 상태로 돌아간다.
--    빌드 댓글 표·칸·함수를 빈 채로 다시 만들고, 바꾼 함수를 059 내용으로 되돌린다 (060이 지운 데이터는 없다 - 안전장치가 0을 확인했다).
--    옛 화면(빌드 댓글 칸이 있는 화면)을 다시 쓰려면 이것을 먼저 실행한 뒤 화면을 되돌린다. 함수 내용은 059와 같다(낫표만 코드 번호로 적었다).
--     begin;
--     -- 1) 빌드 댓글 표·칸 (058과 같은 모양, 빈 표)
--     create table public.build_comments (
--       id               bigint generated always as identity primary key,
--       build_id         bigint not null references public.builds (id) on delete cascade,
--       parent_id        bigint,
--       author_id        uuid references public.profiles (id) on delete set null,
--       body             text not null check (deleted_at is not null or char_length(btrim(body)) between 1 and 1000),
--       status           text not null default 'visible' check (status in ('visible', 'hidden')),
--       hidden_note      text,
--       hidden_at        timestamptz,
--       hidden_by        uuid references public.profiles (id) on delete set null,
--       edited_at        timestamptz,
--       edit_grace_until timestamptz,
--       deleted_at       timestamptz,
--       deleted_by       uuid references public.profiles (id) on delete set null,
--       delete_kind      text check (delete_kind in ('author', 'staff')),
--       delete_note      text check (delete_note is null or char_length(delete_note) <= 500),
--       created_at       timestamptz not null default now(),
--       constraint build_comments_build_id_id_key unique (build_id, id),
--       constraint build_comments_parent_fkey foreign key (build_id, parent_id) references public.build_comments (build_id, id) on delete cascade,
--       constraint build_comments_delete_kind_set check ((deleted_at is null) = (delete_kind is null)),
--       constraint build_comments_author_or_deleted check (author_id is not null or deleted_at is not null)
--     );
--     create index build_comments_build_idx on public.build_comments (build_id, created_at);
--     create index build_comments_author_idx on public.build_comments (author_id, created_at);
--     create index build_comments_parent_idx on public.build_comments (parent_id) where parent_id is not null;
--     create index build_comments_deleted_idx on public.build_comments (deleted_at) where deleted_at is not null;
--     comment on table public.build_comments is
--       '상대법 빌드 카드의 댓글·답글 (058). 쓰기는 함수로만. 읽기: 지운 것 제외, 숨긴 것은 운영진만, 공개 빌드(+공개 상대법)의 것만';
--
--     alter table public.builds add column comment_count integer not null default 0;
--     comment on column public.builds.comment_count is '보이는(숨기지도 지우지도 않은) 빌드 댓글·답글 수 (058, 트리거가 관리)';
--
--     -- 빌드가 공개 중인가 (빌드 승인 + 상대법 공개) - 댓글 읽기 정책·쓰기 함수에서 씀
--     create function public.build_open(p_build bigint)
--     returns boolean language sql stable security definer set search_path = ''
--     as $$
--       select exists (
--         select 1 from public.builds b join public.counters c on c.id = b.counter_id
--          where b.id = p_build and b.status = 'approved' and c.status = 'approved');
--     $$;
--     revoke execute on function public.build_open(bigint) from public;
--     grant execute on function public.build_open(bigint) to anon, authenticated;
--
--     revoke all on public.build_comments from anon, authenticated;
--     grant select on public.build_comments to anon, authenticated;
--     alter table public.build_comments enable row level security;
--     create policy "build_comments: 읽기 (숨긴 것은 운영진만)" on public.build_comments for select
--       using (
--         deleted_at is null
--         and (public.is_admin()
--              or ((status = 'visible' or public.can_see_hidden(author_id)) and public.build_open(build_id)))
--       );
--
--     -- 댓글 수
--     create function public.build_comments_after()
--     returns trigger language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       bid bigint := case when tg_op = 'DELETE' then old.build_id else new.build_id end;
--     begin
--       update public.builds
--          set comment_count = (select count(*) from public.build_comments where build_id = bid and status = 'visible' and deleted_at is null)
--        where id = bid;
--       return null;
--     end;
--     $$;
--     revoke execute on function public.build_comments_after() from public, anon, authenticated;
--     create trigger build_comments_after after insert or delete or update of status, deleted_at on public.build_comments
--       for each row execute function public.build_comments_after();
--
--     -- 경험치·숨김 기록 (기존 댓글과 같은 트리거 함수)
--     create constraint trigger build_comments_rewards after insert or delete or update of status, deleted_at on public.build_comments
--       deferrable initially deferred for each row execute function public.rewards_on_post();
--     create trigger build_comments_no_guest before insert on public.build_comments
--       for each row execute function public.block_guest_comment();
--     create trigger build_comments_depth before insert or update of parent_id on public.build_comments
--       for each row execute function public.check_comment_depth();
--     -- 2) 신고 칸·종류 목록 (058과 같음)
--     alter table public.reports add column build_comment_id bigint references public.build_comments (id) on delete cascade;
--     alter table public.reports drop constraint reports_one_target;
--     alter table public.reports add constraint reports_one_target check (num_nonnulls(post_id, comment_id, doc_comment_id, build_comment_id) = 1);
--     create unique index reports_once_build_comment on public.reports (reporter_id, build_comment_id) where build_comment_id is not null;
--
--     alter table public.hide_log drop constraint hide_log_kind_check;
--     alter table public.hide_log add constraint hide_log_kind_check check (kind in ('post', 'comment', 'doc_comment', 'build_comment'));
--
--     alter table public.moderation_log drop constraint moderation_log_target_kind_check;
--     alter table public.moderation_log add constraint moderation_log_target_kind_check check (target_kind in (
--       'post', 'comment', 'doc_comment', 'proposal', 'user', 'inquiry', 'build', 'wiki_report', 'influencer_application', 'link', 'link_domain',
--       'build_comment'  -- 058
--     ));
--
--     alter table public.notifications drop constraint notifications_kind_check;
--     alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
--       'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--       'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
--       'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
--       'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
--       'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
--       'matchup_created', 'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created',
--       'error_reported', 'error_report_handled', 'report_received',
--       'influencer_applied', 'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--       'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
--       'followed_build_created', 'notice_posted', 'new_followers',
--       -- 058: 빌드 댓글, 답글, 빌드 댓글 숨김·다시 공개·운영진 삭제 (모두 알림함에만 - push_group에 없음 = 휴대폰 알림 없음)
--       'build_comment', 'comment_reply', 'build_comment_hidden', 'build_comment_restored', 'build_comment_deleted'
--     ]));
--
--     create trigger build_comments_hide_log after update of status on public.build_comments
--       for each row execute function public.log_hide();
--     -- 3) 빌드 댓글 도우미·함수 (058과 같음)
--     create function public.build_label(p_build bigint)
--     returns text language sql stable security definer set search_path = ''
--     as $$
--       select coalesce(nullif(btrim(b.name), ''), '빌드 ' || coalesce(b.seq::text, b.id::text)) from public.builds b where b.id = p_build;
--     $$;
--
--     -- 감독관: 숨긴 빌드(또는 숨긴 상대법)의 댓글은 운영자만 처리
--     create function public.require_moderate_open_build(p_build bigint)
--     returns void language plpgsql stable security definer set search_path = ''
--     as $$
--     begin
--       if public.is_moderator() and not public.build_open(p_build) then
--         raise exception '숨긴 빌드의 댓글은 운영자만 처리할 수 있습니다.' using errcode = '42501';
--       end if;
--     end;
--     $$;
--
--     create function public.build_comment_for_update(p_id bigint)
--     returns public.build_comments language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       c public.build_comments%rowtype;
--     begin
--       select * into c from public.build_comments where id = p_id for update;
--       if not found or c.deleted_at is not null then
--         raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       return c;
--     end;
--     $$;
--
--     -- 새 댓글·답글 알림 (기존 방식: 받는 사람이 나면 보내지 않음, 안 읽은 알림이 있으면 "N개"로 합침, 휴대폰 알림 없음)
--     --   p_kind: 'post' | 'build', p_target: 글 id | 빌드 id, p_owner: 글·빌드 주인, p_parent_author: 답글이면 부모 댓글 작성자
--     --   - 답글: 부모 댓글 작성자에게 comment_reply
--     --   - 글·빌드 주인: post_comment | build_comment (부모 댓글 작성자와 같은 사람이면 답글 알림 하나만)
--     create function public.notify_build_comment(p_user uuid, p_kind text, p_message text, p_build bigint)
--     returns void language plpgsql security definer set search_path = ''
--     as $$
--     begin
--       if p_user is null or p_user = (select auth.uid()) then
--         return;
--       end if;
--       insert into public.notifications (user_id, kind, message, build_id, counter_id)
--       values (p_user, p_kind, p_message, p_build, (select counter_id from public.builds where id = p_build));
--     end;
--     $$;
--
--     revoke execute on function public.build_label(bigint) from public, anon, authenticated;
--     revoke execute on function public.require_moderate_open_build(bigint) from public, anon, authenticated;
--     revoke execute on function public.build_comment_for_update(bigint) from public, anon, authenticated;
--     revoke execute on function public.notify_new_comment(text, bigint, uuid, uuid, boolean) from public, anon, authenticated;
--     revoke execute on function public.notify_build_comment(uuid, text, text, bigint) from public, anon, authenticated;
--     create function public.create_build_comment(p_build bigint, p_body text, p_parent bigint default null)
--     returns bigint language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       me uuid := public.board_writer();
--       b text := public.board_text(p_body, '댓글', 1000);
--       bl public.builds%rowtype;
--       par public.build_comments%rowtype;
--       new_id bigint;
--     begin
--       if public.is_guest(me) then
--         raise exception '비회원은 댓글을 달 수 없습니다. 구글·카카오를 연결하면 달 수 있습니다.' using errcode = '42501';
--       end if;
--       select * into bl from public.builds where id = p_build;
--       if not found or not public.build_open(bl.id) then
--         raise exception '빌드를 찾지 못했습니다. (숨겨졌거나 지워졌을 수 있습니다)' using errcode = 'P0002';
--       end if;
--       if p_parent is not null then
--         select * into par from public.build_comments where id = p_parent;
--         if not found or par.build_id <> bl.id or par.deleted_at is not null or par.status <> 'visible' then
--           raise exception '답글을 달 댓글을 찾지 못했습니다. (지워졌거나 숨겨졌을 수 있습니다)' using errcode = 'P0002';
--         end if;
--         if par.parent_id is not null then
--           raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
--         end if;
--       end if;
--       perform public.board_throttle(me, 'comment');
--       insert into public.build_comments (build_id, author_id, body, parent_id) values (bl.id, me, b, p_parent) returning id into new_id;
--       perform public.notify_new_comment('build', bl.id, bl.author_id, par.author_id, p_parent is not null);
--       return new_id;
--     end;
--     $$;
--
--     create function public.edit_build_comment(p_id bigint, p_body text)
--     returns void language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       me uuid := public.board_writer();
--       b text := public.board_text(p_body, '댓글', 1000);
--       c public.build_comments%rowtype := public.build_comment_for_update(p_id);
--     begin
--       if c.author_id is distinct from me then
--         raise exception '내 댓글만 고칠 수 있습니다.' using errcode = '42501';
--       end if;
--       if c.status <> 'visible' or not public.build_open(c.build_id) then
--         raise exception '숨긴 댓글·빌드는 고칠 수 없습니다.' using errcode = '23514';
--       end if;
--       perform public.require_edit_window('build_comment', c.created_at, c.edit_grace_until);
--       if b = c.body then
--         return;
--       end if;
--       update public.build_comments set body = b, edited_at = now() where id = c.id;
--     end;
--     $$;
--
--     create function public.delete_my_build_comment(p_id bigint)
--     returns void language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       me uuid := (select auth.uid());
--       c public.build_comments%rowtype := public.build_comment_for_update(p_id);
--     begin
--       if me is null or c.author_id is distinct from me then
--         raise exception '내 댓글만 지울 수 있습니다.' using errcode = '42501';
--       end if;
--       update public.build_comments set deleted_at = now(), deleted_by = me, delete_kind = 'author' where id = c.id;
--       update public.reports set status = 'dismissed', handled_at = now(), handled_note = '작성자가 댓글을 지움'
--        where build_comment_id = c.id and status = 'open';
--     end;
--     $$;
--
--     create function public.report_build_comment(p_id bigint, p_reason text, p_detail text default null)
--     returns void language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       me uuid := public.board_writer();
--       dt text := public.board_report_check(p_reason, p_detail);
--       c public.build_comments%rowtype;
--     begin
--       select * into c from public.build_comments where id = p_id;
--       if not found or c.status <> 'visible' or c.deleted_at is not null or not public.build_open(c.build_id) then
--         raise exception '신고할 수 없는 댓글입니다.' using errcode = 'P0002';
--       end if;
--       if c.author_id = me then
--         raise exception '내 댓글은 신고할 수 없습니다.' using errcode = '23514';
--       end if;
--       insert into public.reports (reporter_id, build_comment_id, reason, detail) values (me, c.id, p_reason, dt);
--     exception when unique_violation then
--       raise exception '이미 신고한 댓글입니다.' using errcode = '23505';
--     end;
--     $$;
--
--     create function public.hide_build_comment(p_id bigint, p_note text)
--     returns void language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       note text;
--       c public.build_comments%rowtype;
--     begin
--       perform public.require_staff();
--       note := public.require_note(p_note, '숨기는 이유');
--       c := public.build_comment_for_update(p_id);
--       perform public.require_moderate_target(c.author_id);
--       perform public.require_moderate_open_build(c.build_id);
--       if c.status = 'hidden' then
--         raise exception '이미 숨긴 댓글입니다.' using errcode = '23514';
--       end if;
--       update public.build_comments set status = 'hidden', hidden_note = note, hidden_at = now(), hidden_by = (select auth.uid())
--        where id = c.id;
--       update public.reports set status = 'resolved', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
--        where build_comment_id = c.id and status = 'open';
--       perform public.notify_build_comment(c.author_id, 'build_comment_hidden',
--         format('빌드에 쓴 내 댓글을 운영진이 숨겼습니다. 메모: %s', note), c.build_id);
--       perform public.log_moderation('hide', 'build_comment', c.id::text, note);
--     end;
--     $$;
--
--     create function public.restore_build_comment(p_id bigint, p_note text)
--     returns void language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       note text;
--       c public.build_comments%rowtype;
--     begin
--       perform public.require_staff();
--       note := public.require_note(p_note, '다시 공개 메모');
--       c := public.build_comment_for_update(p_id);
--       perform public.require_moderate_target(c.author_id);
--       perform public.require_moderate_open_build(c.build_id);
--       if c.status <> 'hidden' then
--         raise exception '숨긴 댓글이 아닙니다.' using errcode = '23514';
--       end if;
--       perform public.require_restore_allowed(c.hidden_by);
--       update public.build_comments set status = 'visible', hidden_note = null, hidden_at = null, hidden_by = null where id = c.id;
--       perform public.notify_build_comment(c.author_id, 'build_comment_restored',
--         format('숨겨졌던 빌드 댓글이 다시 공개됐습니다. 메모: %s', note), c.build_id);
--       perform public.log_moderation('restore', 'build_comment', c.id::text, note);
--     end;
--     $$;
--
--     create function public.staff_delete_build_comment(p_id bigint, p_note text)
--     returns void language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       me uuid := (select auth.uid());
--       note text;
--       c public.build_comments%rowtype;
--     begin
--       perform public.require_staff();
--       note := public.require_note(p_note, '삭제 이유');
--       c := public.build_comment_for_update(p_id);
--       perform public.require_moderate_target(c.author_id);
--       perform public.require_moderate_open_build(c.build_id);
--       update public.build_comments set deleted_at = now(), deleted_by = me, delete_kind = 'staff', delete_note = note where id = c.id;
--       update public.reports set status = 'resolved', handled_by = me, handled_at = now(), handled_note = note
--        where build_comment_id = c.id and status = 'open';
--       perform public.notify_build_comment(c.author_id, 'build_comment_deleted',
--         format('빌드에 쓴 내 댓글을 운영진이 삭제했습니다. 메모: %s', note), c.build_id);
--       perform public.log_moderation('delete', 'build_comment', c.id::text, note);
--     end;
--     $$;
--
--     revoke execute on function public.create_build_comment(bigint, text, bigint) from public, anon;
--     revoke execute on function public.edit_build_comment(bigint, text) from public, anon;
--     revoke execute on function public.delete_my_build_comment(bigint) from public, anon;
--     revoke execute on function public.report_build_comment(bigint, text, text) from public, anon;
--     revoke execute on function public.hide_build_comment(bigint, text) from public, anon;
--     revoke execute on function public.restore_build_comment(bigint, text) from public, anon;
--     revoke execute on function public.staff_delete_build_comment(bigint, text) from public, anon;
--     grant execute on function public.create_build_comment(bigint, text, bigint) to authenticated;
--     grant execute on function public.edit_build_comment(bigint, text) to authenticated;
--     grant execute on function public.delete_my_build_comment(bigint) to authenticated;
--     grant execute on function public.report_build_comment(bigint, text, text) to authenticated;
--     grant execute on function public.hide_build_comment(bigint, text) to authenticated;
--     grant execute on function public.restore_build_comment(bigint, text) to authenticated;
--     grant execute on function public.staff_delete_build_comment(bigint, text) to authenticated;
--     -- 4) 060이 바꾼 함수를 059 내용으로 (신고 기각은 인자 4개 -> 5개)
--     drop function public.dismiss_reports(bigint, bigint, text, bigint);
--     CREATE OR REPLACE FUNCTION public.dismiss_reports(p_post bigint, p_comment bigint, p_note text DEFAULT NULL::text, p_doc_comment bigint DEFAULT NULL::bigint, p_build_comment bigint DEFAULT NULL::bigint)
--      RETURNS integer
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       n integer;
--       who uuid;
--       doc_counter bigint;
--       bid bigint;
--     begin
--       perform public.require_staff();
--       if num_nonnulls(p_post, p_comment, p_doc_comment, p_build_comment) <> 1 then
--         raise exception '글이나 댓글 하나를 골라 주세요.' using errcode = '22023';
--       end if;
--       -- 감독관: 본인·운영진 대상 신고, 숨긴 상대법의 문서 댓글·숨긴 빌드의 빌드 댓글 신고는 처리할 수 없다
--       if public.is_moderator() then
--         if p_post is not null then
--           select author_id into who from public.posts where id = p_post;
--         elsif p_comment is not null then
--           select author_id into who from public.post_comments where id = p_comment;
--         elsif p_doc_comment is not null then
--           select author_id, counter_id into who, doc_counter from public.doc_comments where id = p_doc_comment;
--           perform public.require_moderate_doc_counter(doc_counter);
--         else
--           select author_id, build_id into who, bid from public.build_comments where id = p_build_comment;
--           perform public.require_moderate_open_build(bid);
--         end if;
--         perform public.require_moderate_target(who);
--       end if;
--       update public.reports
--       set status = 'dismissed', handled_by = (select auth.uid()), handled_at = now(),
--           handled_note = nullif(btrim(coalesce(p_note, '')), '')
--       where status = 'open'
--         and (post_id = p_post or comment_id = p_comment or doc_comment_id = p_doc_comment or build_comment_id = p_build_comment);
--       get diagnostics n = row_count;
--       if n = 0 then
--         raise exception '처리할 신고가 없습니다. (이미 처리됐을 수 있습니다)' using errcode = 'P0002';
--       end if;
--       perform public.log_moderation('dismiss_reports',
--         case when p_post is not null then 'post' when p_comment is not null then 'comment'
--              when p_doc_comment is not null then 'doc_comment' else 'build_comment' end,
--         coalesce(p_post, p_comment, p_doc_comment, p_build_comment)::text, nullif(btrim(coalesce(p_note, '')), ''));
--       return n;
--     end;
--     $function$;
--     revoke execute on function public.dismiss_reports(bigint, bigint, text, bigint, bigint) from public, anon;
--     grant execute on function public.dismiss_reports(bigint, bigint, text, bigint, bigint) to authenticated;
--     CREATE OR REPLACE FUNCTION public.begin_edit(p_kind text, p_id bigint)
--      RETURNS timestamp with time zone
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       author uuid;
--       created timestamptz;
--       grace timestamptz;
--       ok boolean;
--       base timestamptz;
--       new_grace timestamptz;
--     begin
--       if p_kind = 'post' then
--         select p.author_id, p.created_at, p.edit_grace_until, p.status = 'visible' and p.deleted_at is null
--           into author, created, grace, ok
--         from public.posts p where p.id = p_id for update;
--       elsif p_kind = 'comment' then
--         select c.author_id, c.created_at, c.edit_grace_until,
--                c.status = 'visible' and c.deleted_at is null and p.status = 'visible' and p.deleted_at is null
--           into author, created, grace, ok
--         from public.post_comments c join public.posts p on p.id = c.post_id where c.id = p_id for update of c;
--       elsif p_kind = 'doc_comment' then
--         select d.author_id, d.created_at, d.edit_grace_until, d.status = 'visible' and d.deleted_at is null and k.status = 'approved'
--           into author, created, grace, ok
--         from public.doc_comments d join public.counters k on k.id = d.counter_id where d.id = p_id for update of d;
--       elsif p_kind = 'build_comment' then  -- 058
--         select c.author_id, c.created_at, c.edit_grace_until, c.status = 'visible' and c.deleted_at is null and public.build_open(c.build_id)
--           into author, created, grace, ok
--         from public.build_comments c where c.id = p_id for update;
--       else
--         raise exception '알 수 없는 종류입니다.' using errcode = '22023';
--       end if;
--       if author is null then
--         raise exception '찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if author <> me then
--         raise exception '내 글·댓글만 고칠 수 있습니다.' using errcode = '42501';
--       end if;
--       if not ok then
--         raise exception '숨기거나 삭제된 글·댓글은 고칠 수 없습니다.' using errcode = '23514';
--       end if;
--
--       base := public.edit_deadline(p_kind, created, null);
--       if now() <= base then
--         new_grace := now() + make_interval(mins => public.xp_rule('edit_grace_minutes'));
--         if grace is null or new_grace > grace then
--           grace := new_grace;
--           if p_kind = 'post' then
--             update public.posts set edit_grace_until = grace where id = p_id;
--           elsif p_kind = 'comment' then
--             update public.post_comments set edit_grace_until = grace where id = p_id;
--           elsif p_kind = 'build_comment' then
--             update public.build_comments set edit_grace_until = grace where id = p_id;
--           else
--             update public.doc_comments set edit_grace_until = grace where id = p_id;
--           end if;
--         end if;
--       end if;
--       perform public.require_edit_window(p_kind, created, grace);
--       return public.edit_deadline(p_kind, created, grace);
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.open_reports_for_moderator()
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       result jsonb;
--     begin
--       if not public.is_moderator() then
--         raise exception '감독관만 쓰는 목록입니다.' using errcode = '42501';
--       end if;
--       with person as (
--         select id, jsonb_build_object('nickname', nickname, 'role', role, 'level', level, 'main_title', main_title, 'influencer', influencer, 'nickname_state', nickname_state, 'is_guest', is_guest) as j
--         from public.profiles
--       )
--       select coalesce(jsonb_agg(row_data order by created_at), '[]'::jsonb) into result
--       from (
--         select r.created_at, jsonb_build_object(
--           'id', r.id, 'post_id', r.post_id, 'comment_id', r.comment_id, 'doc_comment_id', r.doc_comment_id, 'build_comment_id', r.build_comment_id,
--           'reason', r.reason, 'detail', r.detail, 'created_at', r.created_at, 'reporter', null,
--           'post', case when p.id is not null then jsonb_build_object(
--             'id', p.id, 'title', p.title, 'body', p.body, 'status', p.status, 'deleted_at', p.deleted_at, 'author_id', p.author_id,
--             'author', (select j from person where id = p.author_id)) end,
--           'comment', case when c.id is not null then jsonb_build_object(
--             'id', c.id, 'post_id', c.post_id, 'body', c.body, 'status', c.status, 'author_id', c.author_id,
--             'author', (select j from person where id = c.author_id)) end,
--           'doc_comment', case when d.id is not null then jsonb_build_object(
--             'id', d.id, 'counter_id', d.counter_id, 'body', d.body, 'status', d.status, 'author_id', d.author_id,
--             'author', (select j from person where id = d.author_id),
--             'counter', jsonb_build_object('id', k.id, 'target_champion', k.target_champion, 'counter_champion', k.counter_champion, 'status', k.status)) end,
--           'build_comment', case when bc.id is not null then jsonb_build_object(
--             'id', bc.id, 'build_id', bc.build_id, 'body', bc.body, 'status', bc.status, 'author_id', bc.author_id,
--             'author', (select j from person where id = bc.author_id),
--             'build', jsonb_build_object('id', bb.id, 'name', bb.name, 'seq', bb.seq, 'status', bb.status,
--               'counter', jsonb_build_object('id', bk.id, 'target_champion', bk.target_champion, 'counter_champion', bk.counter_champion, 'status', bk.status))) end
--         ) as row_data
--         from public.reports r
--         left join public.posts p on p.id = r.post_id
--         left join public.post_comments c on c.id = r.comment_id
--         left join public.doc_comments d on d.id = r.doc_comment_id
--         left join public.counters k on k.id = d.counter_id
--         left join public.build_comments bc on bc.id = r.build_comment_id
--         left join public.builds bb on bb.id = bc.build_id
--         left join public.counters bk on bk.id = bb.counter_id
--         where r.status = 'open' and coalesce(p.deleted_at, c.deleted_at, d.deleted_at, bc.deleted_at) is null
--           and public.moderatable_author(coalesce(p.author_id, c.author_id, d.author_id, bc.author_id))
--           and (r.doc_comment_id is null or k.status = 'approved')
--           and (r.build_comment_id is null or public.build_open(bc.build_id))
--       ) x;
--       return result;
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.notify_staff_new_report()
--      RETURNS trigger
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       target_key text := case when new.post_id is not null then 'post:' || new.post_id
--                               when new.comment_id is not null then 'comment:' || new.comment_id
--                               when new.doc_comment_id is not null then 'doc_comment:' || new.doc_comment_id
--                               else 'build_comment:' || new.build_comment_id end;
--       kind_label text := case when new.post_id is not null then '글'
--                               when new.comment_id is not null then '댓글'
--                               when new.doc_comment_id is not null then '문서 댓글'
--                               else '빌드 댓글' end;
--       n_post bigint;
--       n_counter bigint;
--       author uuid;
--     begin
--       if new.status <> 'open' then
--         return null;
--       end if;
--       -- 같은 대상 동시 신고가 서로의 처리 전 신고를 못 봐서 둘 다 "처음"이 되지 않게 (잠금이 풀린 뒤 다음 조회가 새 줄을 본다)
--       perform pg_advisory_xact_lock(hashtext('report_received:' || target_key));
--       if exists (
--         select 1 from public.reports r
--          where r.status = 'open' and r.id <> new.id
--            and r.post_id is not distinct from new.post_id
--            and r.comment_id is not distinct from new.comment_id
--            and r.doc_comment_id is not distinct from new.doc_comment_id
--            and r.build_comment_id is not distinct from new.build_comment_id) then
--         return null;
--       end if;
--
--       if new.post_id is not null then
--         n_post := new.post_id;
--         select p.author_id into author from public.posts p where p.id = new.post_id;
--       elsif new.comment_id is not null then
--         select c.post_id, c.author_id into n_post, author from public.post_comments c where c.id = new.comment_id;
--       elsif new.doc_comment_id is not null then
--         select d.counter_id, d.author_id into n_counter, author from public.doc_comments d where d.id = new.doc_comment_id;
--       else
--         select b.counter_id, c.author_id into n_counter, author
--           from public.build_comments c join public.builds b on b.id = c.build_id where c.id = new.build_comment_id;
--       end if;
--
--       insert into public.notifications (user_id, kind, message, post_id, counter_id)
--       select u.id, 'report_received', format('새 신고가 들어왔습니다. (%s)', kind_label), n_post, n_counter
--         from public.profiles u
--        where u.id is distinct from new.reporter_id
--          and (u.role = 'admin'
--               or (u.role = 'moderator'
--                   -- 감독관이 처리할 수 있는 대상만 (030 moderatable_author: 작성자가 일반 회원이거나 탈퇴)
--                   and (author is null or exists (select 1 from public.profiles a where a.id = author and a.role = 'user'))
--                   and u.id is distinct from author));
--       return null;
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.xp_should_have(p_user uuid)
--      RETURNS TABLE(source_key text, kind text, ref_id text, amount integer, at timestamp with time zone, target_champion text, counter_champion text)
--      LANGUAGE sql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--       -- 새 상대법(예전 승인 제안): 승인 + 상대법 공개 중 (숨기면 0, 다시 공개·재승인하면 같은 키로 돌아온다)
--       select 'proposal:' || p.id, 'new_counter', p.id::text, public.xp_rule('new_counter'), p.reviewed_at, p.target_champion, p.counter_champion
--       from public.edit_proposals p join public.counters c on c.id = p.counter_id
--       where p.proposer_id = p_user and p.type = 'new_counter' and p.status = 'approved' and c.status = 'approved'
--       union all
--       -- 문서 수정(예전 승인 제안): 승인 + 상대법이 있음 (숨김은 회수하지 않고 완전 삭제만)
--       select 'proposal:' || p.id, 'doc_edit', p.id::text, public.xp_rule('doc_edit'), p.reviewed_at, p.target_champion, p.counter_champion
--       from public.edit_proposals p join public.counters c on c.id = p.counter_id
--       where p.proposer_id = p_user and p.type = 'doc_edit' and p.status = 'approved'
--       union all
--       -- 빌드(예전 승인): 공개 중, 새 상대법의 첫 빌드는 상대법 +100에 포함
--       select 'build:' || b.id, 'build', b.id::text, public.xp_rule('build'), b.reviewed_at, c.target_champion, c.counter_champion
--       from public.builds b join public.counters c on c.id = b.counter_id
--       where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null and not b.wiki
--       union all
--       -- 위키 등록(038): 새 상대법 +100(공개 중, 첫 빌드 포함) · 새 빌드 +30(공개 중, 첫 빌드 제외)
--       --   그날(한국 시간) 먼저 등록한 순서대로 합계 create_daily_cap까지 — 하나가 숨겨지면 다음 것이 들어온다
--       select w.source_key, w.kind, w.ref_id, w.amount, w.at, w.target_champion, w.counter_champion
--       from (
--         select k.*, sum(k.amount) over (
--           partition by (k.at at time zone 'Asia/Seoul')::date order by k.at, k.source_key) as run
--         from (
--           select 'matchup:' || c.id as source_key, 'new_matchup' as kind, c.id::text as ref_id, public.xp_rule('new_counter') as amount,
--                  c.created_at as at, c.target_champion, c.counter_champion
--           from public.counters c
--           where c.proposed_by = p_user and c.wiki and c.status = 'approved'
--           union all
--           select 'build:' || b.id, 'build', b.id::text, public.xp_rule('build'), b.created_at, c.target_champion, c.counter_champion
--           from public.builds b join public.counters c on c.id = b.counter_id
--           where b.author_id = p_user and b.wiki and b.status = 'approved' and b.id is distinct from c.first_build_id
--         ) k
--       ) w
--       where w.run <= coalesce(public.xp_rule('create_daily_cap'), 200)
--       union all
--       -- 추천: 처음 누른 추천만, 받은 사람 기준 하루(한국 시간) 상한 — 상한은 지워진 빌드의 추천까지 넣고 센다
--       select 'vote:' || v.id, 'vote', v.build_id::text, public.xp_rule('vote'), v.created_at, c.target_champion, c.counter_champion
--       from (
--         select l.*, row_number() over (
--           partition by (l.created_at at time zone 'Asia/Seoul')::date order by l.created_at, l.id) as rn
--         from public.build_vote_log l
--         where l.author_id = p_user and l.first_up
--       ) v
--       join public.builds b on b.id = v.build_id
--       join public.counters c on c.id = b.counter_id
--       where v.rn <= public.xp_rule('vote_daily_cap') / greatest(public.xp_rule('vote'), 1)
--       union all
--       -- 게시판 글: 보이는 글(숨김·삭제 아님)을 그날(한국 시간) 먼저 쓴 순서대로 상한까지
--       select 'post:' || p.id, 'post', p.id::text, public.xp_rule('post'), p.created_at, null::text, null::text
--       from (
--         select p.id, p.created_at, row_number() over (
--           partition by (p.created_at at time zone 'Asia/Seoul')::date order by p.created_at, p.id) as rn
--         from public.posts p
--         where p.author_id = p_user and p.status = 'visible' and p.deleted_at is null
--       ) p
--       where p.rn <= public.xp_rule('post_daily_cap') / greatest(public.xp_rule('post'), 1)
--       union all
--       -- 댓글: 게시판 댓글·답글 + 문서 댓글 + 빌드 댓글·답글(058)(숨김·삭제 아님)을 합쳐 그날 먼저 쓴 순서대로 상한까지
--       select x.source_key, x.kind, x.ref_id, public.xp_rule('comment'), x.created_at, x.target_champion, x.counter_champion
--       from (
--         select y.*, row_number() over (
--           partition by (y.created_at at time zone 'Asia/Seoul')::date order by y.created_at, y.kind, y.id) as rn
--         from (
--           select 'comment:' || c.id as source_key, 'comment' as kind, c.id::text as ref_id, c.id, c.created_at,
--                  null::text as target_champion, null::text as counter_champion
--           from public.post_comments c
--           where c.author_id = p_user and c.status = 'visible' and c.deleted_at is null
--           union all
--           select 'doc_comment:' || d.id, 'doc_comment', d.counter_id || ':' || d.id, d.id, d.created_at, k.target_champion, k.counter_champion
--           from public.doc_comments d join public.counters k on k.id = d.counter_id
--           where d.author_id = p_user and d.status = 'visible' and d.deleted_at is null
--           union all
--           select 'build_comment:' || bc.id, 'build_comment', bc.build_id || ':' || bc.id, bc.id, bc.created_at, k.target_champion, k.counter_champion
--           from public.build_comments bc join public.builds b on b.id = bc.build_id join public.counters k on k.id = b.counter_id
--           where bc.author_id = p_user and bc.status = 'visible' and bc.deleted_at is null
--         ) y
--       ) x
--       where x.rn <= public.xp_rule('comment_daily_cap') / greatest(public.xp_rule('comment'), 1);
--     $function$;
--     CREATE OR REPLACE FUNCTION public.xp_reason(p_kind text, p_ref text, p_want integer, p_have integer, p_seen boolean)
--      RETURNS text
--      LANGUAGE plpgsql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       st text;
--       cst text;
--       del timestamptz;
--     begin
--       if p_want > 0 and p_have > 0 then
--         return '규칙 변경';
--       end if;
--       if p_want > 0 then
--         return case when p_seen then '다시 공개·승인' else null end;
--       end if;
--       -- 회수
--       if p_kind in ('new_counter', 'doc_edit') then
--         select p.status, c.status into st, cst
--         from public.edit_proposals p left join public.counters c on c.id = p.counter_id where p.id = p_ref::bigint;
--         if not found or cst is null then return '상대법 삭제'; end if;
--         if st = 'revoked' or cst = 'hidden' then return '상대법 숨김 (승인 취소)'; end if;
--         return '승인 취소';
--       elsif p_kind = 'new_matchup' then  -- 038
--         select status into cst from public.counters where id = p_ref::bigint;
--         if not found then return '상대법 삭제'; end if;
--         if cst = 'hidden' then return '상대법 숨김'; end if;
--         return '규칙 변경';
--       elsif p_kind = 'build' then
--         select status into st from public.builds where id = p_ref::bigint;
--         if not found then return '상대법 삭제'; end if;
--         if st = 'hidden' then return '빌드 숨김'; end if;
--         return '승인 취소';
--       elsif p_kind = 'vote' then
--         if not exists (select 1 from public.builds where id = p_ref::bigint) then return '빌드 삭제 (상대법 삭제)'; end if;
--         return '규칙 변경';
--       elsif p_kind = 'post' then
--         select status, deleted_at into st, del from public.posts where id = p_ref::bigint;
--         if not found or del is not null then return '글 삭제'; end if;
--         if st = 'hidden' then return '글 숨김'; end if;
--         return '규칙 변경';
--       elsif p_kind = 'comment' then
--         select status, deleted_at into st, del from public.post_comments where id = p_ref::bigint;
--         if not found or del is not null then return '댓글 삭제'; end if;
--         if st = 'hidden' then return '댓글 숨김'; end if;
--         return '규칙 변경';
--       elsif p_kind = 'doc_comment' then
--         if not exists (select 1 from public.counters where id = split_part(p_ref, ':', 1)::bigint) then return '상대법 삭제'; end if;
--         select status, deleted_at into st, del from public.doc_comments where id = split_part(p_ref, ':', 2)::bigint;
--         if not found or del is not null then return '댓글 삭제'; end if;
--         if st = 'hidden' then return '댓글 숨김'; end if;
--         return '규칙 변경';
--       elsif p_kind = 'build_comment' then  -- 058
--         if not exists (select 1 from public.builds where id = split_part(p_ref, ':', 1)::bigint) then return '빌드 삭제 (상대법 삭제)'; end if;
--         select status, deleted_at into st, del from public.build_comments where id = split_part(p_ref, ':', 2)::bigint;
--         if not found or del is not null then return '댓글 삭제'; end if;
--         if st = 'hidden' then return '댓글 숨김'; end if;
--         return '규칙 변경';
--       end if;
--       return null;
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.has_visible_writing(p_user uuid)
--      RETURNS boolean
--      LANGUAGE sql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--       select exists (select 1 from public.posts where author_id = p_user and status = 'visible' and deleted_at is null)
--           or exists (select 1 from public.post_comments where author_id = p_user and status = 'visible' and deleted_at is null)
--           or exists (select 1 from public.doc_comments where author_id = p_user and status = 'visible' and deleted_at is null)
--           or exists (select 1 from public.build_comments where author_id = p_user and status = 'visible' and deleted_at is null);
--     $function$;
--     CREATE OR REPLACE FUNCTION public.guest_has_records(p_user uuid)
--      RETURNS boolean
--      LANGUAGE sql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--       select exists (select 1 from public.posts where author_id = p_user)
--           or exists (select 1 from public.post_comments where author_id = p_user)
--           or exists (select 1 from public.doc_comments where author_id = p_user)
--           or exists (select 1 from public.build_comments where author_id = p_user)
--           or exists (select 1 from public.edit_proposals where proposer_id = p_user)
--           or exists (select 1 from public.builds where author_id = p_user);
--     $function$;
--     CREATE OR REPLACE FUNCTION public.admin_member_info(p_user uuid)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       u public.profiles%rowtype;
--     begin
--       perform public.require_operator();
--       select * into u from public.profiles where id = p_user;
--       if not found then
--         raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       return jsonb_build_object(
--         'id', u.id, 'nickname', u.nickname, 'role', u.role, 'level', u.level, 'main_title', u.main_title, 'influencer', u.influencer, 'nickname_state', u.nickname_state,
--         'is_guest', u.is_guest, 'created_at', u.created_at,
--         -- 가입 방식: provider 이름만 (구글·카카오). 로그인 ID·이메일은 읽지 않는다
--         'providers', coalesce((
--           select jsonb_agg(provider order by provider)
--             from (select distinct provider from auth.identities where user_id = u.id and provider in ('google', 'kakao')) s
--         ), '[]'::jsonb),
--         'titles', coalesce((select jsonb_agg(title_key order by title_key) from public.user_titles where user_id = u.id), '[]'::jsonb),
--         'proposals', (select count(*) from public.edit_proposals where proposer_id = u.id),
--         'posts', (select count(*) from public.posts where author_id = u.id and deleted_at is null),
--         'builds', (select count(*) from public.builds where author_id = u.id),
--         'comments', (select count(*) from public.post_comments where author_id = u.id and deleted_at is null)
--                   + (select count(*) from public.doc_comments where author_id = u.id and deleted_at is null)
--                   + (select count(*) from public.build_comments where author_id = u.id and deleted_at is null),
--         'deleted_posts', (select count(*) from public.posts where author_id = u.id and deleted_at is not null),
--         'deleted_comments', (select count(*) from public.post_comments where author_id = u.id and deleted_at is not null)
--                           + (select count(*) from public.doc_comments where author_id = u.id and deleted_at is not null)
--                           + (select count(*) from public.build_comments where author_id = u.id and deleted_at is not null)
--       );
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.admin_deleted_writings(p_user uuid)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--     begin
--       perform public.require_operator();
--       return jsonb_build_object(
--         'keep_days', coalesce(public.xp_rule('deleted_writing_keep_days'), 365),
--         'posts', coalesce((
--           select jsonb_agg(jsonb_build_object(
--             'id', p.id, 'title', p.title, 'body', p.body, 'created_at', p.created_at, 'status', p.status,
--             'deleted_at', p.deleted_at, 'delete_kind', p.delete_kind, 'delete_note', p.delete_note,
--             'deleted_by', (select jsonb_build_object('nickname', x.nickname, 'role', x.role) from public.profiles x where x.id = p.deleted_by),
--             'comment_count', (select count(*) from public.post_comments c where c.post_id = p.id and c.deleted_at is null)
--           ) order by p.deleted_at desc, p.id desc)
--           from public.posts p where p.author_id = p_user and p.deleted_at is not null
--         ), '[]'::jsonb),
--         'comments', coalesce((
--           select jsonb_agg(jsonb_build_object(
--             'id', c.id, 'post_id', c.post_id, 'post_title', p.title, 'post_deleted', p.deleted_at is not null,
--             'body', c.body, 'created_at', c.created_at, 'status', c.status,
--             'deleted_at', c.deleted_at, 'delete_kind', c.delete_kind, 'delete_note', c.delete_note,
--             'deleted_by', (select jsonb_build_object('nickname', x.nickname, 'role', x.role) from public.profiles x where x.id = c.deleted_by)
--           ) order by c.deleted_at desc, c.id desc)
--           from public.post_comments c join public.posts p on p.id = c.post_id
--           where c.author_id = p_user and c.deleted_at is not null
--         ), '[]'::jsonb),
--         'doc_comments', coalesce((
--           select jsonb_agg(jsonb_build_object(
--             'id', d.id, 'counter_id', d.counter_id, 'target_champion', k.target_champion, 'counter_champion', k.counter_champion,
--             'body', d.body, 'created_at', d.created_at, 'status', d.status,
--             'deleted_at', d.deleted_at, 'delete_kind', d.delete_kind, 'delete_note', d.delete_note,
--             'deleted_by', (select jsonb_build_object('nickname', x.nickname, 'role', x.role) from public.profiles x where x.id = d.deleted_by)
--           ) order by d.deleted_at desc, d.id desc)
--           from public.doc_comments d join public.counters k on k.id = d.counter_id
--           where d.author_id = p_user and d.deleted_at is not null
--         ), '[]'::jsonb),
--         'build_comments', coalesce((  -- 058
--           select jsonb_agg(jsonb_build_object(
--             'id', bc.id, 'build_id', bc.build_id, 'build_name', b.name, 'build_seq', b.seq,
--             'counter_id', b.counter_id, 'target_champion', k.target_champion, 'counter_champion', k.counter_champion,
--             'body', bc.body, 'created_at', bc.created_at, 'status', bc.status,
--             'deleted_at', bc.deleted_at, 'delete_kind', bc.delete_kind, 'delete_note', bc.delete_note,
--             'deleted_by', (select jsonb_build_object('nickname', x.nickname, 'role', x.role) from public.profiles x where x.id = bc.deleted_by)
--           ) order by bc.deleted_at desc, bc.id desc)
--           from public.build_comments bc join public.builds b on b.id = bc.build_id join public.counters k on k.id = b.counter_id
--           where bc.author_id = p_user and bc.deleted_at is not null
--         ), '[]'::jsonb)
--       );
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.admin_member_detail_unchecked(p_user uuid, p_limit integer)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       lim integer := least(greatest(coalesce(p_limit, 30), 1), 100);
--       info jsonb;
--     begin
--       info := public.admin_member_info(p_user);  -- 없는 회원이면 여기서 '회원을 찾지 못했습니다.' (P0002)
--       return jsonb_build_object(
--         'info', info || jsonb_build_object(
--           'xp', (select xp from public.profiles where id = p_user),
--           'matchups', (select count(*) from public.counters where proposed_by = p_user and status = 'approved')),
--         -- 쓴 글 (지운 것 제외)
--         'posts', coalesce((
--           select jsonb_agg(jsonb_build_object(
--             'id', x.id, 'title', x.title, 'excerpt', left(x.body, 200), 'created_at', x.created_at, 'status', x.status,
--             'comment_count', x.comment_count) order by x.created_at desc, x.id desc)
--           from (
--             select p.id, p.title, p.body, p.created_at, p.status,
--                    (select count(*) from public.post_comments c where c.post_id = p.id and c.deleted_at is null) as comment_count
--               from public.posts p
--              where p.author_id = p_user and p.deleted_at is null
--              order by p.created_at desc, p.id desc limit lim
--           ) x
--         ), '[]'::jsonb),
--         -- 쓴 댓글: 게시판 댓글(지운 글 밑 제외) + 문서(상대법) 댓글 + 빌드 댓글(058) (지운 것 제외)
--         'comments', coalesce((
--           select jsonb_agg(jsonb_build_object(
--             'kind', x.kind, 'id', x.id, 'post_id', x.post_id, 'post_title', x.post_title,
--             'counter_id', x.counter_id, 'target_champion', x.target_champion, 'counter_champion', x.counter_champion,
--             'build_id', x.build_id,
--             'excerpt', left(x.body, 200), 'created_at', x.created_at, 'status', x.status)
--             order by x.created_at desc, x.kind, x.id desc)
--           from (
--             select * from (
--               select 'post' as kind, c.id, c.post_id, p.title as post_title, null::bigint as counter_id,
--                      null::text as target_champion, null::text as counter_champion, null::bigint as build_id, c.body, c.created_at, c.status
--                 from public.post_comments c join public.posts p on p.id = c.post_id
--                where c.author_id = p_user and c.deleted_at is null and p.deleted_at is null
--               union all
--               select 'doc', d.id, null::bigint, null::text, d.counter_id, k.target_champion, k.counter_champion, null::bigint, d.body, d.created_at, d.status
--                 from public.doc_comments d join public.counters k on k.id = d.counter_id
--                where d.author_id = p_user and d.deleted_at is null
--               union all
--               select 'build', bc.id, null::bigint, null::text, b.counter_id, k.target_champion, k.counter_champion, bc.build_id, bc.body, bc.created_at, bc.status
--                 from public.build_comments bc join public.builds b on b.id = bc.build_id join public.counters k on k.id = b.counter_id
--                where bc.author_id = p_user and bc.deleted_at is null
--             ) u order by u.created_at desc, u.id desc limit lim
--           ) x
--         ), '[]'::jsonb),
--         -- 고친 빌드 (build_editors: 시초가 아니라 고친 사람)
--         'edited_builds', coalesce((
--           select jsonb_agg(jsonb_build_object(
--             'build_id', x.build_id, 'seq', x.seq, 'name', x.name, 'status', x.status, 'counter_id', x.counter_id,
--             'target_champion', x.target_champion, 'counter_champion', x.counter_champion,
--             'edits', x.edits, 'first_at', x.first_at, 'last_at', x.last_at) order by x.last_at desc, x.build_id desc)
--           from (
--             select e.build_id, b.seq, b.name, b.status, b.counter_id, k.target_champion, k.counter_champion, e.edits, e.first_at, e.last_at
--               from public.build_editors e
--               join public.builds b on b.id = e.build_id
--               join public.counters k on k.id = b.counter_id
--              where e.user_id = p_user
--              order by e.last_at desc, e.build_id desc limit lim
--           ) x
--         ), '[]'::jsonb),
--         -- 처리 이력: 이 회원이 대상인 줄 (회원 자신 · 쓴 글 · 쓴 댓글 · 쓴 문서 댓글 · 쓴 빌드 댓글 · 낸 제안). 처리자가 탈퇴했으면 "탈퇴한 이용자"
--         'moderation', coalesce((
--           select jsonb_agg(jsonb_build_object(
--             'id', x.id, 'action', x.action, 'target_kind', x.target_kind, 'target_id', x.target_id, 'note', x.note,
--             'created_at', x.created_at, 'actor_role', x.actor_role,
--             'actor_nickname', case when x.actor_id is not null and not exists (select 1 from public.profiles a where a.id = x.actor_id)
--                                    then '탈퇴한 이용자' else x.actor_nickname end,
--             'actor_withdrawn', x.actor_id is not null and not exists (select 1 from public.profiles a where a.id = x.actor_id))
--             order by x.created_at desc, x.id desc)
--           from (
--             select l.* from public.moderation_log l
--              where (l.target_kind = 'user' and l.target_id = p_user::text)
--                 or (l.target_kind = 'post' and l.target_id in (select id::text from public.posts where author_id = p_user))
--                 or (l.target_kind = 'comment' and l.target_id in (select id::text from public.post_comments where author_id = p_user))
--                 or (l.target_kind = 'doc_comment' and l.target_id in (select id::text from public.doc_comments where author_id = p_user))
--                 or (l.target_kind = 'build_comment' and l.target_id in (select id::text from public.build_comments where author_id = p_user))
--                 or (l.target_kind = 'proposal' and l.target_id in (select id::text from public.edit_proposals where proposer_id = p_user))
--              order by l.created_at desc, l.id desc limit lim
--           ) x
--         ), '[]'::jsonb)
--       );
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.log_hide()
--      RETURNS trigger
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       k text := case tg_table_name when 'posts' then 'post' when 'post_comments' then 'comment'
--                                    when 'build_comments' then 'build_comment' else 'doc_comment' end;
--     begin
--       if new.status = 'hidden' and old.status is distinct from 'hidden' and new.author_id is not null then
--         insert into public.hide_log (author_id, kind, target_id) values (new.author_id, k, new.id);
--       elsif old.status = 'hidden' and new.status is distinct from 'hidden' then
--         update public.hide_log set unhidden_at = now()
--          where kind = k and target_id = new.id and unhidden_at is null;
--       end if;
--       return new;
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.check_comment_depth()
--      RETURNS trigger
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       grand bigint;
--       has_child boolean;
--     begin
--       if new.parent_id is null then
--         return new;
--       end if;
--       if new.parent_id = new.id then
--         raise exception '댓글은 자기 자신에게 답글을 달 수 없습니다.' using errcode = '23514';
--       end if;
--       if tg_table_name = 'post_comments' then
--         select parent_id into grand from public.post_comments where id = new.parent_id;
--         has_child := tg_op = 'UPDATE' and exists (select 1 from public.post_comments where parent_id = new.id);
--       elsif tg_table_name = 'doc_comments' then  -- 059
--         select parent_id into grand from public.doc_comments where id = new.parent_id;
--         has_child := tg_op = 'UPDATE' and exists (select 1 from public.doc_comments where parent_id = new.id);
--       else
--         select parent_id into grand from public.build_comments where id = new.parent_id;
--         has_child := tg_op = 'UPDATE' and exists (select 1 from public.build_comments where parent_id = new.id);
--       end if;
--       if grand is not null or has_child then
--         raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
--       end if;
--       return new;
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.notify_new_comment(p_kind text, p_target bigint, p_owner uuid, p_parent_author uuid, p_is_reply boolean)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--       lq text := chr(12300);  -- 낫표 여는 것 (SQL Editor에 붙여도 깨지지 않게 코드 번호로)
--       rq text := chr(12301);
--       what text;      -- 낫표로 감싼 글 제목 또는 빌드 이름 (문서는 없음 - 화면이 매치업 이름을 붙인다)
--       ctr bigint;     -- 빌드·문서 댓글이면 상대법 id (알림 링크)
--       n public.notifications%rowtype;
--       cnt integer;
--     begin
--       if p_kind = 'post' then
--         select lq || public.post_snippet(title) || rq into what from public.posts where id = p_target;
--       elsif p_kind = 'doc' then
--         ctr := p_target;
--       else
--         select counter_id into ctr from public.builds where id = p_target;
--         what := lq || public.post_snippet(public.build_label(p_target)) || rq;
--       end if;
--
--       -- 답글 -> 부모 댓글 작성자
--       if p_is_reply and p_parent_author is not null and p_parent_author is distinct from me then
--         select * into n from public.notifications
--          where user_id = p_parent_author and kind = 'comment_reply' and read_at is null
--            and ((p_kind = 'post' and post_id = p_target)
--                 or (p_kind = 'build' and build_id = p_target)
--                 or (p_kind = 'doc' and counter_id = p_target and post_id is null and build_id is null))
--          order by created_at limit 1 for update;
--         if found then
--           if p_kind = 'post' then
--             select count(*) into cnt from public.post_comments r join public.post_comments pc on pc.id = r.parent_id
--              where r.post_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
--                and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
--           elsif p_kind = 'doc' then
--             select count(*) into cnt from public.doc_comments r join public.doc_comments pc on pc.id = r.parent_id
--              where r.counter_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
--                and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
--           else
--             select count(*) into cnt from public.build_comments r join public.build_comments pc on pc.id = r.parent_id
--              where r.build_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
--                and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
--           end if;
--           update public.notifications
--              set message = case when p_kind = 'doc' then format('상대법 문서에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', greatest(cnt, 2))
--                                 else format('%s에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', case when p_kind = 'build' then '빌드 ' else '' end || what, greatest(cnt, 2)) end
--            where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, post_id, build_id, counter_id)
--           values (p_parent_author, 'comment_reply',
--                   case when p_kind = 'doc' then '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.'
--                        else format('%s에 쓴 내 댓글에 새 답글이 달렸습니다.', case when p_kind = 'build' then '빌드 ' else '' end || what) end,
--                   case when p_kind = 'post' then p_target end, case when p_kind = 'build' then p_target end, ctr);
--         end if;
--       end if;
--
--       -- 글·빌드 주인, 문서는 상대법을 처음 제안한 분 (답글의 부모 작성자와 같은 사람이면 위 알림 하나로)
--       if p_owner is null or p_owner = me or (p_is_reply and p_owner is not distinct from p_parent_author) then
--         return;
--       end if;
--       if p_kind = 'post' then
--         select * into n from public.notifications
--          where user_id = p_owner and kind = 'post_comment' and post_id = p_target and read_at is null
--          order by created_at limit 1 for update;
--         if found then
--           select count(*) into cnt from public.post_comments
--            where post_id = p_target and author_id is distinct from p_owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
--           update public.notifications set message = format('내 글 %s에 새 댓글 %s개가 달렸습니다.', what, greatest(cnt, 2)) where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, post_id)
--           values (p_owner, 'post_comment', format('내 글 %s에 새 댓글이 달렸습니다.', what), p_target);
--         end if;
--       elsif p_kind = 'doc' then  -- 059: 016의 create_doc_comment에 있던 알림을 여기로 (문장 그대로, 답글도 센다)
--         select * into n from public.notifications
--          where user_id = p_owner and kind = 'doc_comment' and counter_id = p_target and read_at is null
--          order by created_at limit 1 for update;
--         if found then
--           select count(*) into cnt from public.doc_comments
--            where counter_id = p_target and author_id is distinct from p_owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
--           update public.notifications set message = format('내가 제안한 상대법 문서에 새 댓글 %s개가 달렸습니다.', greatest(cnt, 2)) where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, counter_id)
--           values (p_owner, 'doc_comment', '내가 제안한 상대법 문서에 새 댓글이 달렸습니다.', p_target);
--         end if;
--       else
--         select * into n from public.notifications
--          where user_id = p_owner and kind = 'build_comment' and build_id = p_target and read_at is null
--          order by created_at limit 1 for update;
--         if found then
--           select count(*) into cnt from public.build_comments
--            where build_id = p_target and author_id is distinct from p_owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
--           update public.notifications set message = format('내 빌드 %s에 새 댓글 %s개가 달렸습니다.', what, greatest(cnt, 2)) where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, build_id, counter_id)
--           values (p_owner, 'build_comment', format('내 빌드 %s에 새 댓글이 달렸습니다.', what), p_target, ctr);
--         end if;
--       end if;
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.board_on_profile_delete()
--      RETURNS trigger
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     begin
--       -- 058: 댓글 (탑신병자 커뮤니티 + 빌드)
--       with shells as (
--         update public.post_comments c
--            set body = '', deleted_at = coalesce(c.deleted_at, now()), delete_kind = coalesce(c.delete_kind, 'author'),
--                delete_note = null, hidden_note = null
--          where c.author_id = old.id
--            and exists (select 1 from public.post_comments r
--                         where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null)
--         returning c.id)
--       delete from public.reports where comment_id in (select id from shells);
--       delete from public.post_comments c
--        where c.author_id = old.id
--          and not exists (select 1 from public.post_comments r
--                           where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null);
--       with shells as (
--         update public.build_comments c
--            set body = '', deleted_at = coalesce(c.deleted_at, now()), delete_kind = coalesce(c.delete_kind, 'author'),
--                delete_note = null, hidden_note = null
--          where c.author_id = old.id
--            and exists (select 1 from public.build_comments r
--                         where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null)
--         returning c.id)
--       delete from public.reports where build_comment_id in (select id from shells);
--       delete from public.build_comments c
--        where c.author_id = old.id
--          and not exists (select 1 from public.build_comments r
--                           where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null);
--       -- 059: 문서 댓글
--       with shells as (
--         update public.doc_comments c
--            set body = '', deleted_at = coalesce(c.deleted_at, now()), delete_kind = coalesce(c.delete_kind, 'author'),
--                delete_note = null, hidden_note = null
--          where c.author_id = old.id
--            and exists (select 1 from public.doc_comments r
--                         where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null)
--         returning c.id)
--       delete from public.reports where doc_comment_id in (select id from shells);
--       delete from public.doc_comments c
--        where c.author_id = old.id
--          and not exists (select 1 from public.doc_comments r
--                           where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null);
--
--       -- 글 (040 그대로)
--       update public.posts p
--          set title = '', body = '', deleted_at = coalesce(p.deleted_at, now()), delete_kind = coalesce(p.delete_kind, 'author'),
--              delete_note = null, up_count = 0
--        where p.author_id = old.id
--          and exists (select 1 from public.post_comments c where c.post_id = p.id and c.author_id <> old.id);
--       delete from public.posts p
--        where p.author_id = old.id
--          and not exists (select 1 from public.post_comments c where c.post_id = p.id and c.author_id <> old.id);
--       return old;
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.purge_deleted_writings()
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       before timestamptz := now() - make_interval(days => coalesce(public.xp_rule('deleted_writing_keep_days'), 365));
--       n_doc integer;
--       n_comment integer;
--       n_build_comment integer;
--       n_post integer;
--     begin
--       perform set_config('app.quiet_rewards', 'on', true);  -- 이 거래 안에서만: rewards_on_post가 알림 없이 다시 계산
--       delete from public.doc_comments c
--        where c.deleted_at < before
--          and not exists (select 1 from public.doc_comments r where r.parent_id = c.id and (r.deleted_at is null or r.deleted_at >= before));
--       get diagnostics n_doc = row_count;
--       delete from public.post_comments c
--        where c.deleted_at < before
--          and not exists (select 1 from public.post_comments r where r.parent_id = c.id and (r.deleted_at is null or r.deleted_at >= before));
--       get diagnostics n_comment = row_count;
--       delete from public.build_comments c
--        where c.deleted_at < before
--          and not exists (select 1 from public.build_comments r where r.parent_id = c.id and (r.deleted_at is null or r.deleted_at >= before));
--       get diagnostics n_build_comment = row_count;
--       delete from public.posts where deleted_at < before;  -- 그 아래 다른 사람 댓글·사진·신고·알림도 함께
--       get diagnostics n_post = row_count;
--       return jsonb_build_object('posts', n_post, 'comments', n_comment, 'doc_comments', n_doc, 'build_comments', n_build_comment);
--     end;
--     $function$;
--     commit;
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. 안전장치: 빌드 댓글과 그 기록이 하나라도 있으면 아무것도 바꾸지 않고 멈춘다
--    (운영 DB 확인 결과 모두 0 = A안 "지움"이지만 지울 행이 없다. 그 사이 생겼으면 알려 주세요)
-- ---------------------------------------------------------------------
do $guard$
declare
  n_comments bigint := (select count(*) from public.build_comments);
  n_reports bigint := (select count(*) from public.reports where build_comment_id is not null);
  n_hide bigint := (select count(*) from public.hide_log where kind = 'build_comment');
  n_mod bigint := (select count(*) from public.moderation_log where target_kind = 'build_comment');
  n_notes bigint := (select count(*) from public.notifications
                      where kind in ('build_comment', 'build_comment_hidden', 'build_comment_restored', 'build_comment_deleted')
                         or (kind = 'comment_reply' and build_id is not null));
  n_xp bigint := (select count(*) from public.xp_events where type = 'build_comment');
begin
  if n_comments + n_reports + n_hide + n_mod + n_notes + n_xp > 0 then
    raise exception '060을 멈춥니다 (아무것도 바뀌지 않았습니다). 빌드 댓글 %줄, 신고 %줄, 숨김 기록 %줄, 처리 기록 %줄, 알림 %줄, 경험치 기록 %줄이 있습니다. check_build_comments.sql 결과를 알려 주세요.',
      n_comments, n_reports, n_hide, n_mod, n_notes, n_xp using errcode = 'P0001';
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------
-- 1. 빌드 댓글을 모르던 057 내용으로 되돌리는 함수 (058이 빌드 댓글 분기만 더했던 것 - 로컬에서 057·059 내용을 비교해 확인)
--    신고 기각은 인자 5개 -> 4개 (새 화면은 원래 4개만 보낸다)
-- ---------------------------------------------------------------------
drop function public.dismiss_reports(bigint, bigint, text, bigint, bigint);
CREATE OR REPLACE FUNCTION public.dismiss_reports(p_post bigint, p_comment bigint, p_note text DEFAULT NULL::text, p_doc_comment bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  n integer;
  who uuid;
  doc_counter bigint;
begin
  perform public.require_staff();
  if num_nonnulls(p_post, p_comment, p_doc_comment) <> 1 then
    raise exception '글이나 댓글 하나를 골라 주세요.' using errcode = '22023';
  end if;
  -- 감독관: 본인·운영진 대상 신고, 숨긴 상대법의 문서 댓글 신고는 처리할 수 없다
  if public.is_moderator() then
    if p_post is not null then
      select author_id into who from public.posts where id = p_post;
    elsif p_comment is not null then
      select author_id into who from public.post_comments where id = p_comment;
    else
      select author_id, counter_id into who, doc_counter from public.doc_comments where id = p_doc_comment;
      perform public.require_moderate_doc_counter(doc_counter);
    end if;
    perform public.require_moderate_target(who);
  end if;
  update public.reports
  set status = 'dismissed', handled_by = (select auth.uid()), handled_at = now(),
      handled_note = nullif(btrim(coalesce(p_note, '')), '')
  where status = 'open' and (post_id = p_post or comment_id = p_comment or doc_comment_id = p_doc_comment);
  get diagnostics n = row_count;
  if n = 0 then
    raise exception '처리할 신고가 없습니다. (이미 처리됐을 수 있습니다)' using errcode = 'P0002';
  end if;
  perform public.log_moderation('dismiss_reports',
    case when p_post is not null then 'post' when p_comment is not null then 'comment' else 'doc_comment' end,
    coalesce(p_post, p_comment, p_doc_comment)::text, nullif(btrim(coalesce(p_note, '')), ''));
  return n;
end;
$function$;
revoke execute on function public.dismiss_reports(bigint, bigint, text, bigint) from public, anon;
grant execute on function public.dismiss_reports(bigint, bigint, text, bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.begin_edit(p_kind text, p_id bigint)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := public.board_writer();
  author uuid;
  created timestamptz;
  grace timestamptz;
  ok boolean;
  base timestamptz;
  new_grace timestamptz;
begin
  if p_kind = 'post' then
    select p.author_id, p.created_at, p.edit_grace_until, p.status = 'visible' and p.deleted_at is null
      into author, created, grace, ok
    from public.posts p where p.id = p_id for update;
  elsif p_kind = 'comment' then
    select c.author_id, c.created_at, c.edit_grace_until,
           c.status = 'visible' and c.deleted_at is null and p.status = 'visible' and p.deleted_at is null
      into author, created, grace, ok
    from public.post_comments c join public.posts p on p.id = c.post_id where c.id = p_id for update of c;
  elsif p_kind = 'doc_comment' then
    select d.author_id, d.created_at, d.edit_grace_until, d.status = 'visible' and d.deleted_at is null and k.status = 'approved'
      into author, created, grace, ok
    from public.doc_comments d join public.counters k on k.id = d.counter_id where d.id = p_id for update of d;
  else
    raise exception '알 수 없는 종류입니다.' using errcode = '22023';
  end if;
  if author is null then
    raise exception '찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if author <> me then
    raise exception '내 글·댓글만 고칠 수 있습니다.' using errcode = '42501';
  end if;
  if not ok then
    raise exception '숨기거나 삭제된 글·댓글은 고칠 수 없습니다.' using errcode = '23514';
  end if;

  base := public.edit_deadline(p_kind, created, null);
  if now() <= base then
    new_grace := now() + make_interval(mins => public.xp_rule('edit_grace_minutes'));
    if grace is null or new_grace > grace then
      grace := new_grace;
      if p_kind = 'post' then
        update public.posts set edit_grace_until = grace where id = p_id;
      elsif p_kind = 'comment' then
        update public.post_comments set edit_grace_until = grace where id = p_id;
      else
        update public.doc_comments set edit_grace_until = grace where id = p_id;
      end if;
    end if;
  end if;
  perform public.require_edit_window(p_kind, created, grace);
  return public.edit_deadline(p_kind, created, grace);
end;
$function$;

CREATE OR REPLACE FUNCTION public.open_reports_for_moderator()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  result jsonb;
begin
  if not public.is_moderator() then
    raise exception '감독관만 쓰는 목록입니다.' using errcode = '42501';
  end if;
  with person as (
    select id, jsonb_build_object('nickname', nickname, 'role', role, 'level', level, 'main_title', main_title, 'influencer', influencer, 'nickname_state', nickname_state, 'is_guest', is_guest) as j
    from public.profiles
  )
  select coalesce(jsonb_agg(row_data order by created_at), '[]'::jsonb) into result
  from (
    select r.created_at, jsonb_build_object(
      'id', r.id, 'post_id', r.post_id, 'comment_id', r.comment_id, 'doc_comment_id', r.doc_comment_id,
      'reason', r.reason, 'detail', r.detail, 'created_at', r.created_at, 'reporter', null,
      'post', case when p.id is not null then jsonb_build_object(
        'id', p.id, 'title', p.title, 'body', p.body, 'status', p.status, 'deleted_at', p.deleted_at, 'author_id', p.author_id,
        'author', (select j from person where id = p.author_id)) end,
      'comment', case when c.id is not null then jsonb_build_object(
        'id', c.id, 'post_id', c.post_id, 'body', c.body, 'status', c.status, 'author_id', c.author_id,
        'author', (select j from person where id = c.author_id)) end,
      'doc_comment', case when d.id is not null then jsonb_build_object(
        'id', d.id, 'counter_id', d.counter_id, 'body', d.body, 'status', d.status, 'author_id', d.author_id,
        'author', (select j from person where id = d.author_id),
        'counter', jsonb_build_object('id', k.id, 'target_champion', k.target_champion, 'counter_champion', k.counter_champion, 'status', k.status)) end
    ) as row_data
    from public.reports r
    left join public.posts p on p.id = r.post_id
    left join public.post_comments c on c.id = r.comment_id
    left join public.doc_comments d on d.id = r.doc_comment_id
    left join public.counters k on k.id = d.counter_id
    where r.status = 'open' and coalesce(p.deleted_at, c.deleted_at, d.deleted_at) is null
      and public.moderatable_author(coalesce(p.author_id, c.author_id, d.author_id))
      and (r.doc_comment_id is null or k.status = 'approved')
  ) x;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_staff_new_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target_key text := case when new.post_id is not null then 'post:' || new.post_id
                          when new.comment_id is not null then 'comment:' || new.comment_id
                          else 'doc_comment:' || new.doc_comment_id end;
  kind_label text := case when new.post_id is not null then '글'
                          when new.comment_id is not null then '댓글'
                          else '문서 댓글' end;
  n_post bigint;
  n_counter bigint;
  author uuid;
begin
  if new.status <> 'open' then
    return null;
  end if;
  -- 같은 대상 동시 신고가 서로의 처리 전 신고를 못 봐서 둘 다 "처음"이 되지 않게 (잠금이 풀린 뒤 다음 조회가 새 줄을 본다)
  perform pg_advisory_xact_lock(hashtext('report_received:' || target_key));
  if exists (
    select 1 from public.reports r
     where r.status = 'open' and r.id <> new.id
       and r.post_id is not distinct from new.post_id
       and r.comment_id is not distinct from new.comment_id
       and r.doc_comment_id is not distinct from new.doc_comment_id) then
    return null;
  end if;

  if new.post_id is not null then
    n_post := new.post_id;
    select p.author_id into author from public.posts p where p.id = new.post_id;
  elsif new.comment_id is not null then
    select c.post_id, c.author_id into n_post, author from public.post_comments c where c.id = new.comment_id;
  else
    select d.counter_id, d.author_id into n_counter, author from public.doc_comments d where d.id = new.doc_comment_id;
  end if;

  insert into public.notifications (user_id, kind, message, post_id, counter_id)
  select u.id, 'report_received', format('새 신고가 들어왔습니다. (%s)', kind_label), n_post, n_counter
    from public.profiles u
   where u.id is distinct from new.reporter_id
     and (u.role = 'admin'
          or (u.role = 'moderator'
              -- 감독관이 처리할 수 있는 대상만 (030 moderatable_author: 작성자가 일반 회원이거나 탈퇴)
              and (author is null or exists (select 1 from public.profiles a where a.id = author and a.role = 'user'))
              and u.id is distinct from author));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.xp_should_have(p_user uuid)
 RETURNS TABLE(source_key text, kind text, ref_id text, amount integer, at timestamp with time zone, target_champion text, counter_champion text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 새 상대법(예전 승인 제안): 승인 + 상대법 공개 중 (숨기면 0, 다시 공개·재승인하면 같은 키로 돌아온다)
  select 'proposal:' || p.id, 'new_counter', p.id::text, public.xp_rule('new_counter'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'new_counter' and p.status = 'approved' and c.status = 'approved'
  union all
  -- 문서 수정(예전 승인 제안): 승인 + 상대법이 있음 (숨김은 회수하지 않고 완전 삭제만)
  select 'proposal:' || p.id, 'doc_edit', p.id::text, public.xp_rule('doc_edit'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'doc_edit' and p.status = 'approved'
  union all
  -- 빌드(예전 승인): 공개 중, 새 상대법의 첫 빌드는 상대법 +100에 포함
  select 'build:' || b.id, 'build', b.id::text, public.xp_rule('build'), b.reviewed_at, c.target_champion, c.counter_champion
  from public.builds b join public.counters c on c.id = b.counter_id
  where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null and not b.wiki
  union all
  -- 위키 등록(038): 새 상대법 +100(공개 중, 첫 빌드 포함) · 새 빌드 +30(공개 중, 첫 빌드 제외)
  --   그날(한국 시간) 먼저 등록한 순서대로 합계 create_daily_cap까지 — 하나가 숨겨지면 다음 것이 들어온다
  select w.source_key, w.kind, w.ref_id, w.amount, w.at, w.target_champion, w.counter_champion
  from (
    select k.*, sum(k.amount) over (
      partition by (k.at at time zone 'Asia/Seoul')::date order by k.at, k.source_key) as run
    from (
      select 'matchup:' || c.id as source_key, 'new_matchup' as kind, c.id::text as ref_id, public.xp_rule('new_counter') as amount,
             c.created_at as at, c.target_champion, c.counter_champion
      from public.counters c
      where c.proposed_by = p_user and c.wiki and c.status = 'approved'
      union all
      select 'build:' || b.id, 'build', b.id::text, public.xp_rule('build'), b.created_at, c.target_champion, c.counter_champion
      from public.builds b join public.counters c on c.id = b.counter_id
      where b.author_id = p_user and b.wiki and b.status = 'approved' and b.id is distinct from c.first_build_id
    ) k
  ) w
  where w.run <= coalesce(public.xp_rule('create_daily_cap'), 200)
  union all
  -- 추천: 처음 누른 추천만, 받은 사람 기준 하루(한국 시간) 상한 — 상한은 지워진 빌드의 추천까지 넣고 센다
  select 'vote:' || v.id, 'vote', v.build_id::text, public.xp_rule('vote'), v.created_at, c.target_champion, c.counter_champion
  from (
    select l.*, row_number() over (
      partition by (l.created_at at time zone 'Asia/Seoul')::date order by l.created_at, l.id) as rn
    from public.build_vote_log l
    where l.author_id = p_user and l.first_up
  ) v
  join public.builds b on b.id = v.build_id
  join public.counters c on c.id = b.counter_id
  where v.rn <= public.xp_rule('vote_daily_cap') / greatest(public.xp_rule('vote'), 1)
  union all
  -- 게시판 글: 보이는 글(숨김·삭제 아님)을 그날(한국 시간) 먼저 쓴 순서대로 상한까지
  select 'post:' || p.id, 'post', p.id::text, public.xp_rule('post'), p.created_at, null::text, null::text
  from (
    select p.id, p.created_at, row_number() over (
      partition by (p.created_at at time zone 'Asia/Seoul')::date order by p.created_at, p.id) as rn
    from public.posts p
    where p.author_id = p_user and p.status = 'visible' and p.deleted_at is null
  ) p
  where p.rn <= public.xp_rule('post_daily_cap') / greatest(public.xp_rule('post'), 1)
  union all
  -- 댓글: 게시판 댓글 + 문서 댓글(숨김·삭제 아님)을 합쳐 그날 먼저 쓴 순서대로 상한까지
  select x.source_key, x.kind, x.ref_id, public.xp_rule('comment'), x.created_at, x.target_champion, x.counter_champion
  from (
    select y.*, row_number() over (
      partition by (y.created_at at time zone 'Asia/Seoul')::date order by y.created_at, y.kind, y.id) as rn
    from (
      select 'comment:' || c.id as source_key, 'comment' as kind, c.id::text as ref_id, c.id, c.created_at,
             null::text as target_champion, null::text as counter_champion
      from public.post_comments c
      where c.author_id = p_user and c.status = 'visible' and c.deleted_at is null
      union all
      select 'doc_comment:' || d.id, 'doc_comment', d.counter_id || ':' || d.id, d.id, d.created_at, k.target_champion, k.counter_champion
      from public.doc_comments d join public.counters k on k.id = d.counter_id
      where d.author_id = p_user and d.status = 'visible' and d.deleted_at is null
    ) y
  ) x
  where x.rn <= public.xp_rule('comment_daily_cap') / greatest(public.xp_rule('comment'), 1);
$function$;

CREATE OR REPLACE FUNCTION public.xp_reason(p_kind text, p_ref text, p_want integer, p_have integer, p_seen boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  st text;
  cst text;
  del timestamptz;
begin
  if p_want > 0 and p_have > 0 then
    return '규칙 변경';
  end if;
  if p_want > 0 then
    return case when p_seen then '다시 공개·승인' else null end;
  end if;
  -- 회수
  if p_kind in ('new_counter', 'doc_edit') then
    select p.status, c.status into st, cst
    from public.edit_proposals p left join public.counters c on c.id = p.counter_id where p.id = p_ref::bigint;
    if not found or cst is null then return '상대법 삭제'; end if;
    if st = 'revoked' or cst = 'hidden' then return '상대법 숨김 (승인 취소)'; end if;
    return '승인 취소';
  elsif p_kind = 'new_matchup' then  -- 038
    select status into cst from public.counters where id = p_ref::bigint;
    if not found then return '상대법 삭제'; end if;
    if cst = 'hidden' then return '상대법 숨김'; end if;
    return '규칙 변경';
  elsif p_kind = 'build' then
    select status into st from public.builds where id = p_ref::bigint;
    if not found then return '상대법 삭제'; end if;
    if st = 'hidden' then return '빌드 숨김'; end if;
    return '승인 취소';
  elsif p_kind = 'vote' then
    if not exists (select 1 from public.builds where id = p_ref::bigint) then return '빌드 삭제 (상대법 삭제)'; end if;
    return '규칙 변경';
  elsif p_kind = 'post' then
    select status, deleted_at into st, del from public.posts where id = p_ref::bigint;
    if not found or del is not null then return '글 삭제'; end if;
    if st = 'hidden' then return '글 숨김'; end if;
    return '규칙 변경';
  elsif p_kind = 'comment' then
    select status, deleted_at into st, del from public.post_comments where id = p_ref::bigint;
    if not found or del is not null then return '댓글 삭제'; end if;
    if st = 'hidden' then return '댓글 숨김'; end if;
    return '규칙 변경';
  elsif p_kind = 'doc_comment' then
    if not exists (select 1 from public.counters where id = split_part(p_ref, ':', 1)::bigint) then return '상대법 삭제'; end if;
    select status, deleted_at into st, del from public.doc_comments where id = split_part(p_ref, ':', 2)::bigint;
    if not found or del is not null then return '댓글 삭제'; end if;
    if st = 'hidden' then return '댓글 숨김'; end if;
    return '규칙 변경';
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.has_visible_writing(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from public.posts where author_id = p_user and status = 'visible' and deleted_at is null)
      or exists (select 1 from public.post_comments where author_id = p_user and status = 'visible' and deleted_at is null)
      or exists (select 1 from public.doc_comments where author_id = p_user and status = 'visible' and deleted_at is null);
$function$;

CREATE OR REPLACE FUNCTION public.guest_has_records(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from public.posts where author_id = p_user)
      or exists (select 1 from public.post_comments where author_id = p_user)
      or exists (select 1 from public.doc_comments where author_id = p_user)
      or exists (select 1 from public.edit_proposals where proposer_id = p_user)
      or exists (select 1 from public.builds where author_id = p_user);
$function$;

CREATE OR REPLACE FUNCTION public.admin_member_info(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  u public.profiles%rowtype;
begin
  perform public.require_operator();
  select * into u from public.profiles where id = p_user;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'id', u.id, 'nickname', u.nickname, 'role', u.role, 'level', u.level, 'main_title', u.main_title, 'influencer', u.influencer, 'nickname_state', u.nickname_state,
    'is_guest', u.is_guest, 'created_at', u.created_at,
    -- 가입 방식: provider 이름만 (구글·카카오). 로그인 ID·이메일은 읽지 않는다
    'providers', coalesce((
      select jsonb_agg(provider order by provider)
        from (select distinct provider from auth.identities where user_id = u.id and provider in ('google', 'kakao')) s
    ), '[]'::jsonb),
    'titles', coalesce((select jsonb_agg(title_key order by title_key) from public.user_titles where user_id = u.id), '[]'::jsonb),
    'proposals', (select count(*) from public.edit_proposals where proposer_id = u.id),
    'posts', (select count(*) from public.posts where author_id = u.id and deleted_at is null),
    'builds', (select count(*) from public.builds where author_id = u.id),
    'comments', (select count(*) from public.post_comments where author_id = u.id and deleted_at is null)
              + (select count(*) from public.doc_comments where author_id = u.id and deleted_at is null),
    'deleted_posts', (select count(*) from public.posts where author_id = u.id and deleted_at is not null),
    'deleted_comments', (select count(*) from public.post_comments where author_id = u.id and deleted_at is not null)
                      + (select count(*) from public.doc_comments where author_id = u.id and deleted_at is not null)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_deleted_writings(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
begin
  perform public.require_operator();
  return jsonb_build_object(
    'keep_days', coalesce(public.xp_rule('deleted_writing_keep_days'), 365),
    'posts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'title', p.title, 'body', p.body, 'created_at', p.created_at, 'status', p.status,
        'deleted_at', p.deleted_at, 'delete_kind', p.delete_kind, 'delete_note', p.delete_note,
        'deleted_by', (select jsonb_build_object('nickname', x.nickname, 'role', x.role) from public.profiles x where x.id = p.deleted_by),
        'comment_count', (select count(*) from public.post_comments c where c.post_id = p.id and c.deleted_at is null)
      ) order by p.deleted_at desc, p.id desc)
      from public.posts p where p.author_id = p_user and p.deleted_at is not null
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'post_id', c.post_id, 'post_title', p.title, 'post_deleted', p.deleted_at is not null,
        'body', c.body, 'created_at', c.created_at, 'status', c.status,
        'deleted_at', c.deleted_at, 'delete_kind', c.delete_kind, 'delete_note', c.delete_note,
        'deleted_by', (select jsonb_build_object('nickname', x.nickname, 'role', x.role) from public.profiles x where x.id = c.deleted_by)
      ) order by c.deleted_at desc, c.id desc)
      from public.post_comments c join public.posts p on p.id = c.post_id
      where c.author_id = p_user and c.deleted_at is not null
    ), '[]'::jsonb),
    'doc_comments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'counter_id', d.counter_id, 'target_champion', k.target_champion, 'counter_champion', k.counter_champion,
        'body', d.body, 'created_at', d.created_at, 'status', d.status,
        'deleted_at', d.deleted_at, 'delete_kind', d.delete_kind, 'delete_note', d.delete_note,
        'deleted_by', (select jsonb_build_object('nickname', x.nickname, 'role', x.role) from public.profiles x where x.id = d.deleted_by)
      ) order by d.deleted_at desc, d.id desc)
      from public.doc_comments d join public.counters k on k.id = d.counter_id
      where d.author_id = p_user and d.deleted_at is not null
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_member_detail_unchecked(p_user uuid, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  lim integer := least(greatest(coalesce(p_limit, 30), 1), 100);
  info jsonb;
begin
  info := public.admin_member_info(p_user);  -- 없는 회원이면 여기서 '회원을 찾지 못했습니다.' (P0002)
  return jsonb_build_object(
    'info', info || jsonb_build_object(
      'xp', (select xp from public.profiles where id = p_user),
      'matchups', (select count(*) from public.counters where proposed_by = p_user and status = 'approved')),
    -- 쓴 글 (지운 것 제외)
    'posts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id, 'title', x.title, 'excerpt', left(x.body, 200), 'created_at', x.created_at, 'status', x.status,
        'comment_count', x.comment_count) order by x.created_at desc, x.id desc)
      from (
        select p.id, p.title, p.body, p.created_at, p.status,
               (select count(*) from public.post_comments c where c.post_id = p.id and c.deleted_at is null) as comment_count
          from public.posts p
         where p.author_id = p_user and p.deleted_at is null
         order by p.created_at desc, p.id desc limit lim
      ) x
    ), '[]'::jsonb),
    -- 쓴 댓글: 게시판 댓글(지운 글 밑 제외) + 문서(상대법) 댓글 (지운 것 제외)
    'comments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', x.kind, 'id', x.id, 'post_id', x.post_id, 'post_title', x.post_title,
        'counter_id', x.counter_id, 'target_champion', x.target_champion, 'counter_champion', x.counter_champion,
        'excerpt', left(x.body, 200), 'created_at', x.created_at, 'status', x.status)
        order by x.created_at desc, x.kind, x.id desc)
      from (
        select * from (
          select 'post' as kind, c.id, c.post_id, p.title as post_title, null::bigint as counter_id,
                 null::text as target_champion, null::text as counter_champion, c.body, c.created_at, c.status
            from public.post_comments c join public.posts p on p.id = c.post_id
           where c.author_id = p_user and c.deleted_at is null and p.deleted_at is null
          union all
          select 'doc', d.id, null::bigint, null::text, d.counter_id, k.target_champion, k.counter_champion, d.body, d.created_at, d.status
            from public.doc_comments d join public.counters k on k.id = d.counter_id
           where d.author_id = p_user and d.deleted_at is null
        ) u order by u.created_at desc, u.id desc limit lim
      ) x
    ), '[]'::jsonb),
    -- 고친 빌드 (build_editors: 시초가 아니라 고친 사람)
    'edited_builds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'build_id', x.build_id, 'seq', x.seq, 'name', x.name, 'status', x.status, 'counter_id', x.counter_id,
        'target_champion', x.target_champion, 'counter_champion', x.counter_champion,
        'edits', x.edits, 'first_at', x.first_at, 'last_at', x.last_at) order by x.last_at desc, x.build_id desc)
      from (
        select e.build_id, b.seq, b.name, b.status, b.counter_id, k.target_champion, k.counter_champion, e.edits, e.first_at, e.last_at
          from public.build_editors e
          join public.builds b on b.id = e.build_id
          join public.counters k on k.id = b.counter_id
         where e.user_id = p_user
         order by e.last_at desc, e.build_id desc limit lim
      ) x
    ), '[]'::jsonb),
    -- 처리 이력: 이 회원이 대상인 줄 (회원 자신 · 쓴 글 · 쓴 댓글 · 쓴 문서 댓글 · 낸 제안). 처리자가 탈퇴했으면 "탈퇴한 이용자"
    'moderation', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id, 'action', x.action, 'target_kind', x.target_kind, 'target_id', x.target_id, 'note', x.note,
        'created_at', x.created_at, 'actor_role', x.actor_role,
        'actor_nickname', case when x.actor_id is not null and not exists (select 1 from public.profiles a where a.id = x.actor_id)
                               then '탈퇴한 이용자' else x.actor_nickname end,
        'actor_withdrawn', x.actor_id is not null and not exists (select 1 from public.profiles a where a.id = x.actor_id))
        order by x.created_at desc, x.id desc)
      from (
        select l.* from public.moderation_log l
         where (l.target_kind = 'user' and l.target_id = p_user::text)
            or (l.target_kind = 'post' and l.target_id in (select id::text from public.posts where author_id = p_user))
            or (l.target_kind = 'comment' and l.target_id in (select id::text from public.post_comments where author_id = p_user))
            or (l.target_kind = 'doc_comment' and l.target_id in (select id::text from public.doc_comments where author_id = p_user))
            or (l.target_kind = 'proposal' and l.target_id in (select id::text from public.edit_proposals where proposer_id = p_user))
         order by l.created_at desc, l.id desc limit lim
      ) x
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.log_hide()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  k text := case tg_table_name when 'posts' then 'post' when 'post_comments' then 'comment' else 'doc_comment' end;
begin
  if new.status = 'hidden' and old.status is distinct from 'hidden' and new.author_id is not null then
    insert into public.hide_log (author_id, kind, target_id) values (new.author_id, k, new.id);
  elsif old.status = 'hidden' and new.status is distinct from 'hidden' then
    update public.hide_log set unhidden_at = now()
     where kind = k and target_id = new.id and unhidden_at is null;
  end if;
  return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. 058·059에서 커뮤니티 답글·문서 댓글 답글과 함께 바꾼 함수: 빌드 댓글 부분만 뺀다
-- ---------------------------------------------------------------------
-- 2단계 막기: 탑신병자 커뮤니티 댓글·문서 댓글만 (빌드 댓글 분기 뺌)
create or replace function public.check_comment_depth()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  grand bigint;
  has_child boolean;
begin
  if new.parent_id is null then
    return new;
  end if;
  if new.parent_id = new.id then
    raise exception '댓글은 자기 자신에게 답글을 달 수 없습니다.' using errcode = '23514';
  end if;
  if tg_table_name = 'post_comments' then
    select parent_id into grand from public.post_comments where id = new.parent_id;
    has_child := tg_op = 'UPDATE' and exists (select 1 from public.post_comments where parent_id = new.id);
  else  -- doc_comments (059)
    select parent_id into grand from public.doc_comments where id = new.parent_id;
    has_child := tg_op = 'UPDATE' and exists (select 1 from public.doc_comments where parent_id = new.id);
  end if;
  if grand is not null or has_child then
    raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- 새 댓글·답글 알림: 글('post')·문서('doc')만 (빌드 분기 뺌, 인자 모양은 그대로)
create or replace function public.notify_new_comment(p_kind text, p_target bigint, p_owner uuid, p_parent_author uuid, p_is_reply boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  lq text := chr(12300);  -- 낫표 여는 것 (SQL Editor에 붙여도 깨지지 않게 코드 번호로)
  rq text := chr(12301);
  what text;      -- 낫표로 감싼 글 제목 (문서는 없음 - 화면이 매치업 이름을 붙인다)
  n public.notifications%rowtype;
  cnt integer;
begin
  if p_kind = 'post' then
    select lq || public.post_snippet(title) || rq into what from public.posts where id = p_target;
  end if;

  -- 답글 -> 부모 댓글 작성자
  if p_is_reply and p_parent_author is not null and p_parent_author is distinct from me then
    select * into n from public.notifications
     where user_id = p_parent_author and kind = 'comment_reply' and read_at is null
       and ((p_kind = 'post' and post_id = p_target)
            or (p_kind = 'doc' and counter_id = p_target and post_id is null and build_id is null))
     order by created_at limit 1 for update;
    if found then
      if p_kind = 'post' then
        select count(*) into cnt from public.post_comments r join public.post_comments pc on pc.id = r.parent_id
         where r.post_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
           and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
      else
        select count(*) into cnt from public.doc_comments r join public.doc_comments pc on pc.id = r.parent_id
         where r.counter_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
           and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
      end if;
      update public.notifications
         set message = case when p_kind = 'doc' then format('상대법 문서에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', greatest(cnt, 2))
                            else format('%s에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', what, greatest(cnt, 2)) end
       where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, post_id, counter_id)
      values (p_parent_author, 'comment_reply',
              case when p_kind = 'doc' then '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.'
                   else format('%s에 쓴 내 댓글에 새 답글이 달렸습니다.', what) end,
              case when p_kind = 'post' then p_target end, case when p_kind = 'doc' then p_target end);
    end if;
  end if;

  -- 글 주인, 문서는 상대법을 처음 제안한 분 (답글의 부모 작성자와 같은 사람이면 위 알림 하나로)
  if p_owner is null or p_owner = me or (p_is_reply and p_owner is not distinct from p_parent_author) then
    return;
  end if;
  if p_kind = 'post' then
    select * into n from public.notifications
     where user_id = p_owner and kind = 'post_comment' and post_id = p_target and read_at is null
     order by created_at limit 1 for update;
    if found then
      select count(*) into cnt from public.post_comments
       where post_id = p_target and author_id is distinct from p_owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
      update public.notifications set message = format('내 글 %s에 새 댓글 %s개가 달렸습니다.', what, greatest(cnt, 2)) where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, post_id)
      values (p_owner, 'post_comment', format('내 글 %s에 새 댓글이 달렸습니다.', what), p_target);
    end if;
  else
    select * into n from public.notifications
     where user_id = p_owner and kind = 'doc_comment' and counter_id = p_target and read_at is null
     order by created_at limit 1 for update;
    if found then
      select count(*) into cnt from public.doc_comments
       where counter_id = p_target and author_id is distinct from p_owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
      update public.notifications set message = format('내가 제안한 상대법 문서에 새 댓글 %s개가 달렸습니다.', greatest(cnt, 2)) where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, counter_id)
      values (p_owner, 'doc_comment', '내가 제안한 상대법 문서에 새 댓글이 달렸습니다.', p_target);
    end if;
  end if;
end;
$$;

-- 탈퇴: 탑신병자 커뮤니티 댓글·문서 댓글 껍데기 (빌드 댓글 부분 뺌), 글은 그대로
create or replace function public.board_on_profile_delete()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  -- 058: 탑신병자 커뮤니티 댓글 - 다른 사람의 남은 답글이 달린 내 댓글은 껍데기(작성자는 FK가 비움), 나머지는 삭제
  with shells as (
    update public.post_comments c
       set body = '', deleted_at = coalesce(c.deleted_at, now()), delete_kind = coalesce(c.delete_kind, 'author'),
           delete_note = null, hidden_note = null
     where c.author_id = old.id
       and exists (select 1 from public.post_comments r
                    where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null)
    returning c.id)
  delete from public.reports where comment_id in (select id from shells);
  delete from public.post_comments c
   where c.author_id = old.id
     and not exists (select 1 from public.post_comments r
                      where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null);
  -- 059: 문서 댓글 (같은 규칙)
  with shells as (
    update public.doc_comments c
       set body = '', deleted_at = coalesce(c.deleted_at, now()), delete_kind = coalesce(c.delete_kind, 'author'),
           delete_note = null, hidden_note = null
     where c.author_id = old.id
       and exists (select 1 from public.doc_comments r
                    where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null)
    returning c.id)
  delete from public.reports where doc_comment_id in (select id from shells);
  delete from public.doc_comments c
   where c.author_id = old.id
     and not exists (select 1 from public.doc_comments r
                      where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null);

  -- 글 (040 그대로)
  update public.posts p
     set title = '', body = '', deleted_at = coalesce(p.deleted_at, now()), delete_kind = coalesce(p.delete_kind, 'author'),
         delete_note = null, up_count = 0
   where p.author_id = old.id
     and exists (select 1 from public.post_comments c where c.post_id = p.id and c.author_id <> old.id);
  delete from public.posts p
   where p.author_id = old.id
     and not exists (select 1 from public.post_comments c where c.post_id = p.id and c.author_id <> old.id);
  return old;
end;
$$;

-- 1년 정리: 빌드 댓글 빼고 (결과도 057처럼 posts·comments·doc_comments). 남은 답글이 있는 부모는 남긴다
create or replace function public.purge_deleted_writings()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  before timestamptz := now() - make_interval(days => coalesce(public.xp_rule('deleted_writing_keep_days'), 365));
  n_doc integer;
  n_comment integer;
  n_post integer;
begin
  perform set_config('app.quiet_rewards', 'on', true);  -- 이 거래 안에서만: rewards_on_post가 알림 없이 다시 계산
  delete from public.doc_comments c
   where c.deleted_at < before
     and not exists (select 1 from public.doc_comments r where r.parent_id = c.id and (r.deleted_at is null or r.deleted_at >= before));
  get diagnostics n_doc = row_count;
  delete from public.post_comments c
   where c.deleted_at < before
     and not exists (select 1 from public.post_comments r where r.parent_id = c.id and (r.deleted_at is null or r.deleted_at >= before));
  get diagnostics n_comment = row_count;
  delete from public.posts where deleted_at < before;  -- 그 아래 다른 사람 댓글·사진·신고·알림도 함께
  get diagnostics n_post = row_count;
  return jsonb_build_object('posts', n_post, 'comments', n_comment, 'doc_comments', n_doc);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 빌드 댓글 함수·표·칸 지우기 (트리거·정책·인덱스는 표와 함께 사라진다)
-- ---------------------------------------------------------------------
drop function public.create_build_comment(bigint, text, bigint);
drop function public.edit_build_comment(bigint, text);
drop function public.delete_my_build_comment(bigint);
drop function public.report_build_comment(bigint, text, text);
drop function public.hide_build_comment(bigint, text);
drop function public.restore_build_comment(bigint, text);
drop function public.staff_delete_build_comment(bigint, text);
drop function public.notify_build_comment(uuid, text, text, bigint);
drop function public.build_comment_for_update(bigint);
drop function public.require_moderate_open_build(bigint);
drop function public.build_label(bigint);
alter table public.reports drop column build_comment_id;  -- reports_once_build_comment·reports_one_target(4개 칸 검사)도 함께 빠진다
alter table public.reports add constraint reports_one_target check (num_nonnulls(post_id, comment_id, doc_comment_id) = 1);
drop table public.build_comments;
drop function public.build_comments_after();
drop function public.build_open(bigint);
alter table public.builds drop column comment_count;

-- ---------------------------------------------------------------------
-- 4. 종류 목록에서 빌드 댓글 빼기 (답글 알림 comment_reply는 글·문서 답글에 그대로 쓴다)
-- ---------------------------------------------------------------------
alter table public.hide_log drop constraint hide_log_kind_check;
alter table public.hide_log add constraint hide_log_kind_check check (kind in ('post', 'comment', 'doc_comment'));
alter table public.moderation_log drop constraint moderation_log_target_kind_check;
alter table public.moderation_log add constraint moderation_log_target_kind_check check (target_kind in (
  'post', 'comment', 'doc_comment', 'proposal', 'user', 'inquiry', 'build', 'wiki_report', 'influencer_application', 'link', 'link_domain'));
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
  'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
  'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
  'matchup_created', 'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created',
  'error_reported', 'error_report_handled', 'report_received',
  'influencer_applied', 'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
  'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
  'followed_build_created', 'notice_posted', 'new_followers',
  'comment_reply'  -- 058: 글·문서 댓글 답글 (알림함만)
]));

commit;
