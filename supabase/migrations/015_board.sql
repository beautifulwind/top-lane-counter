-- =====================================================================
-- 7단계: 자유게시판 (SPEC 3장 /board, 6-5)
-- - 글·댓글은 승인 없이 바로 올라간다. 쓰기는 로그인 + 닉네임, 읽기는 누구나.
-- - 쓰기·고치기·지우기·추천·신고는 모두 아래 함수로만 (직접 insert/update/delete 권한은 없앤다)
--   → 도배 간격(글 30초·댓글 5초, xp_rules에서 바꿈), 길이 검사, "수정됨", 알림을 한곳에서 처리
-- - 글 지우기: 다른 사람 댓글이 있으면 제목·본문을 비운 "삭제된 글"로 남긴다 (댓글과 그 경험치는 그대로).
--   남은 댓글이 모두 없어지면 그때 완전히 지운다. 탈퇴도 같은 규칙.
-- - 운영자: 숨기기(메모 필수) / 다시 공개(메모 필수) / 신고 기각. 운영자의 직접 삭제는 없앤다.
-- - 숨긴 글·댓글은 운영자만 본다. 숨긴 글의 댓글도 함께 안 보인다(댓글 쓴 사람의 경험치는 그대로).
-- - 추천: 한 사람 한 번(다시 누르면 취소), 내 글은 안 됨, 경험치·알림 없음.
-- - 경험치: 014 방식 그대로 키 post:<id> / comment:<id>, 하루(한국 시간) 상한, 숨김·삭제하면 회수.
-- - 탑신병자: 승인된 기여 또는 보이는 글·댓글이 1개 이상.
-- 014_xp_levels_titles.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 글·댓글 칸
-- ---------------------------------------------------------------------
alter table public.posts
  add column status      text not null default 'visible' check (status in ('visible', 'hidden')),
  add column hidden_note text,
  add column hidden_at   timestamptz,
  add column hidden_by   uuid references public.profiles (id) on delete set null,
  add column edited_at   timestamptz,
  add column deleted_at  timestamptz,
  add column comment_count integer not null default 0,
  add column up_count    integer not null default 0;
-- 삭제된 글(제목·본문 비움)도 남을 수 있게 길이 검사를 바꾼다
alter table public.posts drop constraint posts_title_check, drop constraint posts_body_check;
alter table public.posts
  add constraint posts_title_check check (deleted_at is not null or char_length(btrim(title)) between 1 and 100),
  add constraint posts_body_check check (deleted_at is not null or char_length(btrim(body)) between 1 and 10000);
-- 탈퇴해도 다른 사람 댓글이 달린 글은 "삭제된 글"로 남는다 (작성자 = 비움)
alter table public.posts alter column author_id drop not null;
alter table public.posts drop constraint posts_author_id_fkey;
alter table public.posts
  add constraint posts_author_id_fkey foreign key (author_id) references public.profiles (id) on delete set null;
create index posts_author_idx on public.posts (author_id, created_at);

alter table public.post_comments
  add column status      text not null default 'visible' check (status in ('visible', 'hidden')),
  add column hidden_note text,
  add column hidden_at   timestamptz,
  add column hidden_by   uuid references public.profiles (id) on delete set null,
  add column edited_at   timestamptz;
alter table public.post_comments drop constraint post_comments_body_check;
alter table public.post_comments add constraint post_comments_body_check check (char_length(btrim(body)) between 1 and 1000);
create index post_comments_author_idx on public.post_comments (author_id, created_at);

-- 추천 (한 사람 한 번)
create table public.post_votes (
  post_id    bigint not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- 신고 (같은 사람이 같은 글·댓글은 한 번만)
create table public.reports (
  id           bigint generated always as identity primary key,
  reporter_id  uuid not null references public.profiles (id) on delete cascade,
  post_id      bigint references public.posts (id) on delete cascade,
  comment_id   bigint references public.post_comments (id) on delete cascade,
  reason       text not null check (reason in ('abuse', 'spam', 'privacy', 'other')),
  detail       text check (detail is null or char_length(detail) <= 500),
  status       text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  handled_by   uuid references public.profiles (id) on delete set null,
  handled_at   timestamptz,
  handled_note text,
  created_at   timestamptz not null default now(),
  check ((post_id is null) <> (comment_id is null)),
  check (reason <> 'other' or detail is not null)
);
comment on table public.reports is '게시판 신고 — 운영자만 본다. 숨기면 resolved, 기각하면 dismissed';
create unique index reports_once_post on public.reports (reporter_id, post_id) where post_id is not null;
create unique index reports_once_comment on public.reports (reporter_id, comment_id) where comment_id is not null;
create index reports_open_idx on public.reports (created_at) where status = 'open';

-- 도배 방지: 사람마다 마지막으로 쓴 때 (글을 지워도 남는다)
create table public.board_last_write (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  post_at    timestamptz,
  comment_at timestamptz
);

insert into public.xp_rules (key, value, note) values
  ('post_interval',    30, '자유게시판 글 최소 간격 (초, 도배 방지)'),
  ('comment_interval',  5, '자유게시판 댓글 최소 간격 (초, 도배 방지)');
update public.xp_rules set note = replace(note, ' (게시판 단계)', '') where key in ('post', 'post_daily_cap', 'comment', 'comment_daily_cap');

-- ---------------------------------------------------------------------
-- 2. 권한: 읽기만 직접, 쓰기는 함수로만
-- ---------------------------------------------------------------------
revoke insert, update, delete on public.posts, public.post_comments from authenticated;
drop policy "posts: 본인 작성" on public.posts;
drop policy "posts: 본인 수정" on public.posts;
drop policy "posts: 본인 또는 관리자 삭제" on public.posts;
drop policy "post_comments: 본인 작성" on public.post_comments;
drop policy "post_comments: 본인 수정" on public.post_comments;
drop policy "post_comments: 본인 또는 관리자 삭제" on public.post_comments;

drop policy "posts: 누구나 읽기" on public.posts;
create policy "posts: 읽기 (숨긴 글은 운영자만)" on public.posts
  for select using (status = 'visible' or public.is_admin());
drop policy "post_comments: 누구나 읽기" on public.post_comments;
create policy "post_comments: 읽기 (숨긴 것은 운영자만)" on public.post_comments
  for select using (
    public.is_admin()
    or (status = 'visible' and exists (select 1 from public.posts p where p.id = post_id and p.status = 'visible'))
  );

revoke all on public.post_votes, public.reports, public.board_last_write from anon, authenticated;
grant select on public.post_votes, public.reports to authenticated;
alter table public.post_votes enable row level security;
alter table public.reports enable row level security;
alter table public.board_last_write enable row level security;
create policy "post_votes: 내 추천 읽기" on public.post_votes
  for select to authenticated using (user_id = (select auth.uid()));
create policy "reports: 운영자 읽기" on public.reports
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 3. 알림 종류 + 글 연결
-- ---------------------------------------------------------------------
alter table public.notifications add column post_id bigint references public.posts (id) on delete cascade;
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check check (kind in (
    'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected',
    'build_approved', 'build_rejected', 'build_hidden', 'build_restored',
    'level_up', 'level_down', 'title_earned', 'title_revoked',
    'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored'));

-- ---------------------------------------------------------------------
-- 4. 도우미
-- ---------------------------------------------------------------------
-- 쓰는 사람: 로그인 + 닉네임
create function public.board_writer()
returns uuid language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  if not public.has_nickname() then
    raise exception '닉네임을 정해야 쓸 수 있어요.' using errcode = '42501';
  end if;
  return me;
end;
$$;

-- 글자 검사 (앞뒤 공백을 뺀 값을 돌려준다)
create function public.board_text(p_text text, p_what text, p_max integer)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  v text := btrim(coalesce(p_text, ''), E' \t\r\n');
begin
  if v = '' then
    raise exception '%을 적어 주세요.', p_what using errcode = '23514';
  end if;
  if char_length(v) > p_max then
    raise exception '%은 %자 이하로 적어 주세요. (지금 %자)', p_what, p_max, char_length(v) using errcode = '23514';
  end if;
  return v;
end;
$$;

-- 도배 방지: 같은 사람이 글은 post_interval초, 댓글은 comment_interval초 안에 다시 못 쓴다 (동시에 두 번 보내도 한 번만)
create function public.board_throttle(p_user uuid, p_kind text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  last timestamptz;
  gap integer := public.xp_rule(p_kind || '_interval');
  wait integer;
begin
  insert into public.board_last_write (user_id) values (p_user) on conflict do nothing;
  select case when p_kind = 'post' then post_at else comment_at end into last
  from public.board_last_write where user_id = p_user for update;
  if last is not null and gap > 0 and now() < last + make_interval(secs => gap) then
    wait := greatest(ceil(extract(epoch from (last + make_interval(secs => gap) - now())))::integer, 1);
    raise exception '%은 %초에 한 번 쓸 수 있어요. %초 뒤에 다시 해 주세요.',
      case when p_kind = 'post' then '글' else '댓글' end, gap, wait using errcode = 'P0001';
  end if;
  if p_kind = 'post' then
    update public.board_last_write set post_at = now() where user_id = p_user;
  else
    update public.board_last_write set comment_at = now() where user_id = p_user;
  end if;
end;
$$;

-- 알림에 넣을 글 제목 (앞 20자)
create function public.post_snippet(p_title text)
returns text language sql immutable set search_path = ''
as $$
  select case when char_length(p_title) > 20 then left(p_title, 20) || '…' else p_title end;
$$;

-- 게시판 알림 (받는 사람이 나면 보내지 않는다)
create function public.notify_post(p_user uuid, p_kind text, p_message text, p_post bigint)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if p_user is null or p_user = (select auth.uid()) then
    return;
  end if;
  insert into public.notifications (user_id, kind, message, post_id) values (p_user, p_kind, p_message, p_post);
end;
$$;

create function public.board_post_for_update(p_id bigint)
returns public.posts language plpgsql security definer set search_path = ''
as $$
declare
  p public.posts%rowtype;
begin
  select * into p from public.posts where id = p_id for update;
  if not found then
    raise exception '글을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  return p;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 글: 쓰기 / 고치기 / 지우기 / 추천
-- ---------------------------------------------------------------------
-- 돌려주는 값: 새 글 id
create function public.create_post(p_title text, p_body text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  t text := public.board_text(p_title, '제목', 100);
  b text := public.board_text(p_body, '본문', 10000);
  new_id bigint;
begin
  perform public.board_throttle(me, 'post');
  insert into public.posts (author_id, title, body) values (me, t, b) returning id into new_id;
  return new_id;
end;
$$;

create function public.edit_post(p_id bigint, p_title text, p_body text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  t text := public.board_text(p_title, '제목', 100);
  b text := public.board_text(p_body, '본문', 10000);
  p public.posts%rowtype := public.board_post_for_update(p_id);
begin
  if p.author_id is distinct from me then
    raise exception '내 글만 고칠 수 있어요.' using errcode = '42501';
  end if;
  if p.deleted_at is not null then
    raise exception '삭제된 글이에요.' using errcode = '23514';
  end if;
  if p.status <> 'visible' then
    raise exception '운영자가 숨긴 글은 고칠 수 없어요.' using errcode = '23514';
  end if;
  if t = p.title and b = p.body then
    return;  -- 바뀐 게 없으면 "수정됨"도 붙이지 않는다
  end if;
  update public.posts set title = t, body = b, edited_at = now() where id = p.id;
end;
$$;

-- 돌려주는 값: 'soft'(다른 사람 댓글이 있어 "삭제된 글"로 남김) / 'hard'(완전히 지움)
create function public.delete_my_post(p_id bigint)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  p public.posts%rowtype := public.board_post_for_update(p_id);
begin
  if me is null or p.author_id is distinct from me then
    raise exception '내 글만 지울 수 있어요.' using errcode = '42501';
  end if;
  if p.deleted_at is not null then
    raise exception '이미 삭제된 글이에요.' using errcode = '23514';
  end if;
  if exists (select 1 from public.post_comments c where c.post_id = p.id and c.author_id <> me) then
    update public.posts set title = '', body = '', deleted_at = now(), up_count = 0 where id = p.id;
    delete from public.post_votes where post_id = p.id;
    update public.reports set status = 'dismissed', handled_at = now(), handled_note = '작성자가 글을 지움'
    where post_id = p.id and status = 'open';
    return 'soft';
  end if;
  delete from public.posts where id = p.id;  -- 내 댓글·추천·신고·알림도 함께 지워진다
  return 'hard';
end;
$$;

-- 추천 누르기/취소. 돌려주는 값: {up, mine}
create function public.vote_post(p_id bigint)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  p public.posts%rowtype := public.board_post_for_update(p_id);
  mine boolean;
begin
  if p.deleted_at is not null or p.status <> 'visible' then
    raise exception '추천할 수 없는 글이에요.' using errcode = '23514';
  end if;
  if p.author_id = me then
    raise exception '내 글은 추천할 수 없어요.' using errcode = '23514';
  end if;
  delete from public.post_votes where post_id = p.id and user_id = me;
  mine := not found;
  if mine then
    insert into public.post_votes (post_id, user_id) values (p.id, me);
  end if;
  update public.posts set up_count = (select count(*) from public.post_votes where post_id = p.id)
  where id = p.id returning up_count into p.up_count;
  return jsonb_build_object('up', p.up_count, 'mine', mine);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 댓글: 쓰기 / 고치기 / 지우기
-- ---------------------------------------------------------------------
-- 돌려주는 값: 새 댓글 id. 글쓴이에게 알림 (안 읽은 알림이 있으면 "새 댓글 N개"로 합친다)
create function public.create_comment(p_post bigint, p_body text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b text := public.board_text(p_body, '댓글', 1000);
  p public.posts%rowtype;
  new_id bigint;
  n public.notifications%rowtype;
  cnt integer;
begin
  select * into p from public.posts where id = p_post;
  if not found or p.status <> 'visible' then
    raise exception '글을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if p.deleted_at is not null then
    raise exception '삭제된 글에는 댓글을 달 수 없어요.' using errcode = '23514';
  end if;
  perform public.board_throttle(me, 'comment');
  insert into public.post_comments (post_id, author_id, body) values (p.id, me, b) returning id into new_id;

  if p.author_id is not null and p.author_id <> me then
    select * into n from public.notifications
    where user_id = p.author_id and kind = 'post_comment' and post_id = p.id and read_at is null
    order by created_at limit 1 for update;
    if found then
      select count(*) into cnt from public.post_comments
      where post_id = p.id and author_id <> p.author_id and status = 'visible' and created_at >= n.created_at;
      update public.notifications
      set message = format('내 글 「%s」에 새 댓글 %s개가 달렸어요.', public.post_snippet(p.title), greatest(cnt, 2))
      where id = n.id;
    else
      perform public.notify_post(p.author_id, 'post_comment',
        format('내 글 「%s」에 새 댓글이 달렸어요.', public.post_snippet(p.title)), p.id);
    end if;
  end if;
  return new_id;
end;
$$;

create function public.edit_comment(p_id bigint, p_body text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b text := public.board_text(p_body, '댓글', 1000);
  c public.post_comments%rowtype;
begin
  select * into c from public.post_comments where id = p_id for update;
  if not found then
    raise exception '댓글을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if c.author_id <> me then
    raise exception '내 댓글만 고칠 수 있어요.' using errcode = '42501';
  end if;
  if c.status <> 'visible' or exists (select 1 from public.posts where id = c.post_id and status <> 'visible') then
    raise exception '운영자가 숨긴 댓글·글은 고칠 수 없어요.' using errcode = '23514';
  end if;
  if b = c.body then
    return;
  end if;
  update public.post_comments set body = b, edited_at = now() where id = c.id;
end;
$$;

create function public.delete_my_comment(p_id bigint)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  c public.post_comments%rowtype;
begin
  select * into c from public.post_comments where id = p_id for update;
  if not found then
    raise exception '댓글을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if me is null or c.author_id <> me then
    raise exception '내 댓글만 지울 수 있어요.' using errcode = '42501';
  end if;
  delete from public.post_comments where id = c.id;
end;
$$;

-- 댓글 수 (보이는 댓글만) + 댓글이 모두 없어진 "삭제된 글"은 완전히 지운다
create function public.post_comments_after()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  pid bigint := case when tg_op = 'DELETE' then old.post_id else new.post_id end;
begin
  update public.posts
  set comment_count = (select count(*) from public.post_comments where post_id = pid and status = 'visible')
  where id = pid;
  if tg_op = 'DELETE' then
    delete from public.posts p
    where p.id = pid and p.deleted_at is not null
      and not exists (select 1 from public.post_comments c where c.post_id = pid);
  end if;
  return null;
end;
$$;
create trigger post_comments_after after insert or update of status or delete on public.post_comments
  for each row execute function public.post_comments_after();

-- 탈퇴: 다른 사람 댓글이 달린 내 글은 "삭제된 글"로 남기고, 나머지는 지운다 (내 댓글은 FK가 지운다)
create function public.board_on_profile_delete()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update public.posts p set title = '', body = '', deleted_at = coalesce(p.deleted_at, now()), up_count = 0
  where p.author_id = old.id
    and exists (select 1 from public.post_comments c where c.post_id = p.id and c.author_id <> old.id);
  delete from public.posts p where p.author_id = old.id and p.deleted_at is null;
  delete from public.posts p
  where p.author_id = old.id
    and not exists (select 1 from public.post_comments c where c.post_id = p.id and c.author_id <> old.id);
  return old;
end;
$$;
create trigger profiles_board_delete before delete on public.profiles
  for each row execute function public.board_on_profile_delete();

-- ---------------------------------------------------------------------
-- 7. 신고
-- ---------------------------------------------------------------------
create function public.board_report_check(p_reason text, p_detail text)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  d text := nullif(btrim(coalesce(p_detail, '')), '');
begin
  if p_reason is null or p_reason not in ('abuse', 'spam', 'privacy', 'other') then
    raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
  end if;
  if p_reason = 'other' and d is null then
    raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(d) > 500 then
    raise exception '신고 내용은 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  return d;
end;
$$;

create function public.report_post(p_id bigint, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  d text := public.board_report_check(p_reason, p_detail);
  p public.posts%rowtype;
begin
  select * into p from public.posts where id = p_id;
  if not found or p.status <> 'visible' or p.deleted_at is not null then
    raise exception '신고할 수 없는 글이에요.' using errcode = 'P0002';
  end if;
  if p.author_id = me then
    raise exception '내 글은 신고할 수 없어요.' using errcode = '23514';
  end if;
  insert into public.reports (reporter_id, post_id, reason, detail) values (me, p.id, p_reason, d);
exception when unique_violation then
  raise exception '이미 신고한 글이에요.' using errcode = '23505';
end;
$$;

create function public.report_comment(p_id bigint, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  d text := public.board_report_check(p_reason, p_detail);
  c public.post_comments%rowtype;
begin
  select * into c from public.post_comments where id = p_id;
  if not found or c.status <> 'visible'
     or exists (select 1 from public.posts where id = c.post_id and status <> 'visible') then
    raise exception '신고할 수 없는 댓글이에요.' using errcode = 'P0002';
  end if;
  if c.author_id = me then
    raise exception '내 댓글은 신고할 수 없어요.' using errcode = '23514';
  end if;
  insert into public.reports (reporter_id, comment_id, reason, detail) values (me, c.id, p_reason, d);
exception when unique_violation then
  raise exception '이미 신고한 댓글이에요.' using errcode = '23505';
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 운영자: 숨기기 / 다시 공개 / 신고 기각
-- ---------------------------------------------------------------------
create function public.hide_post(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  p public.posts%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '숨기는 이유');
  p := public.board_post_for_update(p_id);
  if p.status = 'hidden' then
    raise exception '이미 숨긴 글이에요.' using errcode = '23514';
  end if;
  if p.deleted_at is not null then
    raise exception '삭제된 글이에요.' using errcode = '23514';
  end if;
  update public.posts set status = 'hidden', hidden_note = note, hidden_at = now(), hidden_by = (select auth.uid())
  where id = p.id;
  update public.reports set status = 'resolved', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
  where post_id = p.id and status = 'open';
  perform public.notify_post(p.author_id, 'post_hidden',
    format('내 글 「%s」을 운영자가 숨겼어요. 메모: %s', public.post_snippet(p.title), note), p.id);
end;
$$;

create function public.restore_post(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  p public.posts%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '다시 공개 메모');
  p := public.board_post_for_update(p_id);
  if p.status <> 'hidden' then
    raise exception '숨긴 글이 아니에요.' using errcode = '23514';
  end if;
  update public.posts set status = 'visible', hidden_note = null, hidden_at = null, hidden_by = null where id = p.id;
  perform public.notify_post(p.author_id, 'post_restored',
    format('숨겨졌던 내 글 「%s」이 다시 공개됐어요. 메모: %s', public.post_snippet(p.title), note), p.id);
end;
$$;

create function public.hide_comment(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  c public.post_comments%rowtype;
  t text;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '숨기는 이유');
  select * into c from public.post_comments where id = p_id for update;
  if not found then
    raise exception '댓글을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if c.status = 'hidden' then
    raise exception '이미 숨긴 댓글이에요.' using errcode = '23514';
  end if;
  update public.post_comments set status = 'hidden', hidden_note = note, hidden_at = now(), hidden_by = (select auth.uid())
  where id = c.id;
  update public.reports set status = 'resolved', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
  where comment_id = c.id and status = 'open';
  select title into t from public.posts where id = c.post_id;
  perform public.notify_post(c.author_id, 'comment_hidden',
    format('「%s」에 쓴 내 댓글을 운영자가 숨겼어요. 메모: %s', public.post_snippet(coalesce(nullif(t, ''), '삭제된 글')), note), c.post_id);
end;
$$;

create function public.restore_comment(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  c public.post_comments%rowtype;
  t text;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '다시 공개 메모');
  select * into c from public.post_comments where id = p_id for update;
  if not found then
    raise exception '댓글을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if c.status <> 'hidden' then
    raise exception '숨긴 댓글이 아니에요.' using errcode = '23514';
  end if;
  update public.post_comments set status = 'visible', hidden_note = null, hidden_at = null, hidden_by = null where id = c.id;
  select title into t from public.posts where id = c.post_id;
  perform public.notify_post(c.author_id, 'comment_restored',
    format('숨겨졌던 내 댓글(「%s」)이 다시 공개됐어요. 메모: %s', public.post_snippet(coalesce(nullif(t, ''), '삭제된 글')), note), c.post_id);
end;
$$;

-- 신고 기각 (메모는 선택). 돌려주는 값: 기각한 신고 수
create function public.dismiss_reports(p_post bigint, p_comment bigint, p_note text default null)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  perform public.require_operator();
  if (p_post is null) = (p_comment is null) then
    raise exception '글이나 댓글 하나를 골라 주세요.' using errcode = '22023';
  end if;
  update public.reports
  set status = 'dismissed', handled_by = (select auth.uid()), handled_at = now(),
      handled_note = nullif(btrim(coalesce(p_note, '')), '')
  where status = 'open' and (post_id = p_post or comment_id = p_comment);
  get diagnostics n = row_count;
  if n = 0 then
    raise exception '처리할 신고가 없어요. (이미 처리됐을 수 있어요)' using errcode = 'P0002';
  end if;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 9. 목록·검색 (RLS 그대로: 숨긴 글은 운영자에게만). 돌려주는 값: {total, size, rows}
-- ---------------------------------------------------------------------
create function public.board_page(p_q text default null, p_page integer default 1, p_size integer default 20)
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
  where pat is null or (p.deleted_at is null and (p.title ilike pat or p.body ilike pat));

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into items
  from (
    select p.id, p.title, p.status, p.deleted_at is not null as deleted, p.comment_count, p.up_count,
           p.created_at, p.edited_at,
           (select jsonb_build_object('nickname', a.nickname, 'level', a.level, 'main_title', a.main_title)
            from public.profiles a where a.id = p.author_id) as author
    from public.posts p
    where pat is null or (p.deleted_at is null and (p.title ilike pat or p.body ilike pat))
    order by p.created_at desc, p.id desc
    limit sz offset (pg - 1) * sz
  ) x;
  return jsonb_build_object('total', total, 'size', sz, 'rows', items);
end;
$$;

-- ---------------------------------------------------------------------
-- 10. 경험치: 글·댓글 (014의 xp_should_have / xp_reason / sync_rewards에 더한다)
-- ---------------------------------------------------------------------
create or replace function public.xp_should_have(p_user uuid)
returns table (source_key text, kind text, ref_id text, amount integer, at timestamptz, target_champion text, counter_champion text)
language sql stable security definer set search_path = ''
as $$
  -- 새 카운터: 승인 + 카운터 공개 중 (숨기면 0, 다시 공개·재승인하면 같은 키로 돌아온다)
  select 'proposal:' || p.id, 'new_counter', p.id::text, public.xp_rule('new_counter'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'new_counter' and p.status = 'approved' and c.status = 'approved'
  union all
  -- 문서 수정: 승인 + 카운터가 있음 (숨김은 회수하지 않고 완전 삭제만)
  select 'proposal:' || p.id, 'doc_edit', p.id::text, public.xp_rule('doc_edit'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'doc_edit' and p.status = 'approved'
  union all
  -- 빌드: 공개 중, 새 카운터의 첫 빌드는 카운터 +100에 포함
  select 'build:' || b.id, 'build', b.id::text, public.xp_rule('build'), b.reviewed_at, c.target_champion, c.counter_champion
  from public.builds b join public.counters c on c.id = b.counter_id
  where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null
  union all
  -- 따봉: 처음 누른 따봉만, 받은 사람 기준 하루(한국 시간) 상한 — 상한은 지워진 빌드의 따봉까지 넣고 센다
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
  -- 게시판 댓글: 보이는 댓글 (글이 숨겨지거나 삭제된 글로 남아도 댓글 쓴 사람은 그대로)
  select 'comment:' || c.id, 'comment', c.id::text, public.xp_rule('comment'), c.created_at, null::text, null::text
  from (
    select c.id, c.created_at, row_number() over (
      partition by (c.created_at at time zone 'Asia/Seoul')::date order by c.created_at, c.id) as rn
    from public.post_comments c
    where c.author_id = p_user and c.status = 'visible'
  ) c
  where c.rn <= public.xp_rule('comment_daily_cap') / greatest(public.xp_rule('comment'), 1);
$$;

create or replace function public.xp_reason(p_kind text, p_ref text, p_want integer, p_have integer, p_seen boolean)
returns text language plpgsql stable security definer set search_path = ''
as $$
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
    if not found or cst is null then return '카운터 삭제'; end if;
    if st = 'revoked' or cst = 'hidden' then return '카운터 숨김 (승인 취소)'; end if;
    return '승인 취소';
  elsif p_kind = 'build' then
    select status into st from public.builds where id = p_ref::bigint;
    if not found then return '카운터 삭제'; end if;
    if st = 'hidden' then return '빌드 숨김'; end if;
    return '승인 취소';
  elsif p_kind = 'vote' then
    if not exists (select 1 from public.builds where id = p_ref::bigint) then return '빌드 삭제 (카운터 삭제)'; end if;
    return '규칙 변경';
  elsif p_kind = 'post' then
    select status, deleted_at into st, del from public.posts where id = p_ref::bigint;
    if not found or del is not null then return '글 삭제'; end if;
    if st = 'hidden' then return '글 숨김'; end if;
    return '규칙 변경';
  elsif p_kind = 'comment' then
    select status into st from public.post_comments where id = p_ref::bigint;
    if not found then return '댓글 삭제'; end if;
    if st = 'hidden' then return '댓글 숨김'; end if;
    return '규칙 변경';
  end if;
  return null;
end;
$$;

-- 014의 sync_rewards와 같고, 탑신병자에 "보이는 글·댓글 1개 이상"만 더했다
create or replace function public.sync_rewards(p_user uuid, p_quiet boolean default false)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  prof public.profiles%rowtype;
  r record;
  total integer;
  lv integer;
  counter_cnt integer;
  contrib_cnt integer;
  offmeta_cnt integer;
  board_cnt integer;
  ups integer;
  want text[];
  t text;
begin
  if p_user is null then
    return;
  end if;
  select * into prof from public.profiles where id = p_user for update;
  if not found or prof.role = 'admin' then
    return;  -- 탈퇴했거나 운영자 (항상 Lv.0, 경험치·칭호 없음)
  end if;

  -- 경험치: 키마다 (받아야 할 양 − 이미 받은 양)만 기록
  for r in
    with should as (select * from public.xp_should_have(p_user)),
    got as (
      select e.source_key, sum(e.amount)::integer as amount, max(e.type) as kind, max(e.ref_id) as ref_id,
             max(e.target_champion) as target_champion, max(e.counter_champion) as counter_champion
      from public.xp_events e where e.user_id = p_user and e.source_key is not null group by e.source_key
    )
    select coalesce(w.source_key, h.source_key) as source_key, coalesce(w.kind, h.kind) as kind,
           coalesce(w.ref_id, h.ref_id) as ref_id, coalesce(w.amount, 0) as want, coalesce(h.amount, 0) as have,
           h.source_key is not null as seen, w.at,
           coalesce(w.target_champion, h.target_champion) as target_champion,
           coalesce(w.counter_champion, h.counter_champion) as counter_champion
    from should w full join got h on h.source_key = w.source_key
    where coalesce(w.amount, 0) <> coalesce(h.amount, 0)
    order by coalesce(w.at, now())
  loop
    insert into public.xp_events
      (user_id, type, amount, ref_id, source_key, change, reason, target_champion, counter_champion, created_at)
    values (
      p_user, r.kind, r.want - r.have, r.ref_id, r.source_key,
      case when r.want = 0 then 'revoke' when r.have = 0 then 'grant' else 'adjust' end,
      public.xp_reason(r.kind, r.ref_id, r.want, r.have, r.seen),
      r.target_champion, r.counter_champion,
      case when p_quiet and r.have = 0 and r.at is not null then r.at else now() end
    );
  end loop;

  select greatest(coalesce(sum(amount), 0), 0) into total from public.xp_events where user_id = p_user;
  lv := public.level_for(total);
  if prof.xp is distinct from total or prof.level is distinct from lv then
    update public.profiles set xp = total, level = lv where id = p_user;
    if not p_quiet and lv > prof.level then
      insert into public.notifications (user_id, kind, message) values (p_user, 'level_up', format('레벨이 올랐어요: Lv.%s', lv));
    elsif not p_quiet and lv < prof.level then
      insert into public.notifications (user_id, kind, message)
      values (p_user, 'level_down', format('승인 취소·삭제로 경험치가 줄어 레벨이 내려갔어요: Lv.%s', lv));
    end if;
  end if;

  -- 칭호: 지금 유효한 기여만 센다 (경험치와 같은 기준, 새 카운터의 첫 빌드는 카운터와 함께 1개)
  with contrib as (
    select p.type as kind, p.offmeta
    from public.edit_proposals p join public.counters c on c.id = p.counter_id
    where p.proposer_id = p_user and p.status = 'approved' and (p.type = 'doc_edit' or c.status = 'approved')
    union all
    select 'build', b.offmeta
    from public.builds b join public.counters c on c.id = b.counter_id
    where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null
  )
  select count(*) filter (where kind in ('new_counter', 'doc_edit')), count(*), count(*) filter (where offmeta)
    into counter_cnt, contrib_cnt, offmeta_cnt
  from contrib;
  -- 탑신병자: 보이는 글·댓글도 센다 (숨김·삭제 제외, 1개만 확인하면 충분)
  select count(*) into board_cnt from (
    (select 1 from public.posts where author_id = p_user and status = 'visible' and deleted_at is null limit 1)
    union all
    (select 1 from public.post_comments where author_id = p_user and status = 'visible' limit 1)
  ) x;
  -- 장군: 공개 중인 내 빌드(카운터도 공개)의 지금 따봉 수 합계
  select coalesce(sum(b.up_count), 0) into ups
  from public.builds b join public.counters c on c.id = b.counter_id
  where b.author_id = p_user and b.status = 'approved' and c.status = 'approved';

  want := array_remove(array[
    case when contrib_cnt + board_cnt >= public.xp_rule('title_top_addict') then 'top_addict' end,
    case when counter_cnt >= public.xp_rule('title_tool_hater') then 'tool_hater' end,
    case when counter_cnt >= public.xp_rule('title_solid_heavy') then 'solid_heavy' end,
    case when counter_cnt >= public.xp_rule('title_butcher_owner') then 'butcher_owner' end,
    case when ups >= public.xp_rule('title_general') then 'general' end,
    case when offmeta_cnt >= public.xp_rule('title_offmeta') then 'offmeta' end
  ], null);

  for t in select title_key from public.user_titles where user_id = p_user and not (title_key = any (want)) loop
    delete from public.user_titles where user_id = p_user and title_key = t;  -- 대표 칭호였으면 FK가 비운다
    if not p_quiet then
      insert into public.notifications (user_id, kind, message)
      values (p_user, 'title_revoked', format('칭호가 회수됐어요: %s (승인 취소·삭제 등으로 조건이 깨졌어요)', public.title_name(t)));
    end if;
  end loop;
  foreach t in array want loop
    if not exists (select 1 from public.user_titles where user_id = p_user and title_key = t) then
      insert into public.user_titles (user_id, title_key) values (p_user, t);
      if not p_quiet then
        insert into public.notifications (user_id, kind, message)
        values (p_user, 'title_earned', format('칭호를 얻었어요: %s — [내 활동]에서 대표 칭호로 고를 수 있어요.', public.title_name(t)));
      end if;
    end if;
  end loop;
end;
$$;

-- 언제 다시 계산하나: 글·댓글을 쓰거나, 숨기거나 다시 공개하거나, 지울 때 (트랜잭션 끝에)
create function public.rewards_on_post()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.sync_rewards(case when tg_op = 'DELETE' then old.author_id else new.author_id end);
  return null;
end;
$$;
create constraint trigger posts_rewards after insert or update of status, deleted_at or delete on public.posts
  deferrable initially deferred for each row execute function public.rewards_on_post();
create constraint trigger post_comments_rewards after insert or update of status or delete on public.post_comments
  deferrable initially deferred for each row execute function public.rewards_on_post();

-- ---------------------------------------------------------------------
-- 11. 함수 권한
-- ---------------------------------------------------------------------
revoke execute on function public.board_writer() from public, anon, authenticated;
revoke execute on function public.board_text(text, text, integer) from public, anon, authenticated;
revoke execute on function public.board_throttle(uuid, text) from public, anon, authenticated;
revoke execute on function public.post_snippet(text) from public, anon, authenticated;
revoke execute on function public.notify_post(uuid, text, text, bigint) from public, anon, authenticated;
revoke execute on function public.board_post_for_update(bigint) from public, anon, authenticated;
revoke execute on function public.post_comments_after() from public, anon, authenticated;
revoke execute on function public.board_on_profile_delete() from public, anon, authenticated;
revoke execute on function public.board_report_check(text, text) from public, anon, authenticated;
revoke execute on function public.rewards_on_post() from public, anon, authenticated;

revoke execute on function public.create_post(text, text) from public, anon;
revoke execute on function public.edit_post(bigint, text, text) from public, anon;
revoke execute on function public.delete_my_post(bigint) from public, anon;
revoke execute on function public.vote_post(bigint) from public, anon;
revoke execute on function public.create_comment(bigint, text) from public, anon;
revoke execute on function public.edit_comment(bigint, text) from public, anon;
revoke execute on function public.delete_my_comment(bigint) from public, anon;
revoke execute on function public.report_post(bigint, text, text) from public, anon;
revoke execute on function public.report_comment(bigint, text, text) from public, anon;
revoke execute on function public.hide_post(bigint, text) from public, anon;
revoke execute on function public.restore_post(bigint, text) from public, anon;
revoke execute on function public.hide_comment(bigint, text) from public, anon;
revoke execute on function public.restore_comment(bigint, text) from public, anon;
revoke execute on function public.dismiss_reports(bigint, bigint, text) from public, anon;
grant execute on function public.create_post(text, text) to authenticated;
grant execute on function public.edit_post(bigint, text, text) to authenticated;
grant execute on function public.delete_my_post(bigint) to authenticated;
grant execute on function public.vote_post(bigint) to authenticated;
grant execute on function public.create_comment(bigint, text) to authenticated;
grant execute on function public.edit_comment(bigint, text) to authenticated;
grant execute on function public.delete_my_comment(bigint) to authenticated;
grant execute on function public.report_post(bigint, text, text) to authenticated;
grant execute on function public.report_comment(bigint, text, text) to authenticated;
grant execute on function public.hide_post(bigint, text) to authenticated;
grant execute on function public.restore_post(bigint, text) to authenticated;
grant execute on function public.hide_comment(bigint, text) to authenticated;
grant execute on function public.restore_comment(bigint, text) to authenticated;
grant execute on function public.dismiss_reports(bigint, bigint, text) to authenticated;
grant execute on function public.board_page(text, integer, integer) to anon, authenticated;

-- 기존 글·댓글이 있으면 경험치·칭호를 한 번 맞춘다 (알림 없음, 내역 날짜 = 실제로 쓴 날)
select public.recalc_all_xp(true) where exists (select 1 from public.posts) or exists (select 1 from public.post_comments);

commit;
