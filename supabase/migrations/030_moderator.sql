-- =====================================================================
-- 030: 감독관 (role = 'moderator') (2026-11-07, SPEC 5장 회원 등급·6-18)
-- 1. 역할: 운영자(admin, 1명, Lv.0)는 그대로, 감독관(moderator)은 일반 회원처럼 경험치·칭호가 쌓인다.
--    화면 표시는 운영자·감독관 모두 닉네임 앞 "(운)". 권한 구분은 여기 DB의 role로만 한다.
-- 2. 지정·해제: 운영자만 set_moderator(대상, 켜기/끄기, 메모). role은 호출마다 읽으므로 해제하면 그 즉시 권한이 없다.
-- 3. 감독관이 하는 일: 글·댓글·문서 댓글 숨김과 다시 공개, 신고 처리, 새 카운터 제안 승인·반려(메모 필수).
--    - 본인·다른 감독관·운영자의 글·댓글·신고·제안은 처리할 수 없다.
--    - 운영자가 숨긴 것은 다시 공개할 수 없다 (다른 감독관이 숨긴 것은 된다).
--    - 새 카운터 제안은 대기 중인 것만, 내용을 고치지 않고. 숨긴 카운터 재검토 제안은 운영자만.
--    - 숨긴 카운터의 문서 댓글은 운영자만.
--    그 밖의 운영자 함수(빌드 처리, 카운터 숨김·삭제, 순서, 되돌리기, 가격표 등)는 is_admin 그대로라 감독관은 호출해도 거부된다.
-- 4. 기록: moderation_log = 누가(id·닉네임·역할) 무엇을 언제 왜 처리했나. 운영자만 읽고, 아무도 고치지 못하며,
--    처리자 탈퇴 후에도 남는다 (사용자 표와 연결하지 않음). 지정·해제 기록도 여기에 남는다.
-- 5. 신고: reports 표는 운영자 전용 그대로. 감독관은 open_reports_for_moderator()로 읽는다 (신고자는 빠져 있다).
-- 6. 문구: 알림·오류의 "운영자가 숨긴/숨겼습니다"를 "운영진이"로. 이미 보낸 알림은 그대로.
-- 7. board_page(자유게시판 목록)의 작성자에 role을 더한다 (029 이후 목록에서만 (운)이 안 붙던 것).
--
-- 하위 호환: 함수 이름·인자는 하나도 바꾸지 않고, 운영자의 동작도 같다. 지금 배포된 화면에서 그대로 동작한다.
-- 순서: 이 파일 실행 → 확인 → 새 코드 push. 029까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 역할
-- ---------------------------------------------------------------------
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('user', 'moderator', 'admin'));

create function public.is_moderator()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'moderator');
$$;
comment on function public.is_moderator() is '지금 로그인한 사람이 감독관인가';

create function public.is_staff()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator', 'admin'));
$$;
comment on function public.is_staff() is '지금 로그인한 사람이 운영자 또는 감독관인가';

create function public.require_staff()
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_staff() then
    raise exception '운영자만 할 수 있습니다.' using errcode = '42501';
  end if;
end;
$$;

-- 감독관이 처리해도 되는 작성자인가: 일반 회원(또는 탈퇴해서 없음)이고 본인이 아님
create function public.moderatable_author(p_author uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_author is null or (
    p_author is distinct from (select auth.uid())
    and exists (select 1 from public.profiles where id = p_author and role = 'user')
  );
$$;

-- 숨긴 글·댓글을 볼 수 있는가 (RLS용): 운영자는 전부, 감독관은 처리할 수 있는 작성자의 것만
create function public.can_see_hidden(p_author uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or (public.is_moderator() and public.moderatable_author(p_author));
$$;

create function public.require_moderate_target(p_author uuid)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.is_moderator() and not public.moderatable_author(p_author) then
    raise exception '본인이나 운영진의 글·댓글은 감독관이 처리할 수 없습니다.' using errcode = '42501';
  end if;
end;
$$;

create function public.require_moderate_doc_counter(p_counter bigint)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.is_moderator()
     and not exists (select 1 from public.counters where id = p_counter and status = 'approved') then
    raise exception '숨긴 카운터의 댓글은 운영자만 처리할 수 있습니다.' using errcode = '42501';
  end if;
end;
$$;

-- 감독관은 다른 감독관이 숨긴 것만 다시 공개한다 (운영자가 숨긴 것, 숨긴 사람을 모르는 것은 안 됨)
create function public.require_restore_allowed(p_hidden_by uuid)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.is_moderator()
     and not exists (select 1 from public.profiles where id = p_hidden_by and role = 'moderator') then
    raise exception '운영자가 숨긴 것은 감독관이 다시 공개할 수 없습니다.' using errcode = '42501';
  end if;
end;
$$;

-- 감독관이 처리할 수 있는 제안: 대기 중인 새 카운터 제안(숨긴 카운터 재검토 제외), 제안자가 일반 회원이고 본인이 아님
create function public.require_review_allowed(p public.edit_proposals)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.is_moderator() and (
    p.type <> 'new_counter' or p.counter_id is not null or p.status <> 'pending'
    or not public.moderatable_author(p.proposer_id)
  ) then
    raise exception '감독관이 처리할 수 없는 제안입니다. (본인·운영진의 제안, 문서 수정 제안, 숨긴 카운터의 제안은 운영자가 처리합니다)'
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. 처리 기록
-- ---------------------------------------------------------------------
create table public.moderation_log (
  id              bigint generated always as identity primary key,
  actor_id        uuid,            -- 사용자 표와 연결하지 않는다: 처리자가 탈퇴해도 남는다
  actor_nickname  text,
  actor_role      text not null,
  action          text not null check (action in (
    'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator')),
  target_kind     text not null check (target_kind in ('post', 'comment', 'doc_comment', 'proposal', 'user')),
  target_id       text not null,
  target_nickname text,            -- 지정·해제 기록에만
  note            text,
  created_at      timestamptz not null default now()
);
create index moderation_log_recent on public.moderation_log (created_at desc);
comment on table public.moderation_log is
  '운영자·감독관의 처리 기록 (030). 숨김·다시 공개·신고 기각·새 카운터 승인/반려·감독관 지정/해제. 운영자만 읽고 아무도 직접 못 씀. 처리자 탈퇴 후에도 남음';
revoke all on public.moderation_log from anon, authenticated;
grant select on public.moderation_log to authenticated;
alter table public.moderation_log enable row level security;
create policy "moderation_log: 운영자 읽기" on public.moderation_log for select to authenticated using (public.is_admin());

create function public.log_moderation(p_action text, p_kind text, p_target text, p_note text, p_target_nickname text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me public.profiles%rowtype;
begin
  select * into me from public.profiles where id = (select auth.uid());
  insert into public.moderation_log
    (actor_id, actor_nickname, actor_role, action, target_kind, target_id, target_nickname, note)
  values (me.id, me.nickname, coalesce(me.role, 'unknown'), p_action, p_kind, p_target, p_target_nickname, p_note);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 감독관 지정·해제 (운영자만)
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in ('revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected', 'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked', 'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked'));

create function public.set_moderator(p_user uuid, p_on boolean, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  u public.profiles%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '메모');
  select * into u from public.profiles where id = p_user for update;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if u.role = 'admin' then
    raise exception '운영자는 감독관으로 바꿀 수 없습니다.' using errcode = '23514';
  end if;
  if p_on then
    if u.role = 'moderator' then
      raise exception '이미 감독관입니다.' using errcode = '23514';
    end if;
    if u.nickname is null or u.is_guest then
      raise exception '닉네임을 정한 정식 회원만 감독관으로 지정할 수 있습니다.' using errcode = '23514';
    end if;
    update public.profiles set role = 'moderator' where id = u.id;
    perform public.notify(u.id, 'moderator_granted',
      format('감독관으로 지정됐습니다. 처리 기록은 탈퇴 후에도 남습니다. 메모: %s', note), null, null);
  else
    if u.role <> 'moderator' then
      raise exception '감독관이 아닙니다.' using errcode = '23514';
    end if;
    update public.profiles set role = 'user' where id = u.id;
    perform public.notify(u.id, 'moderator_revoked', format('감독관에서 해제됐습니다. 메모: %s', note), null, null);
  end if;
  perform public.log_moderation(case when p_on then 'grant_moderator' else 'revoke_moderator' end,
    'user', u.id::text, note, u.nickname);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 감독관의 신고 읽기 (신고자를 뺀다, 처리할 수 있는 대상만)
-- ---------------------------------------------------------------------
create function public.open_reports_for_moderator()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  if not public.is_moderator() then
    raise exception '감독관만 쓰는 목록입니다.' using errcode = '42501';
  end if;
  with person as (
    select id, jsonb_build_object('nickname', nickname, 'role', role, 'level', level, 'main_title', main_title, 'is_guest', is_guest) as j
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
    where r.status = 'open'
      and public.moderatable_author(coalesce(p.author_id, c.author_id, d.author_id))
      and (r.doc_comment_id is null or k.status = 'approved')
  ) x;
  return result;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 읽기 권한 (RLS). 운영자는 그대로, 감독관은 처리할 수 있는 것만 더한다
-- ---------------------------------------------------------------------
drop policy "posts: 읽기 (숨긴 글은 운영자만)" on public.posts;
create policy "posts: 읽기 (숨긴 글은 운영진만)" on public.posts
  for select using (status = 'visible' or public.can_see_hidden(author_id));

drop policy "post_comments: 읽기 (숨긴 것은 운영자만)" on public.post_comments;
create policy "post_comments: 읽기 (숨긴 것은 운영진만)" on public.post_comments
  for select using (
    public.can_see_hidden(author_id)
    or (status = 'visible' and exists (select 1 from public.posts p where p.id = post_id and p.status = 'visible'))
  );

drop policy "doc_comments: 읽기 (숨긴 것은 운영자만)" on public.doc_comments;
create policy "doc_comments: 읽기 (숨긴 것은 운영진만)" on public.doc_comments
  for select using (
    public.is_admin()
    or (
      (status = 'visible' or public.can_see_hidden(author_id))
      and exists (select 1 from public.counters c where c.id = counter_id and c.status = 'approved')
    )
  );

drop policy "edit_proposals: 본인 또는 관리자 읽기" on public.edit_proposals;
create policy "edit_proposals: 본인·운영진 읽기" on public.edit_proposals
  for select to authenticated using (
    proposer_id = (select auth.uid())
    or public.is_admin()
    or (public.is_moderator() and type = 'new_counter' and counter_id is null and status = 'pending'
        and public.moderatable_author(proposer_id))
  );

-- ---------------------------------------------------------------------
-- 6. 처리 함수 (이름·인자는 그대로)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hide_post(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  note text;
  p public.posts%rowtype;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '숨기는 이유');
  p := public.board_post_for_update(p_id);
  perform public.require_moderate_target(p.author_id);
  if p.status = 'hidden' then
    raise exception '이미 숨긴 글입니다.' using errcode = '23514';
  end if;
  if p.deleted_at is not null then
    raise exception '삭제된 글입니다.' using errcode = '23514';
  end if;
  update public.posts set status = 'hidden', hidden_note = note, hidden_at = now(), hidden_by = (select auth.uid())
  where id = p.id;
  update public.reports set status = 'resolved', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
  where post_id = p.id and status = 'open';
  perform public.notify_post(p.author_id, 'post_hidden',
    format('내 글 「%s」을 운영진이 숨겼습니다. 메모: %s', public.post_snippet(p.title), note), p.id);
  perform public.log_moderation('hide', 'post', p.id::text, note);
end;
$$;

CREATE OR REPLACE FUNCTION public.restore_post(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  note text;
  p public.posts%rowtype;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '다시 공개 메모');
  p := public.board_post_for_update(p_id);
  perform public.require_moderate_target(p.author_id);
  if p.status <> 'hidden' then
    raise exception '숨긴 글이 아닙니다.' using errcode = '23514';
  end if;
  perform public.require_restore_allowed(p.hidden_by);
  update public.posts set status = 'visible', hidden_note = null, hidden_at = null, hidden_by = null where id = p.id;
  perform public.notify_post(p.author_id, 'post_restored',
    format('숨겨졌던 내 글 「%s」이 다시 공개됐습니다. 메모: %s', public.post_snippet(p.title), note), p.id);
  perform public.log_moderation('restore', 'post', p.id::text, note);
end;
$$;

CREATE OR REPLACE FUNCTION public.hide_comment(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  note text;
  c public.post_comments%rowtype;
  t text;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '숨기는 이유');
  select * into c from public.post_comments where id = p_id for update;
  if not found then
    raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.require_moderate_target(c.author_id);
  if c.status = 'hidden' then
    raise exception '이미 숨긴 댓글입니다.' using errcode = '23514';
  end if;
  update public.post_comments set status = 'hidden', hidden_note = note, hidden_at = now(), hidden_by = (select auth.uid())
  where id = c.id;
  update public.reports set status = 'resolved', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
  where comment_id = c.id and status = 'open';
  select title into t from public.posts where id = c.post_id;
  perform public.notify_post(c.author_id, 'comment_hidden',
    format('「%s」에 쓴 내 댓글을 운영진이 숨겼습니다. 메모: %s', public.post_snippet(coalesce(nullif(t, ''), '삭제된 글')), note), c.post_id);
  perform public.log_moderation('hide', 'comment', c.id::text, note);
end;
$$;

CREATE OR REPLACE FUNCTION public.restore_comment(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  note text;
  c public.post_comments%rowtype;
  t text;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '다시 공개 메모');
  select * into c from public.post_comments where id = p_id for update;
  if not found then
    raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.require_moderate_target(c.author_id);
  if c.status <> 'hidden' then
    raise exception '숨긴 댓글이 아닙니다.' using errcode = '23514';
  end if;
  perform public.require_restore_allowed(c.hidden_by);
  update public.post_comments set status = 'visible', hidden_note = null, hidden_at = null, hidden_by = null where id = c.id;
  select title into t from public.posts where id = c.post_id;
  perform public.notify_post(c.author_id, 'comment_restored',
    format('숨겨졌던 내 댓글(「%s」)이 다시 공개됐습니다. 메모: %s', public.post_snippet(coalesce(nullif(t, ''), '삭제된 글')), note), c.post_id);
  perform public.log_moderation('restore', 'comment', c.id::text, note);
end;
$$;

CREATE OR REPLACE FUNCTION public.hide_doc_comment(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  note text;
  d public.doc_comments%rowtype;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '숨기는 이유');
  d := public.doc_comment_for_update(p_id);
  perform public.require_moderate_target(d.author_id);
  perform public.require_moderate_doc_counter(d.counter_id);
  if d.status = 'hidden' then
    raise exception '이미 숨긴 댓글입니다.' using errcode = '23514';
  end if;
  update public.doc_comments set status = 'hidden', hidden_note = note, hidden_at = now(), hidden_by = (select auth.uid())
  where id = d.id;
  update public.reports set status = 'resolved', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
  where doc_comment_id = d.id and status = 'open';
  if d.author_id <> (select auth.uid()) then
    insert into public.notifications (user_id, kind, message, counter_id)
    values (d.author_id, 'doc_comment_hidden', format('문서에 쓴 내 댓글을 운영진이 숨겼습니다. 메모: %s', note), d.counter_id);
  end if;
  perform public.log_moderation('hide', 'doc_comment', d.id::text, note);
end;
$$;

CREATE OR REPLACE FUNCTION public.restore_doc_comment(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  note text;
  d public.doc_comments%rowtype;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '다시 공개 메모');
  d := public.doc_comment_for_update(p_id);
  perform public.require_moderate_target(d.author_id);
  perform public.require_moderate_doc_counter(d.counter_id);
  if d.status <> 'hidden' then
    raise exception '숨긴 댓글이 아닙니다.' using errcode = '23514';
  end if;
  perform public.require_restore_allowed(d.hidden_by);
  update public.doc_comments set status = 'visible', hidden_note = null, hidden_at = null, hidden_by = null where id = d.id;
  if d.author_id <> (select auth.uid()) then
    insert into public.notifications (user_id, kind, message, counter_id)
    values (d.author_id, 'doc_comment_restored', format('숨겨졌던 문서 댓글이 다시 공개됐습니다. 메모: %s', note), d.counter_id);
  end if;
  perform public.log_moderation('restore', 'doc_comment', d.id::text, note);
end;
$$;

CREATE OR REPLACE FUNCTION public.dismiss_reports(p_post bigint, p_comment bigint, p_note text DEFAULT NULL::text, p_doc_comment bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  n integer;
  who uuid;
  doc_counter bigint;
begin
  perform public.require_staff();
  if num_nonnulls(p_post, p_comment, p_doc_comment) <> 1 then
    raise exception '글이나 댓글 하나를 골라 주세요.' using errcode = '22023';
  end if;
  -- 감독관: 본인·운영진 대상 신고, 숨긴 카운터의 문서 댓글 신고는 처리할 수 없다
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
$$;

CREATE OR REPLACE FUNCTION public.hide_counts(p_users uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  days int := coalesce((select value from public.xp_rules where key = 'hide_count_days'), 90);
begin
  if not public.is_staff() then
    raise exception '운영자만 할 수 있습니다.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'days', days,
    'counts', coalesce((
      select jsonb_object_agg(u, (
        select count(*) from public.hide_log h
         where h.author_id = u and h.unhidden_at is null and h.hidden_at > now() - make_interval(days => days)
      ))
      from unnest(coalesce(p_users, '{}')) as u
    ), '{}'::jsonb)
  );
end;
$$;

CREATE OR REPLACE FUNCTION public.approve_proposal(p_id bigint, p_note text, p_content jsonb, p_build jsonb, p_version integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
begin
  perform public.require_staff();
  perform public.require_proposal_version(p_id, p_version);
  return public.approve_proposal_unchecked(p_id, p_note, p_content, p_build);
end;
$$;

CREATE OR REPLACE FUNCTION public.approve_proposal_unchecked(p_id bigint, p_note text, p_content jsonb, p_build jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  note text;
  p public.edit_proposals%rowtype;
  c public.counters%rowtype;
  cid bigint;
  st text;
  rid bigint;
  orig_doc jsonb;
  new_doc jsonb;
  orig_build jsonb;
  new_build jsonb;
  nb jsonb;
begin
  perform public.require_staff();
  note := public.require_note(p_note, '승인 메모');
  select * into p from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.require_review_allowed(p);
  if p.status <> 'pending' then
    raise exception '이미 처리된 제안입니다.' using errcode = '23514';
  end if;
  if p.type = 'new_counter' and p.build is null then
    raise exception '빌드가 없는 새 카운터 제안이라 승인할 수 없습니다. 거절해 주세요.' using errcode = '23514';
  end if;
  if p.type = 'doc_edit' and p_build is not null then
    raise exception '문서 수정 제안에는 빌드가 없습니다.' using errcode = '23514';
  end if;

  -- 운영자가 고친 내용 (정리했더니 원래와 같으면 안 고친 것)
  orig_doc := public.clean_doc_content(p.content);
  new_doc := orig_doc;
  if p_content is not null then
    new_doc := public.clean_doc_content(p_content);
  end if;
  if p.type = 'new_counter' then
    orig_build := public.clean_build(p.build);
    new_build := orig_build;
    if p_build is not null then
      nb := public.clean_build(p_build);
      if nb - 'patch' <> orig_build - 'patch' then
        new_build := nb;  -- 고친 빌드는 화면이 보낸 지금 패치
      end if;
    end if;
  end if;

  -- 감독관은 고쳐서 승인할 수 없다 (그대로 승인 또는 반려)
  if public.is_moderator() and (new_doc is distinct from orig_doc or new_build is distinct from orig_build) then
    raise exception '감독관은 내용을 고쳐서 승인할 수 없습니다.' using errcode = '42501';
  end if;

  if p.type = 'new_counter' and p.counter_id is not null then
    -- 숨긴 카운터 재검토 후 다시 낸 제안
    select * into c from public.counters where id = p.counter_id for update;
    if not found or c.status <> 'hidden' then
      raise exception '숨긴 카운터가 아니라 승인할 수 없습니다. 거절해 주세요.' using errcode = '23514';
    end if;
    cid := c.id;
    perform 1 from public.counters where target_champion = c.target_champion and status = 'approved' for update;

    rid := public.add_approved_revisions(p, cid, 'edit', orig_doc, new_doc, note);
    update public.matchup_docs
       set summary = new_doc ->> 'summary', level_notes = new_doc -> 'level_notes',
           lane_cautions = new_doc ->> 'lane_cautions', updated_by = p.proposer_id, revision_id = rid
     where counter_id = cid;

    update public.counters
       set status = 'approved',
           sort_order = coalesce((select max(sort_order) + 1 from public.counters
                                  where target_champion = c.target_champion and status = 'approved'), 0)
     where id = cid;

    update public.edit_proposals
       set status = 'approved', approve_note = note, reviewed_by = (select auth.uid()), reviewed_at = now(),
           revoke_reason = null, revoked_by = null, revoked_at = null, reject_reason = null,
           approved_content = case when new_doc is distinct from orig_doc then new_doc end,
           approved_build = case when new_build is distinct from orig_build then new_build end
     where id = p.id;

    perform public.publish_proposal_build(p, cid, note, new_build,
                                          case when new_build is distinct from orig_build then orig_build end);

    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (cid, 'restore', note, p.id, (select auth.uid()));
    perform public.notify(p.proposer_id, 'proposal_approved', note, p.id, null);
    perform public.log_moderation('approve_proposal', 'proposal', p.id::text, note);
    -- (6단계) 경험치 다시 지급은 여기에 추가 (SPEC 6-1 메모: 한 번분만, 고쳐서 승인해도 제안자에게)
    return cid;
  end if;

  if p.type = 'new_counter' then
    perform 1 from public.counters where target_champion = p.target_champion for update;
    select status into st from public.counters
     where target_champion = p.target_champion and counter_champion = p.counter_champion;
    if st = 'hidden' then
      raise exception '숨긴 카운터입니다. 살리려면 [다시 공개]를 쓰고, 이 제안은 거절해 주세요.' using errcode = '23514';
    end if;
    insert into public.counters (target_champion, counter_champion, sort_order, status, proposed_by)
    values (
      p.target_champion, p.counter_champion,
      coalesce((select max(sort_order) + 1 from public.counters
                where target_champion = p.target_champion and status = 'approved'), 0),
      'approved', p.proposer_id
    )
    on conflict (target_champion, counter_champion) do update
      set status = 'approved', sort_order = excluded.sort_order, proposed_by = excluded.proposed_by
      where public.counters.status not in ('approved', 'hidden')
    returning id into cid;
    if cid is null then
      raise exception '이미 등록된 카운터입니다. 이 제안은 거절해 주세요.' using errcode = '23514';
    end if;
  else
    select id, status into cid, st from public.counters where id = p.counter_id for update;
    if st = 'hidden' then
      raise exception '숨긴 카운터의 제안이라 승인할 수 없습니다. 거절해 주세요.' using errcode = '23514';
    end if;
    if cid is null or st <> 'approved' then
      raise exception '수정할 매치업 문서를 찾지 못했습니다.' using errcode = 'P0002';
    end if;
    if new_doc is distinct from orig_doc and new_doc = (
      select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
      from public.matchup_docs d where d.counter_id = cid
    ) then
      raise exception '고친 내용이 지금 문서와 같습니다. 바꿀 게 없으면 거절해 주세요.' using errcode = '23514';
    end if;
  end if;

  rid := public.add_approved_revisions(p, cid, case when p.type = 'new_counter' then 'create' else 'edit' end,
                                       orig_doc, new_doc, note);

  insert into public.matchup_docs (counter_id, summary, level_notes, lane_cautions, updated_by, revision_id)
  values (cid, new_doc ->> 'summary', new_doc -> 'level_notes', new_doc ->> 'lane_cautions', p.proposer_id, rid)
  on conflict (counter_id) do update
    set summary = excluded.summary, level_notes = excluded.level_notes,
        lane_cautions = excluded.lane_cautions, updated_by = excluded.updated_by,
        revision_id = excluded.revision_id;

  update public.edit_proposals
     set status = 'approved', approve_note = note, reviewed_by = (select auth.uid()), reviewed_at = now(), counter_id = cid,
         approved_content = case when new_doc is distinct from orig_doc then new_doc end,
         approved_build = case when new_build is distinct from orig_build then new_build end
   where id = p.id;
  if p.type = 'new_counter' then
    perform public.publish_proposal_build(p, cid, note, new_build,
                                          case when new_build is distinct from orig_build then orig_build end);
  end if;
  perform public.notify(p.proposer_id, 'proposal_approved', note, p.id, null);
  perform public.log_moderation('approve_proposal', 'proposal', p.id::text, note);
  -- 감독관이 처리하면 제안자·공개 빌드에서 읽을 수 있는 칸에 처리자를 남기지 않는다 (누가 했는지는 moderation_log에만)
  if public.is_moderator() then
    update public.edit_proposals set reviewed_by = null where id = p.id;
    update public.builds set reviewed_by = null where proposal_id = p.id;
  end if;
  -- (6단계) 경험치 지급은 여기에 추가 (고쳐서 승인해도 제안자에게)
  return cid;
end;
$$;

CREATE OR REPLACE FUNCTION public.reject_proposal(p_id bigint, p_reason text, p_version integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
begin
  perform public.require_staff();
  perform public.require_proposal_version(p_id, p_version);
  perform public.reject_proposal_unchecked(p_id, p_reason);
end;
$$;

CREATE OR REPLACE FUNCTION public.reject_proposal_unchecked(p_id bigint, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  reason text;
  p public.edit_proposals%rowtype;
begin
  perform public.require_staff();
  reason := public.require_note(p_reason, '거절 사유');
  select * into p from public.edit_proposals where id = p_id for update;
  if not found then
    raise exception '제안을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.require_review_allowed(p);
  if p.status not in ('pending', 'revision_requested') then
    raise exception '이미 처리된 제안입니다.' using errcode = '23514';
  end if;
  update public.edit_proposals
     set status = 'rejected', reject_reason = reason,
         reviewed_by = case when public.is_moderator() then null else (select auth.uid()) end, reviewed_at = now()
   where id = p_id;
  update public.notifications set read_at = now()
   where proposal_id = p.id and kind = 'revision_request' and read_at is null;
  if public.is_hidden_counter_flow(p) then
    insert into public.counter_status_log (counter_id, action, reason, proposal_id, actor)
    values (p.counter_id, 'reject', reason, p.id, (select auth.uid()));
  end if;
  perform public.notify(p.proposer_id, 'proposal_rejected', reason, p.id, null);
  perform public.log_moderation('reject_proposal', 'proposal', p.id::text, reason);
end;
$$;

-- 고치기 오류 문구: 감독관이 숨긴 글·댓글도 있으므로 "운영진이"
do $$
declare
  f record;
begin
  for f in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('edit_post', 'edit_comment')
  loop
    execute replace(pg_get_functiondef(f.oid), '운영자가 숨긴', '운영진이 숨긴');
  end loop;
  -- 자유게시판 목록의 작성자에 role이 없어 (운)이 붙지 않던 것을 고친다
  execute replace(pg_get_functiondef('public.board_page'::regproc),
    $s$jsonb_build_object('nickname', a.nickname, 'level', a.level,$s$,
    $s$jsonb_build_object('nickname', a.nickname, 'role', a.role, 'level', a.level,$s$);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 실행 권한: 화면이 부르는 것만 열고, 내부 함수는 닫는다
-- ---------------------------------------------------------------------
revoke execute on function public.is_moderator() from public;
revoke execute on function public.is_staff() from public;
revoke execute on function public.can_see_hidden(uuid) from public;
revoke execute on function public.moderatable_author(uuid) from public, anon;
revoke execute on function public.set_moderator(uuid, boolean, text) from public, anon;
revoke execute on function public.open_reports_for_moderator() from public, anon;
grant execute on function public.is_moderator() to anon, authenticated;     -- RLS 정책이 쓴다 (is_admin과 같음)
grant execute on function public.is_staff() to anon, authenticated;
grant execute on function public.can_see_hidden(uuid) to anon, authenticated;
grant execute on function public.moderatable_author(uuid) to authenticated;
grant execute on function public.set_moderator(uuid, boolean, text) to authenticated;
grant execute on function public.open_reports_for_moderator() to authenticated;

revoke execute on function public.require_staff() from public, anon, authenticated;
revoke execute on function public.require_moderate_target(uuid) from public, anon, authenticated;
revoke execute on function public.require_moderate_doc_counter(bigint) from public, anon, authenticated;
revoke execute on function public.require_restore_allowed(uuid) from public, anon, authenticated;
revoke execute on function public.require_review_allowed(public.edit_proposals) from public, anon, authenticated;
revoke execute on function public.log_moderation(text, text, text, text, text) from public, anon, authenticated;

commit;
