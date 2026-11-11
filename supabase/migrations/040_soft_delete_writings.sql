-- =====================================================================
-- 040: 글·댓글 삭제 방식 변경 (상대법 = 빌드 묶음 3단계, SPEC 6-27)
--   - 작성자 삭제: 자유게시판 글·댓글, 문서 댓글을 바로 지우지 않고 "지움" 표시(deleted_at·deleted_by·delete_kind='author')만 남긴다.
--     지운 것은 운영자를 포함해 모든 화면(목록·상세·검색·개수·사진)에서 바로 사라지고 "삭제된 글" 자리도 남지 않는다.
--     지운 글에 달린 다른 사람 댓글은 글과 함께 안 보인다(그 사람들 경험치는 유지).
--   - 운영진 삭제: staff_delete_post·staff_delete_comment·staff_delete_doc_comment (메모 필수, 처리 기록 'delete', 작성자 알림 — 푸시 없음).
--     감독관은 일반 회원의 것만 (숨기기와 같은 규칙). 운영자 모드를 끄면 DB가 거부.
--   - 운영자 조회: admin_deleted_writings(회원) — 그 회원이 쓴 지운 글·댓글 (운영자만).
--   - 1년 정리: purge_deleted_writings() — 지운 날부터 deleted_writing_keep_days(365)일이 지나면 완전 삭제 (pg_cron, 매일 4:50 한국 시간).
--   - 기존 "삭제된 글" 껍데기(제목·본문이 비워진 글)는 이 파일 뒤로 그 아래 댓글과 함께 안 보이고, 지운 날부터 1년 뒤 정리된다.
--     몇 개인지는 실행 전에 supabase/scripts/check_deleted_writings.sql로 확인한다.
--   - 지운 글·댓글의 사진은 지금처럼 바로 지운다(storage_trash → 하루 안에 파일 삭제).
--
-- 039까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. (039 전후 아무 때나 가능 — 옛 화면과 호환)
-- 순서: check_deleted_writings.sql "실행 전" → 이 파일 → 같은 확인 조회 "실행 후" → 화면 push → pg_cron 일정 등록 → 확인 조회 한 번 더.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. 설정값
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('deleted_writing_keep_days', 365, '지운 글·댓글 보관 기간(일) — 지나면 매일 완전 삭제 (purge_deleted_writings, pg_cron, 040)')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 1. "지움" 칸
-- ---------------------------------------------------------------------
alter table public.posts
  add column deleted_by uuid references public.profiles(id) on delete set null,
  add column delete_kind text check (delete_kind in ('author', 'staff')),
  add column delete_note text check (delete_note is null or char_length(delete_note) <= 500);
alter table public.post_comments
  add column deleted_at timestamptz,
  add column deleted_by uuid references public.profiles(id) on delete set null,
  add column delete_kind text check (delete_kind in ('author', 'staff')),
  add column delete_note text check (delete_note is null or char_length(delete_note) <= 500);
alter table public.doc_comments
  add column deleted_at timestamptz,
  add column deleted_by uuid references public.profiles(id) on delete set null,
  add column delete_kind text check (delete_kind in ('author', 'staff')),
  add column delete_note text check (delete_note is null or char_length(delete_note) <= 500);

-- 기존 "삭제된 글" 껍데기 = 작성자가 지운 글
update public.posts set delete_kind = 'author', deleted_by = author_id
 where deleted_at is not null and delete_kind is null;

alter table public.posts add constraint posts_delete_kind_set check ((deleted_at is null) = (delete_kind is null));
alter table public.post_comments add constraint post_comments_delete_kind_set check ((deleted_at is null) = (delete_kind is null));
alter table public.doc_comments add constraint doc_comments_delete_kind_set check ((deleted_at is null) = (delete_kind is null));

create index posts_deleted_idx on public.posts (deleted_at) where deleted_at is not null;
create index post_comments_deleted_idx on public.post_comments (deleted_at) where deleted_at is not null;
create index doc_comments_deleted_idx on public.doc_comments (deleted_at) where deleted_at is not null;

comment on column public.posts.delete_kind is '지운 글: author(작성자) / staff(운영진, delete_note = 사유). 지운 글은 아무에게도 안 보이고 운영자는 admin_deleted_writings로만 본다 (040)';
comment on column public.post_comments.delete_kind is '지운 댓글: author / staff (040)';
comment on column public.doc_comments.delete_kind is '지운 문서 댓글: author / staff (040)';

-- ---------------------------------------------------------------------
-- 2. 읽기 권한: 지운 것은 운영자를 포함해 아무도 못 읽는다
-- ---------------------------------------------------------------------
-- 글이 지워지지 않았나 (댓글 읽기 정책에서 씀 — 숨긴 글의 내 댓글 규칙은 그대로 두려고 RLS를 거치지 않고 본다)
create function public.post_live(p_post bigint)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.posts where id = p_post and deleted_at is null) $$;
revoke execute on function public.post_live(bigint) from public;
grant execute on function public.post_live(bigint) to anon, authenticated;

drop policy "posts: 읽기 (숨긴 글은 운영진만)" on public.posts;
create policy "posts: 읽기 (숨긴 글은 운영진만, 지운 글 제외)" on public.posts for select
  using (deleted_at is null and (status = 'visible' or public.can_see_hidden(author_id)));

drop policy "post_comments: 읽기 (숨긴 것은 운영진만)" on public.post_comments;
create policy "post_comments: 읽기 (지운 것·지운 글 제외)" on public.post_comments for select
  using (
    deleted_at is null and public.post_live(post_id)
    and (public.can_see_hidden(author_id)
         or (status = 'visible' and exists (select 1 from public.posts p where p.id = post_comments.post_id and p.status = 'visible')))
  );

drop policy "doc_comments: 읽기 (숨긴 것은 운영진만)" on public.doc_comments;
create policy "doc_comments: 읽기 (지운 것 제외)" on public.doc_comments for select
  using (
    deleted_at is null
    and (public.is_admin()
         or ((status = 'visible' or public.can_see_hidden(author_id))
             and exists (select 1 from public.counters c where c.id = doc_comments.counter_id and c.status = 'approved')))
  );

-- ---------------------------------------------------------------------
-- 3. 알림 종류·처리 기록 종류
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in (
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
  'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
  'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
  'matchup_created', 'build_created',
  'post_deleted', 'comment_deleted', 'doc_comment_deleted'  -- 040: 운영진 삭제 (푸시 없음)
));

alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action in (
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision',
  'delete'  -- 040: 운영진 삭제
));

-- ---------------------------------------------------------------------
-- 4. 작성자 삭제 (지움 표시만)
-- ---------------------------------------------------------------------
-- 글: 추천은 지우고, 열린 신고는 기각. 사진은 posts_drop_media 트리거가 바로 지운다.
-- 돌려주는 값은 옛 화면 호환으로 늘 'hard' (예전 'soft' = "삭제된 글"로 남음은 없어졌다)
create or replace function public.delete_my_post(p_id bigint)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  p public.posts%rowtype := public.board_post_for_update(p_id);
begin
  if me is null or p.author_id is distinct from me then
    raise exception '내 글만 지울 수 있습니다.' using errcode = '42501';
  end if;
  if p.deleted_at is not null then
    raise exception '이미 삭제된 글입니다.' using errcode = '23514';
  end if;
  update public.posts set deleted_at = now(), deleted_by = me, delete_kind = 'author', up_count = 0 where id = p.id;
  delete from public.post_votes where post_id = p.id;
  update public.reports set status = 'dismissed', handled_at = now(), handled_note = '작성자가 글을 지움'
   where post_id = p.id and status = 'open';
  return 'hard';
end;
$$;

create or replace function public.delete_my_comment(p_id bigint)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  c public.post_comments%rowtype;
begin
  select * into c from public.post_comments where id = p_id for update;
  if not found or c.deleted_at is not null then
    raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if me is null or c.author_id <> me then
    raise exception '내 댓글만 지울 수 있습니다.' using errcode = '42501';
  end if;
  update public.post_comments set deleted_at = now(), deleted_by = me, delete_kind = 'author' where id = c.id;
  update public.reports set status = 'dismissed', handled_at = now(), handled_note = '작성자가 댓글을 지움'
   where comment_id = c.id and status = 'open';
end;
$$;

create or replace function public.delete_my_doc_comment(p_id bigint)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  d public.doc_comments%rowtype := public.doc_comment_for_update(p_id);
begin
  if d.deleted_at is not null then
    raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if me is null or d.author_id <> me then
    raise exception '내 댓글만 지울 수 있습니다.' using errcode = '42501';
  end if;
  update public.doc_comments set deleted_at = now(), deleted_by = me, delete_kind = 'author' where id = d.id;
  update public.reports set status = 'dismissed', handled_at = now(), handled_note = '작성자가 댓글을 지움'
   where doc_comment_id = d.id and status = 'open';
end;
$$;

-- 지운 댓글의 사진도 바로 지운다 (글은 기존 posts_drop_media)
create function public.drop_deleted_comment_media()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.board_attachments where comment_id = new.id;
  return null;
end;
$$;
revoke execute on function public.drop_deleted_comment_media() from public, anon, authenticated;
create trigger post_comments_drop_media after update of deleted_at on public.post_comments
  for each row when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.drop_deleted_comment_media();

-- ---------------------------------------------------------------------
-- 5. 운영진 삭제 (메모 필수, 처리 기록, 작성자 알림)
-- ---------------------------------------------------------------------
create function public.staff_delete_post(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  note text;
  p public.posts%rowtype;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '삭제 이유');
  p := public.board_post_for_update(p_id);
  if p.deleted_at is not null then
    raise exception '이미 삭제된 글입니다.' using errcode = '23514';
  end if;
  perform public.require_moderate_target(p.author_id);
  update public.posts set deleted_at = now(), deleted_by = me, delete_kind = 'staff', delete_note = note, up_count = 0
   where id = p.id;
  delete from public.post_votes where post_id = p.id;
  update public.reports set status = 'resolved', handled_by = me, handled_at = now(), handled_note = note
   where post_id = p.id and status = 'open';
  if p.author_id is not null and p.author_id <> me then
    -- 글은 열 수 없으므로 링크 없이
    insert into public.notifications (user_id, kind, message)
    values (p.author_id, 'post_deleted', format('내 글 「%s」을 운영진이 삭제했습니다. 메모: %s', public.post_snippet(p.title), note));
  end if;
  perform public.log_moderation('delete', 'post', p.id::text, note);
end;
$$;

create function public.staff_delete_comment(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  note text;
  c public.post_comments%rowtype;
  t text;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '삭제 이유');
  select * into c from public.post_comments where id = p_id for update;
  if not found or c.deleted_at is not null then
    raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.require_moderate_target(c.author_id);
  update public.post_comments set deleted_at = now(), deleted_by = me, delete_kind = 'staff', delete_note = note where id = c.id;
  update public.reports set status = 'resolved', handled_by = me, handled_at = now(), handled_note = note
   where comment_id = c.id and status = 'open';
  select title into t from public.posts where id = c.post_id;
  perform public.notify_post(c.author_id, 'comment_deleted',
    format('「%s」에 쓴 내 댓글을 운영진이 삭제했습니다. 메모: %s', public.post_snippet(coalesce(nullif(t, ''), '삭제된 글')), note), c.post_id);
  perform public.log_moderation('delete', 'comment', c.id::text, note);
end;
$$;

create function public.staff_delete_doc_comment(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  note text;
  d public.doc_comments%rowtype;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '삭제 이유');
  d := public.doc_comment_for_update(p_id);
  if d.deleted_at is not null then
    raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.require_moderate_target(d.author_id);
  perform public.require_moderate_doc_counter(d.counter_id);
  update public.doc_comments set deleted_at = now(), deleted_by = me, delete_kind = 'staff', delete_note = note where id = d.id;
  update public.reports set status = 'resolved', handled_by = me, handled_at = now(), handled_note = note
   where doc_comment_id = d.id and status = 'open';
  if d.author_id <> me then
    insert into public.notifications (user_id, kind, message, counter_id)
    values (d.author_id, 'doc_comment_deleted', format('문서에 쓴 내 댓글을 운영진이 삭제했습니다. 메모: %s', note), d.counter_id);
  end if;
  perform public.log_moderation('delete', 'doc_comment', d.id::text, note);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 운영자 조회: 한 회원이 쓴 지운 글·댓글 (지운 순서, 최근 것부터)
-- ---------------------------------------------------------------------
create function public.admin_deleted_writings(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
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
$$;

-- 회원 정보: 활동 수에서 지운 것을 빼고, 지운 개수를 따로
create or replace function public.admin_member_info(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  u public.profiles%rowtype;
begin
  perform public.require_operator();
  select * into u from public.profiles where id = p_user;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'id', u.id, 'nickname', u.nickname, 'role', u.role, 'level', u.level, 'main_title', u.main_title,
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
$$;

-- ---------------------------------------------------------------------
-- 7. 1년 정리 (사람은 못 부르고 pg_cron만). 완전 삭제로 따라오는 경험치 회수는 알림 없이
-- ---------------------------------------------------------------------
create function public.purge_deleted_writings()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  before timestamptz := now() - make_interval(days => coalesce(public.xp_rule('deleted_writing_keep_days'), 365));
  n_doc integer;
  n_comment integer;
  n_post integer;
begin
  perform set_config('app.quiet_rewards', 'on', true);  -- 이 거래 안에서만: rewards_on_post가 알림 없이 다시 계산
  delete from public.doc_comments where deleted_at < before;
  get diagnostics n_doc = row_count;
  delete from public.post_comments where deleted_at < before;
  get diagnostics n_comment = row_count;
  delete from public.posts where deleted_at < before;  -- 그 아래 다른 사람 댓글·사진·신고·알림도 함께
  get diagnostics n_post = row_count;
  return jsonb_build_object('posts', n_post, 'comments', n_comment, 'doc_comments', n_doc);
end;
$$;
revoke execute on function public.purge_deleted_writings() from public, anon, authenticated;

create or replace function public.rewards_on_post()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.sync_rewards(case when tg_op = 'DELETE' then old.author_id else new.author_id end,
                              coalesce(current_setting('app.quiet_rewards', true), '') = 'on');
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 개수·경험치·트리거: 지운 댓글은 빼고 센다
-- ---------------------------------------------------------------------
-- 댓글 수 = 보이는(숨기지도 지우지도 않은) 댓글. 예전 "삭제된 글 껍데기 정리"는 없앤다 (껍데기가 남지 않으므로)
create or replace function public.post_comments_after()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  pid bigint := case when tg_op = 'DELETE' then old.post_id else new.post_id end;
begin
  update public.posts
     set comment_count = (select count(*) from public.post_comments where post_id = pid and status = 'visible' and deleted_at is null)
   where id = pid;
  return null;
end;
$$;

drop trigger post_comments_after on public.post_comments;
create trigger post_comments_after after insert or delete or update of status, deleted_at on public.post_comments
  for each row execute function public.post_comments_after();
drop trigger post_comments_rewards on public.post_comments;
create constraint trigger post_comments_rewards after insert or delete or update of status, deleted_at on public.post_comments
  deferrable initially deferred for each row execute function public.rewards_on_post();
drop trigger doc_comments_rewards on public.doc_comments;
create constraint trigger doc_comments_rewards after insert or delete or update of status, deleted_at on public.doc_comments
  deferrable initially deferred for each row execute function public.rewards_on_post();

create or replace function public.has_visible_writing(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.posts where author_id = p_user and status = 'visible' and deleted_at is null)
      or exists (select 1 from public.post_comments where author_id = p_user and status = 'visible' and deleted_at is null)
      or exists (select 1 from public.doc_comments where author_id = p_user and status = 'visible' and deleted_at is null);
$$;

-- 경험치: 지운 댓글은 회수. 지운 글에 달린 다른 사람 댓글은 그대로 (숨긴 글과 같은 기준)
create or replace function public.xp_should_have(p_user uuid)
returns table(source_key text, kind text, ref_id text, amount integer, at timestamptz, target_champion text, counter_champion text)
language sql stable security definer set search_path = ''
as $$
  -- 새 카운터(예전 승인 제안): 승인 + 카운터 공개 중 (숨기면 0, 다시 공개·재승인하면 같은 키로 돌아온다)
  select 'proposal:' || p.id, 'new_counter', p.id::text, public.xp_rule('new_counter'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'new_counter' and p.status = 'approved' and c.status = 'approved'
  union all
  -- 문서 수정(예전 승인 제안): 승인 + 카운터가 있음 (숨김은 회수하지 않고 완전 삭제만)
  select 'proposal:' || p.id, 'doc_edit', p.id::text, public.xp_rule('doc_edit'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'doc_edit' and p.status = 'approved'
  union all
  -- 빌드(예전 승인): 공개 중, 새 카운터의 첫 빌드는 카운터 +100에 포함
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
$$;

-- 회수 이유: 지운 댓글도 「댓글 삭제」
do $$
declare
  f oid := 'public.xp_reason(text, text, integer, integer, boolean)'::regprocedure;
  def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(def,
    $a$    select status into st from public.post_comments where id = p_ref::bigint;
    if not found then return '댓글 삭제'; end if;$a$,
    $a$    select status, deleted_at into st, del from public.post_comments where id = p_ref::bigint;
    if not found or del is not null then return '댓글 삭제'; end if;$a$);
  new_def := replace(new_def,
    $a$    select status into st from public.doc_comments where id = split_part(p_ref, ':', 2)::bigint;
    if not found then return '댓글 삭제'; end if;$a$,
    $a$    select status, deleted_at into st, del from public.doc_comments where id = split_part(p_ref, ':', 2)::bigint;
    if not found or del is not null then return '댓글 삭제'; end if;$a$);
  if new_def = def or new_def like '%select status into st from public.post_comments%'
     or new_def like '%select status into st from public.doc_comments%' then
    raise exception 'xp_reason을 고치지 못했습니다 (예상과 다른 정의). 아무것도 바뀌지 않았습니다.';
  end if;
  execute new_def;
end $$;

-- ---------------------------------------------------------------------
-- 9. 지운 것은 고치기·신고·숨기기·다시 공개·댓글 달기 불가
-- ---------------------------------------------------------------------
create or replace function public.begin_edit(p_kind text, p_id bigint)
returns timestamptz language plpgsql security definer set search_path = ''
as $$
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
$$;

create or replace function public.edit_comment(p_id bigint, p_body text, p_media text[] default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  c public.post_comments%rowtype;
  keep_count integer;
  b text;
  changed boolean;
begin
  select * into c from public.post_comments where id = p_id for update;
  if not found or c.deleted_at is not null or not public.post_live(c.post_id) then
    raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if c.author_id <> me then
    raise exception '내 댓글만 고칠 수 있습니다.' using errcode = '42501';
  end if;
  if c.status <> 'visible' or exists (select 1 from public.posts where id = c.post_id and status <> 'visible') then
    raise exception '운영진이 숨긴 댓글·글은 고칠 수 없습니다.' using errcode = '23514';
  end if;
  perform public.require_edit_window('comment', c.created_at, c.edit_grace_until);
  keep_count := coalesce(cardinality(p_media), (select count(*) from public.board_attachments where comment_id = c.id));
  b := public.board_text_or_empty(p_body, '댓글', 1000, keep_count > 0);
  changed := false;
  if p_media is not null then
    changed := public.media_set(null, c.id, me, p_media);
  end if;
  if b = c.body and not changed then
    return;
  end if;
  update public.post_comments set body = b, edited_at = now() where id = c.id;
end;
$$;

create or replace function public.edit_doc_comment(p_id bigint, p_body text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b text := public.board_text(p_body, '댓글', 1000);
  d public.doc_comments%rowtype := public.doc_comment_for_update(p_id);
begin
  if d.deleted_at is not null then
    raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if d.author_id <> me then
    raise exception '내 댓글만 고칠 수 있습니다.' using errcode = '42501';
  end if;
  if d.status <> 'visible' or exists (select 1 from public.counters where id = d.counter_id and status <> 'approved') then
    raise exception '숨긴 댓글·문서는 고칠 수 없습니다.' using errcode = '23514';
  end if;
  perform public.require_edit_window('doc_comment', d.created_at, d.edit_grace_until);
  if b = d.body then
    return;
  end if;
  update public.doc_comments set body = b, edited_at = now() where id = d.id;
end;
$$;

create or replace function public.report_comment(p_id bigint, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  d text := public.board_report_check(p_reason, p_detail);
  c public.post_comments%rowtype;
begin
  select * into c from public.post_comments where id = p_id;
  if not found or c.status <> 'visible' or c.deleted_at is not null
     or exists (select 1 from public.posts where id = c.post_id and (status <> 'visible' or deleted_at is not null)) then
    raise exception '신고할 수 없는 댓글입니다.' using errcode = 'P0002';
  end if;
  if c.author_id = me then
    raise exception '내 댓글은 신고할 수 없습니다.' using errcode = '23514';
  end if;
  insert into public.reports (reporter_id, comment_id, reason, detail) values (me, c.id, p_reason, d);
exception when unique_violation then
  raise exception '이미 신고한 댓글입니다.' using errcode = '23505';
end;
$$;

create or replace function public.report_doc_comment(p_id bigint, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  dt text := public.board_report_check(p_reason, p_detail);
  d public.doc_comments%rowtype;
begin
  select * into d from public.doc_comments where id = p_id;
  if not found or d.status <> 'visible' or d.deleted_at is not null
     or exists (select 1 from public.counters where id = d.counter_id and status <> 'approved') then
    raise exception '신고할 수 없는 댓글입니다.' using errcode = 'P0002';
  end if;
  if d.author_id = me then
    raise exception '내 댓글은 신고할 수 없습니다.' using errcode = '23514';
  end if;
  insert into public.reports (reporter_id, doc_comment_id, reason, detail) values (me, d.id, p_reason, dt);
exception when unique_violation then
  raise exception '이미 신고한 댓글입니다.' using errcode = '23505';
end;
$$;

-- 숨기기·다시 공개: 맨 앞에서 지운 것을 거부 (나머지는 그대로)
do $$
declare
  r record;
  def text;
  new_def text;
begin
  for r in
    select * from (values
      ('public.hide_comment(bigint, text)', 'comment', $a$  perform public.require_moderate_target(c.author_id);
  if c.status = 'hidden' then$a$,
        $a$  if c.deleted_at is not null or not public.post_live(c.post_id) then
    raise exception '삭제된 댓글입니다.' using errcode = '23514';
  end if;
  perform public.require_moderate_target(c.author_id);
  if c.status = 'hidden' then$a$),
      ('public.restore_comment(bigint, text)', 'comment', $a$  perform public.require_moderate_target(c.author_id);
  if c.status <> 'hidden' then$a$,
        $a$  if c.deleted_at is not null or not public.post_live(c.post_id) then
    raise exception '삭제된 댓글입니다.' using errcode = '23514';
  end if;
  perform public.require_moderate_target(c.author_id);
  if c.status <> 'hidden' then$a$),
      ('public.hide_doc_comment(bigint, text)', 'doc', $a$  perform public.require_moderate_target(d.author_id);
  perform public.require_moderate_doc_counter(d.counter_id);
  if d.status = 'hidden' then$a$,
        $a$  if d.deleted_at is not null then
    raise exception '삭제된 댓글입니다.' using errcode = '23514';
  end if;
  perform public.require_moderate_target(d.author_id);
  perform public.require_moderate_doc_counter(d.counter_id);
  if d.status = 'hidden' then$a$),
      ('public.restore_doc_comment(bigint, text)', 'doc', $a$  perform public.require_moderate_target(d.author_id);
  perform public.require_moderate_doc_counter(d.counter_id);
  if d.status <> 'hidden' then$a$,
        $a$  if d.deleted_at is not null then
    raise exception '삭제된 댓글입니다.' using errcode = '23514';
  end if;
  perform public.require_moderate_target(d.author_id);
  perform public.require_moderate_doc_counter(d.counter_id);
  if d.status <> 'hidden' then$a$),
      ('public.restore_post(bigint, text)', 'post', $a$  perform public.require_moderate_target(p.author_id);
  if p.status <> 'hidden' then$a$,
        $a$  if p.deleted_at is not null then
    raise exception '삭제된 글입니다.' using errcode = '23514';
  end if;
  perform public.require_moderate_target(p.author_id);
  if p.status <> 'hidden' then$a$)
    ) v(fn, k, old_text, new_text)
  loop
    def := pg_get_functiondef(r.fn::regprocedure);
    new_def := replace(def, r.old_text, r.new_text);
    if new_def = def then
      raise exception '%을 고치지 못했습니다 (예상과 다른 정의). 아무것도 바뀌지 않았습니다.', r.fn;
    end if;
    execute new_def;
  end loop;
end $$;

-- 새 댓글 알림의 "새 댓글 N개"에서 지운 댓글은 빼고 센다
do $$
declare
  def text;
  new_def text;
begin
  def := pg_get_functiondef('public.create_comment(bigint, text, text[])'::regprocedure);
  new_def := replace(def, $a$and author_id <> p.author_id and status = 'visible' and created_at >= n.created_at$a$,
                          $a$and author_id <> p.author_id and status = 'visible' and deleted_at is null and created_at >= n.created_at$a$);
  if new_def = def then raise exception 'create_comment를 고치지 못했습니다. 아무것도 바뀌지 않았습니다.'; end if;
  execute new_def;
  def := pg_get_functiondef('public.create_doc_comment(bigint, text)'::regprocedure);
  new_def := replace(def, $a$and author_id <> owner and status = 'visible' and created_at >= n.created_at$a$,
                          $a$and author_id <> owner and status = 'visible' and deleted_at is null and created_at >= n.created_at$a$);
  if new_def = def then raise exception 'create_doc_comment를 고치지 못했습니다. 아무것도 바뀌지 않았습니다.'; end if;
  execute new_def;
end $$;

-- 감독관 신고 목록: 지운 글·댓글의 신고는 빼고 (지울 때 닫히지만 혹시 남은 것)
do $$
declare
  def text := pg_get_functiondef('public.open_reports_for_moderator()'::regprocedure);
  new_def text;
begin
  new_def := replace(def, $a$    where r.status = 'open'
$a$, $a$    where r.status = 'open' and coalesce(p.deleted_at, c.deleted_at, d.deleted_at) is null
$a$);
  if new_def = def then raise exception 'open_reports_for_moderator를 고치지 못했습니다. 아무것도 바뀌지 않았습니다.'; end if;
  execute new_def;
end $$;

-- ---------------------------------------------------------------------
-- 10. 게시판 목록·검색: 지운 글 없음 (deleted는 옛 화면 호환으로 늘 false)
-- ---------------------------------------------------------------------
create or replace function public.board_page(p_q text default null, p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable set search_path = ''
as $$
declare
  q text := nullif(btrim(coalesce(p_q, '')), '');
  pat text;
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  pg integer := greatest(coalesce(p_page, 1), 1);
  total integer;
  items jsonb;
begin
  if q is not null then
    pat := '%' || replace(replace(replace(left(q, 50), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;
  select count(*) into total from public.posts p
  where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat);

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into items
  from (
    select p.id, p.title, p.status, false as deleted, p.comment_count, p.up_count,
           p.created_at, p.edited_at,
           (select count(*) from public.board_attachments a where a.post_id = p.id) as media_count,
           (select jsonb_build_object('nickname', a.nickname, 'role', a.role, 'level', a.level, 'main_title', a.main_title)
            from public.profiles a where a.id = p.author_id) as author
    from public.posts p
    where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat)
    order by p.created_at desc, p.id desc
    limit sz offset (pg - 1) * sz
  ) x;
  return jsonb_build_object('total', total, 'size', sz, 'rows', items);
end;
$$;

-- ---------------------------------------------------------------------
-- 11. 탈퇴: 다른 사람 댓글이 달린 내 글은 내용을 지운 채 "지움"으로 (안 보임, 1년 뒤 정리), 나머지 내 글은 바로 삭제
-- ---------------------------------------------------------------------
create or replace function public.board_on_profile_delete()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
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

-- ---------------------------------------------------------------------
-- 12. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.staff_delete_post(bigint, text) from public, anon;
revoke execute on function public.staff_delete_comment(bigint, text) from public, anon;
revoke execute on function public.staff_delete_doc_comment(bigint, text) from public, anon;
grant execute on function public.staff_delete_post(bigint, text) to authenticated;
grant execute on function public.staff_delete_comment(bigint, text) to authenticated;
grant execute on function public.staff_delete_doc_comment(bigint, text) to authenticated;
revoke execute on function public.admin_deleted_writings(uuid) from public, anon;
grant execute on function public.admin_deleted_writings(uuid) to authenticated;

commit;
