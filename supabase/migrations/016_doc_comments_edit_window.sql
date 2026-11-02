-- =====================================================================
-- 문서 댓글 + 고치기 시간 제한 (SPEC 6-6, 6-7)
-- 1. 매치업 문서 댓글 (doc_comments): 게시판 댓글과 같은 방식
--    - 로그인 + 닉네임, 승인 없이 바로, 본인 고치기·지우기, 운영자 숨기기·다시 공개(메모 필수), 신고는 reports로 함께
--    - 도배 간격은 게시판 댓글과 공유 (comment_interval), 경험치 +1, 하루 상한은 게시판 댓글과 합쳐서 comment_daily_cap
--    - 카운터를 숨기면 댓글도 운영자만 보고 새 댓글·고치기는 막힌다 (경험치는 그대로). 완전 삭제하면 같이 지워지고 회수
--    - 알림은 카운터 첫 제안자에게 (안 읽은 알림이 있으면 "새 댓글 N개"로 합침)
--    - 탑신병자: 보이는 문서 댓글도 센다
-- 2. 고치기 시간 제한: 글은 쓴 뒤 post_edit_minutes(60), 댓글·문서 댓글은 comment_edit_minutes(10)
--    - 마감 전에 고치는 화면을 열면(begin_edit) edit_grace_minutes(5)분 유예 → 늦어도 마감 + 5분까지
--    - 지우기는 언제든
-- 015_board.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

insert into public.xp_rules (key, value, note) values
  ('post_edit_minutes',    60, '자유게시판 글을 고칠 수 있는 시간 (쓴 뒤 분)'),
  ('comment_edit_minutes', 10, '게시판 댓글·문서 댓글을 고칠 수 있는 시간 (쓴 뒤 분)'),
  ('edit_grace_minutes',    5, '마감 전에 고치기를 열면 더 주는 시간 (분)');
update public.xp_rules set note = '자유게시판 댓글 + 문서 댓글 (합쳐서 하루 상한)' where key = 'comment';
update public.xp_rules set note = '댓글 경험치 하루 상한 (게시판 댓글 + 문서 댓글 합계)' where key = 'comment_daily_cap';
update public.xp_rules set note = '댓글 최소 간격 (초, 게시판 댓글·문서 댓글 공유, 도배 방지)' where key = 'comment_interval';

alter table public.posts add column edit_grace_until timestamptz;
alter table public.post_comments add column edit_grace_until timestamptz;

-- ---------------------------------------------------------------------
-- 1. 문서 댓글
-- ---------------------------------------------------------------------
create table public.doc_comments (
  id               bigint generated always as identity primary key,
  counter_id       bigint not null references public.counters (id) on delete cascade,
  author_id        uuid not null references public.profiles (id) on delete cascade,
  body             text not null check (char_length(btrim(body)) between 1 and 1000),
  status           text not null default 'visible' check (status in ('visible', 'hidden')),
  hidden_note      text,
  hidden_at        timestamptz,
  hidden_by        uuid references public.profiles (id) on delete set null,
  edited_at        timestamptz,
  edit_grace_until timestamptz,
  created_at       timestamptz not null default now()
);
create index doc_comments_counter_idx on public.doc_comments (counter_id, created_at);
create index doc_comments_author_idx on public.doc_comments (author_id, created_at);

revoke all on public.doc_comments from anon, authenticated;
grant select on public.doc_comments to anon, authenticated;
alter table public.doc_comments enable row level security;
create policy "doc_comments: 읽기 (숨긴 것은 운영자만)" on public.doc_comments
  for select using (
    public.is_admin()
    or (status = 'visible' and exists (select 1 from public.counters c where c.id = counter_id and c.status = 'approved'))
  );

-- 신고 대상에 문서 댓글 추가
alter table public.reports add column doc_comment_id bigint references public.doc_comments (id) on delete cascade;
alter table public.reports drop constraint reports_check;
alter table public.reports add constraint reports_one_target check (num_nonnulls(post_id, comment_id, doc_comment_id) = 1);
create unique index reports_once_doc_comment on public.reports (reporter_id, doc_comment_id) where doc_comment_id is not null;

-- 알림: 문서로 연결
alter table public.notifications add column counter_id bigint references public.counters (id) on delete cascade;
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check check (kind in (
    'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected',
    'build_approved', 'build_rejected', 'build_hidden', 'build_restored',
    'level_up', 'level_down', 'title_earned', 'title_revoked',
    'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
    'doc_comment', 'doc_comment_hidden', 'doc_comment_restored'));

-- 완전 삭제 기록에 댓글 수 (delete_counter가 기록을 남긴 직후 카운터를 지울 때 채운다)
alter table public.counter_deletions add column comments_count integer not null default 0;
create function public.counter_deletion_comments()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update public.counter_deletions
  set comments_count = (select count(*) from public.doc_comments where counter_id = old.id)
  where id = (select max(id) from public.counter_deletions where counter_id = old.id);
  return old;
end;
$$;
create trigger counters_deletion_comments before delete on public.counters
  for each row execute function public.counter_deletion_comments();

-- ---------------------------------------------------------------------
-- 2. 고치기 시간: 마감 = 쓴 때 + 제한 시간, 유예를 받았으면 그때까지
-- ---------------------------------------------------------------------
create function public.edit_deadline(p_kind text, p_created timestamptz, p_grace timestamptz)
returns timestamptz language sql stable security definer set search_path = ''
as $$
  select greatest(
    p_created + make_interval(mins => public.xp_rule(case when p_kind = 'post' then 'post_edit_minutes' else 'comment_edit_minutes' end)),
    coalesce(p_grace, '-infinity'::timestamptz));
$$;

create function public.require_edit_window(p_kind text, p_created timestamptz, p_grace timestamptz)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if now() > public.edit_deadline(p_kind, p_created, p_grace) then
    raise exception '고칠 수 있는 시간이 지났어요. 지우고 다시 쓸 수는 있어요.' using errcode = '23514';
  end if;
end;
$$;

-- 고치는 화면을 열 때: 내 것 + 고칠 수 있는 상태인지 확인하고, 마감 전이면 유예를 준다.
-- p_kind: 'post' | 'comment' | 'doc_comment'. 돌려주는 값: 저장할 수 있는 마지막 시각
create function public.begin_edit(p_kind text, p_id bigint)
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
    select c.author_id, c.created_at, c.edit_grace_until, c.status = 'visible' and p.status = 'visible'
      into author, created, grace, ok
    from public.post_comments c join public.posts p on p.id = c.post_id where c.id = p_id for update of c;
  elsif p_kind = 'doc_comment' then
    select d.author_id, d.created_at, d.edit_grace_until, d.status = 'visible' and k.status = 'approved'
      into author, created, grace, ok
    from public.doc_comments d join public.counters k on k.id = d.counter_id where d.id = p_id for update of d;
  else
    raise exception '알 수 없는 종류예요.' using errcode = '22023';
  end if;
  if author is null then
    raise exception '찾지 못했어요.' using errcode = 'P0002';
  end if;
  if author <> me then
    raise exception '내 글·댓글만 고칠 수 있어요.' using errcode = '42501';
  end if;
  if not ok then
    raise exception '숨기거나 삭제된 글·댓글은 고칠 수 없어요.' using errcode = '23514';
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

-- 015의 edit_post / edit_comment에 시간 검사를 더한다
create or replace function public.edit_post(p_id bigint, p_title text, p_body text)
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
  perform public.require_edit_window('post', p.created_at, p.edit_grace_until);
  if t = p.title and b = p.body then
    return;  -- 바뀐 게 없으면 "수정됨"도 붙이지 않는다
  end if;
  update public.posts set title = t, body = b, edited_at = now() where id = p.id;
end;
$$;

create or replace function public.edit_comment(p_id bigint, p_body text)
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
  perform public.require_edit_window('comment', c.created_at, c.edit_grace_until);
  if b = c.body then
    return;
  end if;
  update public.post_comments set body = b, edited_at = now() where id = c.id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 문서 댓글 함수
-- ---------------------------------------------------------------------
-- 돌려주는 값: 새 댓글 id. 카운터 첫 제안자에게 알림 (안 읽은 알림이 있으면 합친다)
create function public.create_doc_comment(p_counter bigint, p_body text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b text := public.board_text(p_body, '댓글', 1000);
  k public.counters%rowtype;
  owner uuid;
  new_id bigint;
  n public.notifications%rowtype;
  cnt integer;
begin
  select * into k from public.counters where id = p_counter;
  if not found or k.status <> 'approved' then
    raise exception '댓글을 달 수 없는 문서예요.' using errcode = 'P0002';
  end if;
  perform public.board_throttle(me, 'comment');
  insert into public.doc_comments (counter_id, author_id, body) values (k.id, me, b) returning id into new_id;

  select proposer_id into owner from public.edit_proposals where id = public.origin_proposal_id(k.id);
  if owner is not null and owner <> me then
    select * into n from public.notifications
    where user_id = owner and kind = 'doc_comment' and counter_id = k.id and read_at is null
    order by created_at limit 1 for update;
    if found then
      select count(*) into cnt from public.doc_comments
      where counter_id = k.id and author_id <> owner and status = 'visible' and created_at >= n.created_at;
      update public.notifications set message = format('내가 제안한 카운터 문서에 새 댓글 %s개가 달렸어요.', greatest(cnt, 2))
      where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, counter_id)
      values (owner, 'doc_comment', '내가 제안한 카운터 문서에 새 댓글이 달렸어요.', k.id);
    end if;
  end if;
  return new_id;
end;
$$;

create function public.doc_comment_for_update(p_id bigint)
returns public.doc_comments language plpgsql security definer set search_path = ''
as $$
declare
  d public.doc_comments%rowtype;
begin
  select * into d from public.doc_comments where id = p_id for update;
  if not found then
    raise exception '댓글을 찾지 못했어요.' using errcode = 'P0002';
  end if;
  return d;
end;
$$;

create function public.edit_doc_comment(p_id bigint, p_body text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b text := public.board_text(p_body, '댓글', 1000);
  d public.doc_comments%rowtype := public.doc_comment_for_update(p_id);
begin
  if d.author_id <> me then
    raise exception '내 댓글만 고칠 수 있어요.' using errcode = '42501';
  end if;
  if d.status <> 'visible' or exists (select 1 from public.counters where id = d.counter_id and status <> 'approved') then
    raise exception '숨긴 댓글·문서는 고칠 수 없어요.' using errcode = '23514';
  end if;
  perform public.require_edit_window('doc_comment', d.created_at, d.edit_grace_until);
  if b = d.body then
    return;
  end if;
  update public.doc_comments set body = b, edited_at = now() where id = d.id;
end;
$$;

create function public.delete_my_doc_comment(p_id bigint)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  d public.doc_comments%rowtype := public.doc_comment_for_update(p_id);
begin
  if me is null or d.author_id <> me then
    raise exception '내 댓글만 지울 수 있어요.' using errcode = '42501';
  end if;
  delete from public.doc_comments where id = d.id;
end;
$$;

create function public.report_doc_comment(p_id bigint, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  dt text := public.board_report_check(p_reason, p_detail);
  d public.doc_comments%rowtype;
begin
  select * into d from public.doc_comments where id = p_id;
  if not found or d.status <> 'visible'
     or exists (select 1 from public.counters where id = d.counter_id and status <> 'approved') then
    raise exception '신고할 수 없는 댓글이에요.' using errcode = 'P0002';
  end if;
  if d.author_id = me then
    raise exception '내 댓글은 신고할 수 없어요.' using errcode = '23514';
  end if;
  insert into public.reports (reporter_id, doc_comment_id, reason, detail) values (me, d.id, p_reason, dt);
exception when unique_violation then
  raise exception '이미 신고한 댓글이에요.' using errcode = '23505';
end;
$$;

create function public.hide_doc_comment(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  d public.doc_comments%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '숨기는 이유');
  d := public.doc_comment_for_update(p_id);
  if d.status = 'hidden' then
    raise exception '이미 숨긴 댓글이에요.' using errcode = '23514';
  end if;
  update public.doc_comments set status = 'hidden', hidden_note = note, hidden_at = now(), hidden_by = (select auth.uid())
  where id = d.id;
  update public.reports set status = 'resolved', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
  where doc_comment_id = d.id and status = 'open';
  if d.author_id <> (select auth.uid()) then
    insert into public.notifications (user_id, kind, message, counter_id)
    values (d.author_id, 'doc_comment_hidden', format('문서에 쓴 내 댓글을 운영자가 숨겼어요. 메모: %s', note), d.counter_id);
  end if;
end;
$$;

create function public.restore_doc_comment(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text;
  d public.doc_comments%rowtype;
begin
  perform public.require_operator();
  note := public.require_note(p_note, '다시 공개 메모');
  d := public.doc_comment_for_update(p_id);
  if d.status <> 'hidden' then
    raise exception '숨긴 댓글이 아니에요.' using errcode = '23514';
  end if;
  update public.doc_comments set status = 'visible', hidden_note = null, hidden_at = null, hidden_by = null where id = d.id;
  if d.author_id <> (select auth.uid()) then
    insert into public.notifications (user_id, kind, message, counter_id)
    values (d.author_id, 'doc_comment_restored', format('숨겨졌던 문서 댓글이 다시 공개됐어요. 메모: %s', note), d.counter_id);
  end if;
end;
$$;

-- 신고 기각: 문서 댓글도 (015의 dismiss_reports는 글·댓글 전용 → 같은 이름으로 대상 하나 더)
drop function public.dismiss_reports(bigint, bigint, text);
create function public.dismiss_reports(p_post bigint, p_comment bigint, p_note text default null, p_doc_comment bigint default null)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  perform public.require_operator();
  if num_nonnulls(p_post, p_comment, p_doc_comment) <> 1 then
    raise exception '글이나 댓글 하나를 골라 주세요.' using errcode = '22023';
  end if;
  update public.reports
  set status = 'dismissed', handled_by = (select auth.uid()), handled_at = now(),
      handled_note = nullif(btrim(coalesce(p_note, '')), '')
  where status = 'open' and (post_id = p_post or comment_id = p_comment or doc_comment_id = p_doc_comment);
  get diagnostics n = row_count;
  if n = 0 then
    raise exception '처리할 신고가 없어요. (이미 처리됐을 수 있어요)' using errcode = 'P0002';
  end if;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 경험치: 문서 댓글 (+1, 하루 상한은 게시판 댓글과 합쳐서), 탑신병자
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
  -- 댓글: 게시판 댓글 + 문서 댓글을 합쳐 그날 먼저 쓴 순서대로 상한까지
  --   (글이 숨겨지거나 삭제된 글로 남아도, 카운터가 숨겨져도 보이는 댓글이면 그대로. 카운터를 완전히 지우면 회수)
  --   문서 댓글의 ref_id = '<카운터 id>:<댓글 id>' (회수 이유를 가리기 위해)
  select x.source_key, x.kind, x.ref_id, public.xp_rule('comment'), x.created_at, x.target_champion, x.counter_champion
  from (
    select y.*, row_number() over (
      partition by (y.created_at at time zone 'Asia/Seoul')::date order by y.created_at, y.kind, y.id) as rn
    from (
      select 'comment:' || c.id as source_key, 'comment' as kind, c.id::text as ref_id, c.id, c.created_at,
             null::text as target_champion, null::text as counter_champion
      from public.post_comments c
      where c.author_id = p_user and c.status = 'visible'
      union all
      select 'doc_comment:' || d.id, 'doc_comment', d.counter_id || ':' || d.id, d.id, d.created_at, k.target_champion, k.counter_champion
      from public.doc_comments d join public.counters k on k.id = d.counter_id
      where d.author_id = p_user and d.status = 'visible'
    ) y
  ) x
  where x.rn <= public.xp_rule('comment_daily_cap') / greatest(public.xp_rule('comment'), 1);
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
  elsif p_kind = 'doc_comment' then
    if not exists (select 1 from public.counters where id = split_part(p_ref, ':', 1)::bigint) then return '카운터 삭제'; end if;
    select status into st from public.doc_comments where id = split_part(p_ref, ':', 2)::bigint;
    if not found then return '댓글 삭제'; end if;
    if st = 'hidden' then return '댓글 숨김'; end if;
    return '규칙 변경';
  end if;
  return null;
end;
$$;

-- 탑신병자용: 보이는 글·댓글·문서 댓글이 하나라도 있나 (다음에 쓸 곳이 늘어도 이 함수만 고친다)
create function public.has_visible_writing(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.posts where author_id = p_user and status = 'visible' and deleted_at is null)
      or exists (select 1 from public.post_comments where author_id = p_user and status = 'visible')
      or exists (select 1 from public.doc_comments where author_id = p_user and status = 'visible');
$$;

-- 015의 sync_rewards와 같고, 탑신병자의 "보이는 글·댓글"을 has_visible_writing()으로 바꿨다
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
  board_cnt := case when public.has_visible_writing(p_user) then 1 else 0 end;
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

-- 언제 다시 계산하나: 문서 댓글을 쓰거나 숨기거나 다시 공개하거나 지울 때 (카운터 완전 삭제의 cascade 포함)
create constraint trigger doc_comments_rewards after insert or update of status or delete on public.doc_comments
  deferrable initially deferred for each row execute function public.rewards_on_post();

-- ---------------------------------------------------------------------
-- 5. 함수 권한
-- ---------------------------------------------------------------------
revoke execute on function public.counter_deletion_comments() from public, anon, authenticated;
revoke execute on function public.edit_deadline(text, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.require_edit_window(text, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.doc_comment_for_update(bigint) from public, anon, authenticated;
revoke execute on function public.has_visible_writing(uuid) from public, anon, authenticated;

revoke execute on function public.begin_edit(text, bigint) from public, anon;
revoke execute on function public.create_doc_comment(bigint, text) from public, anon;
revoke execute on function public.edit_doc_comment(bigint, text) from public, anon;
revoke execute on function public.delete_my_doc_comment(bigint) from public, anon;
revoke execute on function public.report_doc_comment(bigint, text, text) from public, anon;
revoke execute on function public.hide_doc_comment(bigint, text) from public, anon;
revoke execute on function public.restore_doc_comment(bigint, text) from public, anon;
revoke execute on function public.dismiss_reports(bigint, bigint, text, bigint) from public, anon;
grant execute on function public.begin_edit(text, bigint) to authenticated;
grant execute on function public.create_doc_comment(bigint, text) to authenticated;
grant execute on function public.edit_doc_comment(bigint, text) to authenticated;
grant execute on function public.delete_my_doc_comment(bigint) to authenticated;
grant execute on function public.report_doc_comment(bigint, text, text) to authenticated;
grant execute on function public.hide_doc_comment(bigint, text) to authenticated;
grant execute on function public.restore_doc_comment(bigint, text) to authenticated;
grant execute on function public.dismiss_reports(bigint, bigint, text, bigint) to authenticated;

commit;
