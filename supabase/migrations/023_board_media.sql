-- =====================================================================
-- 023: 노가리방 글·댓글에 사진·GIF 첨부 (Supabase Storage)
-- 1. 숫자 (xp_rules media_*): 글 4개(GIF 1개)·댓글 1개, 한 사람 하루 20개, 사진 600KB(화면이 400KB 안쪽으로 압축)·GIF 3MB,
--    전체 1024MB 중 800MB부터 운영자 경고, 900MB부터 새로 올리기 막음, 글에 안 붙은 파일은 24시간 뒤 정리.
-- 2. 비공개 버킷 board-media (파일당 3MB, webp·jpeg·gif). 경로 = 사용자id/임의이름.확장자
--    - 올리기: 닉네임 있는 회원만(비회원·로그인 안 함 불가), 내 폴더에만, 하루 개수·전체 용량 안에서 (media_upload_problem)
--    - 보기: 붙어 있는 글·댓글을 볼 수 있으면 누구나 (숨긴 글·댓글은 운영자만 — 글·댓글 읽기 규칙 그대로), 내가 올린 파일은 나도
-- 3. board_attachments: 파일 하나 = 글 또는 댓글 하나에 붙은 한 줄. 붙이기·바꾸기·빼기는 글·댓글 쓰기·고치기 함수로만
--    - create_post / edit_post / create_comment / edit_comment 에 p_media(경로 목록) 칸을 더한다. 고치기는 지금처럼 시간 제한 안에서만.
--    - 사진이 있으면 본문(댓글)은 비워도 된다 (글 제목은 필수)
-- 4. 지울 파일 대기열 storage_trash: 첨부가 빠지거나 글·댓글이 지워지면(삭제된 글 포함, 탈퇴·비회원 정리 포함) 경로를 적는다.
--    SQL로는 Storage 파일을 지울 수 없어서, Edge Function media-cleanup이 매일 대기열 + 안 붙은 파일을 Storage API로 지운다.
-- 5. 신고 사유 obscene(음란·잔혹한 사진) 추가
-- 6. 운영자 /admin "사진 저장 공간": media_usage()
-- 022_rename_wording.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 숫자
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('media_post_max', 4, '노가리방 글 하나에 붙일 수 있는 사진·GIF 수'),
  ('media_post_gif_max', 1, '노가리방 글 하나에 붙일 수 있는 GIF 수'),
  ('media_comment_max', 1, '노가리방 댓글 하나에 붙일 수 있는 사진·GIF 수'),
  ('media_daily_max', 20, '한 사람이 24시간 안에 올릴 수 있는 사진·GIF 수'),
  ('media_photo_max_kb', 600, '사진(webp·jpeg) 파일 하나 최대 KB (화면은 400KB 안쪽으로 압축해 올린다)'),
  ('media_gif_max_kb', 3072, 'GIF 파일 하나 최대 KB (압축하지 않음)'),
  ('media_total_mb', 1024, 'Storage 무료 용량 (MB) — 운영자 화면 막대의 기준'),
  ('media_warn_mb', 800, '사진 저장 공간이 이만큼(MB) 차면 운영자 화면에 경고'),
  ('media_block_mb', 900, '사진 저장 공간이 이만큼(MB) 차면 새로 올리기를 막는다 (글쓰기는 그대로)'),
  ('media_orphan_hours', 24, '올리고 글·댓글에 붙이지 않은 파일을 이 시간 뒤에 지운다');

-- ---------------------------------------------------------------------
-- 2. 버킷
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('board-media', 'board-media', false, 3145728, array['image/webp', 'image/jpeg', 'image/gif'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------
-- 3. 첨부 표와 지울 파일 대기열
-- ---------------------------------------------------------------------
create table public.board_attachments (
  id          bigint generated always as identity primary key,
  post_id     bigint references public.posts (id) on delete cascade,
  comment_id  bigint references public.post_comments (id) on delete cascade,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  path        text not null unique,
  mime        text not null check (mime in ('image/webp', 'image/jpeg', 'image/gif')),
  size        integer not null check (size > 0),
  position    smallint not null default 1,
  created_at  timestamptz not null default now(),
  check (num_nonnulls(post_id, comment_id) = 1)
);
create index board_attachments_post_idx on public.board_attachments (post_id, position) where post_id is not null;
create index board_attachments_comment_idx on public.board_attachments (comment_id, position) where comment_id is not null;
create index board_attachments_author_idx on public.board_attachments (author_id);
comment on table public.board_attachments is '노가리방 글·댓글에 붙은 사진·GIF (023). 쓰기는 글·댓글 함수로만, 읽기는 글·댓글 읽기 규칙을 따른다';

revoke all on public.board_attachments from anon, authenticated;
grant select on public.board_attachments to anon, authenticated;
alter table public.board_attachments enable row level security;
-- 글·댓글 표의 읽기 규칙(숨긴 것은 운영자만)이 그대로 적용된다
create policy "board_attachments: 글·댓글을 볼 수 있으면 읽기" on public.board_attachments
  for select using (
    (post_id is not null and exists (select 1 from public.posts p where p.id = post_id and p.deleted_at is null))
    or (comment_id is not null and exists (select 1 from public.post_comments c where c.id = comment_id))
  );

create table public.storage_trash (
  path       text primary key,
  reason     text not null,
  queued_at  timestamptz not null default now()
);
comment on table public.storage_trash is '지울 Storage 파일 (board-media). Edge Function media-cleanup이 지우고 줄을 뺀다. 아무도 직접 못 읽음';
revoke all on public.storage_trash from anon, authenticated;
alter table public.storage_trash enable row level security;

-- 첨부가 빠지면(직접 빼기, 글·댓글 삭제, 탈퇴) 파일을 대기열에
create function public.queue_attachment_file()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.storage_trash (path, reason)
  values (old.path, case when old.post_id is not null then 'post' else 'comment' end)
  on conflict (path) do nothing;
  return old;
end;
$$;
create trigger board_attachments_queue after delete on public.board_attachments
  for each row execute function public.queue_attachment_file();

-- "삭제된 글"로 남을 때(다른 사람 댓글이 있어 자리만 남김, 탈퇴 포함) 글의 사진은 지운다
create function public.drop_deleted_post_media()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.board_attachments where post_id = new.id;
  return null;
end;
$$;
create trigger posts_drop_media after update of deleted_at on public.posts
  for each row when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.drop_deleted_post_media();

-- ---------------------------------------------------------------------
-- 4. 올리기 검사 (Storage 규칙과 화면이 같이 쓴다)
-- ---------------------------------------------------------------------
-- 지금 사진 저장 공간 사용량 (바이트)
create function public.media_used_bytes()
returns bigint language sql stable security definer set search_path = ''
as $$
  select coalesce(sum((o.metadata ->> 'size')::bigint), 0)::bigint
  from storage.objects o where o.bucket_id = 'board-media';
$$;

-- 올릴 수 없는 이유 (올릴 수 있으면 null)
create function public.media_upload_problem()
returns text language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  today integer;
begin
  if me is null then
    return '로그인해야 사진을 올릴 수 있어요.';
  end if;
  if not public.has_nickname() then
    return '닉네임을 정해야 사진을 올릴 수 있어요.';
  end if;
  if public.is_guest(me) then
    return '비회원은 사진을 올릴 수 없어요. 구글·카카오를 연결하면 할 수 있어요.';
  end if;
  if public.media_used_bytes() >= public.xp_rule('media_block_mb')::bigint * 1024 * 1024 then
    return '지금은 사진 저장 공간이 거의 차서 사진을 올릴 수 없어요. 글은 그대로 쓸 수 있어요.';
  end if;
  select count(*) into today from storage.objects o
   where o.bucket_id = 'board-media' and o.owner_id = me::text and o.created_at > now() - interval '24 hours';
  if today >= public.xp_rule('media_daily_max') then
    return format('사진은 하루에 %s개까지 올릴 수 있어요. 내일 다시 해 주세요.', public.xp_rule('media_daily_max'));
  end if;
  return null;
end;
$$;
revoke execute on function public.media_used_bytes() from public, anon, authenticated;
revoke execute on function public.media_upload_problem() from public, anon;
grant execute on function public.media_upload_problem() to authenticated;

-- 붙어 있는 글·댓글을 지금 사람이 볼 수 있나 (부른 사람 권한으로 — 글·댓글·첨부 읽기 규칙이 그대로 적용)
create function public.media_visible(p_path text)
returns boolean language sql stable set search_path = ''
as $$
  select exists (select 1 from public.board_attachments a where a.path = p_path);
$$;
grant execute on function public.media_visible(text) to anon, authenticated;

-- 회원이 내 폴더에만 올린다
create policy "board-media 올리기" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'board-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.media_upload_problem() is null
  );
-- 볼 수 있는 글·댓글에 붙은 사진 + 내가 올린 파일
create policy "board-media 보기" on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'board-media'
    and (owner_id = (select auth.uid())::text or public.media_visible(name))
  );

-- ---------------------------------------------------------------------
-- 5. 붙이기·바꾸기·빼기 (글·댓글 함수 안에서만 부른다)
--    p_paths 순서 = 보이는 순서. 지금과 같으면 false, 바뀌었으면 true. 빠진 파일은 대기열로 (트리거)
-- ---------------------------------------------------------------------
create function public.media_set(p_post bigint, p_comment bigint, p_me uuid, p_paths text[])
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  paths text[] := coalesce(p_paths, '{}');
  cur text[];
  maxn integer := public.xp_rule(case when p_post is not null then 'media_post_max' else 'media_comment_max' end);
  o record;
  m text;
  sz integer;
  gifs integer := 0;
  i integer;
begin
  select coalesce(array_agg(a.path order by a.position), '{}') into cur
  from public.board_attachments a
  where (p_post is not null and a.post_id = p_post) or (p_comment is not null and a.comment_id = p_comment);
  if cur = paths then
    return false;
  end if;

  if cardinality(paths) > maxn then
    raise exception '%에는 사진을 %개까지 붙일 수 있어요.', case when p_post is not null then '글' else '댓글' end, maxn
      using errcode = '23514';
  end if;
  if (select count(distinct x) from unnest(paths) x) <> cardinality(paths) then
    raise exception '같은 사진이 두 번 들어 있어요.' using errcode = '23514';
  end if;
  if cardinality(paths) > cardinality(cur) or exists (select 1 from unnest(paths) x where not (x = any(cur))) then
    if public.is_guest(p_me) then
      raise exception '비회원은 사진을 올릴 수 없어요. 구글·카카오를 연결하면 할 수 있어요.' using errcode = '42501';
    end if;
  end if;

  for i in 1 .. cardinality(paths) loop
    if paths[i] = any(cur) then
      select a.mime into m from public.board_attachments a where a.path = paths[i];
    else
      select ob.name, ob.owner_id, ob.metadata into o
      from storage.objects ob where ob.bucket_id = 'board-media' and ob.name = paths[i];
      if not found or o.owner_id is distinct from p_me::text then
        raise exception '올린 사진을 찾지 못했어요. 사진을 다시 골라 주세요.' using errcode = '23514';
      end if;
      if exists (select 1 from public.board_attachments a where a.path = paths[i]) then
        raise exception '다른 글·댓글에 붙은 사진이에요. 사진을 다시 골라 주세요.' using errcode = '23514';
      end if;
      m := o.metadata ->> 'mimetype';
      sz := coalesce((o.metadata ->> 'size')::integer, 0);
      if m is null or m not in ('image/webp', 'image/jpeg', 'image/gif') or sz <= 0 then
        raise exception '사진은 JPG·PNG·WebP·GIF만 붙일 수 있어요.' using errcode = '23514';
      end if;
      if m = 'image/gif' and sz > public.xp_rule('media_gif_max_kb') * 1024 then
        raise exception 'GIF는 %MB까지 올릴 수 있어요.', trim(trailing '.' from trim(trailing '0' from round(public.xp_rule('media_gif_max_kb') / 1024.0, 1)::text))
          using errcode = '23514';
      end if;
      if m <> 'image/gif' and sz > public.xp_rule('media_photo_max_kb') * 1024 then
        raise exception '사진이 너무 커요. 다시 골라 주세요. (%KB까지)', public.xp_rule('media_photo_max_kb') using errcode = '23514';
      end if;
      delete from public.storage_trash where path = paths[i];  -- 빼 뒀던 내 파일을 다시 붙이면 지우지 않는다
      insert into public.board_attachments (post_id, comment_id, author_id, path, mime, size, position)
      values (p_post, p_comment, p_me, paths[i], m, sz, i);
    end if;
    if m = 'image/gif' then
      gifs := gifs + 1;
    end if;
  end loop;
  if p_post is not null and gifs > public.xp_rule('media_post_gif_max') then
    raise exception 'GIF는 글 하나에 %개까지 붙일 수 있어요.', public.xp_rule('media_post_gif_max') using errcode = '23514';
  end if;

  delete from public.board_attachments a
   where ((p_post is not null and a.post_id = p_post) or (p_comment is not null and a.comment_id = p_comment))
     and not (a.path = any(paths));
  update public.board_attachments a set position = array_position(paths, a.path)
   where ((p_post is not null and a.post_id = p_post) or (p_comment is not null and a.comment_id = p_comment))
     and a.position is distinct from array_position(paths, a.path);
  return true;
end;
$$;
revoke execute on function public.media_set(bigint, bigint, uuid, text[]) from public, anon, authenticated;

-- 사진만 있는 글·댓글: 본문을 비울 수 있게 (빈 본문은 사진이 있을 때만 — 함수가 검사)
alter table public.posts drop constraint posts_body_check;
alter table public.posts add constraint posts_body_check check (deleted_at is not null or char_length(btrim(body)) <= 10000);
alter table public.post_comments drop constraint post_comments_body_check;
alter table public.post_comments add constraint post_comments_body_check check (char_length(btrim(body)) <= 1000);

-- 글자 검사: 사진이 있으면 비워도 된다 (빈 문자열을 돌려줌)
create function public.board_text_or_empty(p_text text, p_what text, p_max integer, p_allow_empty boolean)
returns text language plpgsql immutable set search_path = ''
as $$
begin
  if p_allow_empty and btrim(coalesce(p_text, ''), E' \t\r\n') = '' then
    return '';
  end if;
  return public.board_text(p_text, p_what, p_max);
end;
$$;
revoke execute on function public.board_text_or_empty(text, text, integer, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. 글·댓글 함수에 사진 칸 (예전 함수는 지우고 같은 이름으로 다시 만든다 — 사진 없이 부르면 예전과 같다)
-- ---------------------------------------------------------------------
drop function public.create_post(text, text);
drop function public.edit_post(bigint, text, text);
drop function public.create_comment(bigint, text);
drop function public.edit_comment(bigint, text);

create function public.create_post(p_title text, p_body text, p_media text[] default '{}')
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  t text := public.board_text(p_title, '제목', 100);
  b text := public.board_text_or_empty(p_body, '본문', 10000, cardinality(coalesce(p_media, '{}')) > 0);
  new_id bigint;
begin
  perform public.board_throttle(me, 'post');
  insert into public.posts (author_id, title, body) values (me, t, b) returning id into new_id;
  perform public.media_set(new_id, null, me, p_media);
  return new_id;
end;
$$;

-- p_media: null이면 사진은 그대로, 목록이면 그 목록으로 바꾼다 (빈 목록 = 모두 빼기)
create function public.edit_post(p_id bigint, p_title text, p_body text, p_media text[] default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  p public.posts%rowtype := public.board_post_for_update(p_id);
  keep_count integer;
  t text;
  b text;
  changed boolean;
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
  perform public.require_edit_window('post', p.created_at, p.edit_grace_until);
  keep_count := coalesce(cardinality(p_media), (select count(*) from public.board_attachments where post_id = p.id));
  t := public.board_text(p_title, '제목', 100);
  b := public.board_text_or_empty(p_body, '본문', 10000, keep_count > 0);
  changed := false;
  if p_media is not null then
    changed := public.media_set(p.id, null, me, p_media);
  end if;
  if t = p.title and b = p.body and not changed then
    return;  -- 바뀐 게 없으면 "수정됨"도 붙이지 않는다
  end if;
  update public.posts set title = t, body = b, edited_at = now() where id = p.id;
end;
$$;

-- 돌려주는 값: 새 댓글 id. 글쓴이에게 알림 (안 읽은 알림이 있으면 "새 댓글 N개"로 합친다)
create function public.create_comment(p_post bigint, p_body text, p_media text[] default '{}')
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b text := public.board_text_or_empty(p_body, '댓글', 1000, cardinality(coalesce(p_media, '{}')) > 0);
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
  perform public.media_set(null, new_id, me, p_media);

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

create function public.edit_comment(p_id bigint, p_body text, p_media text[] default null)
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
  if not found then
    raise exception '댓글을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  if c.author_id <> me then
    raise exception '내 댓글만 고칠 수 있어요.' using errcode = '42501';
  end if;
  if c.status <> 'visible' or exists (select 1 from public.posts where id = c.post_id and status <> 'visible') then
    raise exception '운영자가 숨긴 댓글·글은 고칠 수 없어요.' using errcode = '23514';
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

revoke execute on function public.create_post(text, text, text[]) from public, anon;
revoke execute on function public.edit_post(bigint, text, text, text[]) from public, anon;
revoke execute on function public.create_comment(bigint, text, text[]) from public, anon;
revoke execute on function public.edit_comment(bigint, text, text[]) from public, anon;
grant execute on function public.create_post(text, text, text[]) to authenticated;
grant execute on function public.edit_post(bigint, text, text, text[]) to authenticated;
grant execute on function public.create_comment(bigint, text, text[]) to authenticated;
grant execute on function public.edit_comment(bigint, text, text[]) to authenticated;

-- 글 목록: 사진 수 (목록에는 사진을 띄우지 않고 표시만)
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
  where pat is null or (p.deleted_at is null and (p.title ilike pat or p.body ilike pat));

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into items
  from (
    select p.id, p.title, p.status, p.deleted_at is not null as deleted, p.comment_count, p.up_count,
           p.created_at, p.edited_at,
           (select count(*) from public.board_attachments a where a.post_id = p.id) as media_count,
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
-- 7. 신고 사유: obscene (음란·잔혹한 사진)
-- ---------------------------------------------------------------------
alter table public.reports drop constraint reports_reason_check;
alter table public.reports add constraint reports_reason_check
  check (reason in ('abuse', 'hate', 'obscene', 'spam', 'privacy', 'other'));

create or replace function public.board_report_check(p_reason text, p_detail text)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  d text := nullif(btrim(coalesce(p_detail, '')), '');
begin
  if p_reason is null or p_reason not in ('abuse', 'hate', 'obscene', 'spam', 'privacy', 'other') then
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

-- ---------------------------------------------------------------------
-- 8. 운영자: 사진 저장 공간
-- ---------------------------------------------------------------------
create function public.media_usage()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  orphan_before timestamptz := now() - make_interval(hours => public.xp_rule('media_orphan_hours'));
  r jsonb;
begin
  if not public.is_admin() then
    raise exception '운영자만 할 수 있어요.' using errcode = '42501';
  end if;
  with o as (
    select ob.name, ob.owner_id, ob.created_at, coalesce((ob.metadata ->> 'size')::bigint, 0) as size,
           coalesce(ob.metadata ->> 'mimetype', '') as mime
    from storage.objects ob where ob.bucket_id = 'board-media'
  ),
  hidden as (
    select a.path from public.board_attachments a
    left join public.posts p on p.id = a.post_id
    left join public.post_comments c on c.id = a.comment_id
    left join public.posts cp on cp.id = c.post_id
    where p.status = 'hidden' or c.status = 'hidden' or cp.status = 'hidden'
  ),
  top as (
    select pr.nickname, count(*) as files, sum(o.size) as bytes
    from o left join public.profiles pr on pr.id::text = o.owner_id
    group by pr.nickname order by sum(o.size) desc limit 5
  )
  select jsonb_build_object(
    'bytes', (select coalesce(sum(size), 0) from o),
    'files', (select count(*) from o),
    'gif_bytes', (select coalesce(sum(size), 0) from o where mime = 'image/gif'),
    'gifs', (select count(*) from o where mime = 'image/gif'),
    'hidden_bytes', (select coalesce(sum(o.size), 0) from o join hidden h on h.path = o.name),
    'recent_bytes', (select coalesce(sum(size), 0) from o where created_at > now() - interval '7 days'),
    'recent_files', (select count(*) from o where created_at > now() - interval '7 days'),
    'trash', (select count(*) from public.storage_trash),
    'orphans', (select count(*) from o
                where o.created_at < orphan_before
                  and not exists (select 1 from public.board_attachments a where a.path = o.name)),
    'top', (select coalesce(jsonb_agg(jsonb_build_object('nickname', nickname, 'files', files, 'bytes', bytes)), '[]'::jsonb) from top),
    'total_mb', public.xp_rule('media_total_mb'),
    'warn_mb', public.xp_rule('media_warn_mb'),
    'block_mb', public.xp_rule('media_block_mb')
  ) into r;
  return r;
end;
$$;
revoke execute on function public.media_usage() from public, anon;
grant execute on function public.media_usage() to authenticated;

-- ---------------------------------------------------------------------
-- 9. 정리 (Edge Function media-cleanup이 service_role로 부른다)
-- ---------------------------------------------------------------------
-- 지울 경로: 대기열 + 글·댓글에 안 붙은 채 media_orphan_hours가 지난 파일
create function public.media_cleanup_list(p_limit integer default 100)
returns text[] language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(x.path), '{}') from (
    select t.path from public.storage_trash t
    where not exists (select 1 from public.board_attachments a where a.path = t.path)
    union
    select ob.name from storage.objects ob
    where ob.bucket_id = 'board-media'
      and ob.created_at < now() - make_interval(hours => public.xp_rule('media_orphan_hours'))
      and not exists (select 1 from public.board_attachments a where a.path = ob.name)
    limit greatest(least(coalesce(p_limit, 100), 1000), 1)
  ) x;
$$;

-- 지운 경로를 대기열에서 뺀다 (그 사이 다시 붙은 파일이 있으면 그 경로는 남겨 둔다)
create function public.media_cleanup_done(p_paths text[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  delete from public.storage_trash t
   where t.path = any(coalesce(p_paths, '{}'))
     and not exists (select 1 from public.board_attachments a where a.path = t.path);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.media_cleanup_list(integer) from public, anon, authenticated;
revoke execute on function public.media_cleanup_done(text[]) from public, anon, authenticated;
grant execute on function public.media_cleanup_list(integer) to service_role;
grant execute on function public.media_cleanup_done(text[]) to service_role;

revoke execute on function public.queue_attachment_file() from public, anon, authenticated;
revoke execute on function public.drop_deleted_post_media() from public, anon, authenticated;

commit;
