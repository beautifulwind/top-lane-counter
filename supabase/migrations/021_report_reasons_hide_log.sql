-- =====================================================================
-- 021: 노가리방·댓글 운영 규칙 보강
-- 1. 신고 사유에 'hate'(혐오·비하) 추가. 화면 이름: abuse 욕설·인신공격 / hate 혐오·비하 / privacy 신상 공개·개인정보 / spam / other
-- 2. 숨김 기록 hide_log: 글·댓글·문서 댓글이 숨겨질 때마다 한 줄 (다시 공개하면 unhidden_at).
--    작성자가 숨겨진 글을 지워도 기록은 남는다 (반복 위반 판단용). 탈퇴하면 같이 지워진다.
-- 3. 운영자 함수 hide_counts(작성자들): 최근 N일(xp_rules.hide_count_days, 90) 숨김 횟수 — 신고 목록에 표시
-- 반복 위반자 제재(글쓰기 정지)는 아직 만들지 않는다 (SPEC 6-11).
-- 020_guest.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 신고 사유
-- ---------------------------------------------------------------------
alter table public.reports drop constraint reports_reason_check;
alter table public.reports add constraint reports_reason_check
  check (reason in ('abuse', 'hate', 'spam', 'privacy', 'other'));

create or replace function public.board_report_check(p_reason text, p_detail text)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  d text := nullif(btrim(coalesce(p_detail, '')), '');
begin
  if p_reason is null or p_reason not in ('abuse', 'hate', 'spam', 'privacy', 'other') then
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
-- 2. 숨김 기록
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('hide_count_days', 90, '운영자 신고 목록에 보이는 "최근 N일 숨김 횟수"의 N');

create table public.hide_log (
  id          bigint generated always as identity primary key,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  kind        text not null check (kind in ('post', 'comment', 'doc_comment')),
  target_id   bigint not null,          -- 대상이 지워져도 기록은 남김 (연결 안 함)
  hidden_at   timestamptz not null default now(),
  unhidden_at timestamptz               -- 운영자가 다시 공개하면 (잘못 숨긴 것 → 횟수에서 뺌)
);
comment on table public.hide_log is '글·댓글·문서 댓글이 숨겨진 기록 (021). 트리거만 쓰고 운영자 함수 hide_counts로만 읽는다';
create index hide_log_author_idx on public.hide_log (author_id, hidden_at);
create index hide_log_target_idx on public.hide_log (kind, target_id) where unhidden_at is null;
alter table public.hide_log enable row level security;
revoke all on public.hide_log from public, anon, authenticated;

create function public.log_hide()
returns trigger language plpgsql security definer set search_path = ''
as $$
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
$$;
revoke execute on function public.log_hide() from public, anon, authenticated;

create trigger posts_hide_log after update of status on public.posts
  for each row execute function public.log_hide();
create trigger post_comments_hide_log after update of status on public.post_comments
  for each row execute function public.log_hide();
create trigger doc_comments_hide_log after update of status on public.doc_comments
  for each row execute function public.log_hide();

-- 지금 숨겨져 있는 것은 숨긴 때 그대로 채워 둔다
insert into public.hide_log (author_id, kind, target_id, hidden_at)
select author_id, 'post', id, coalesce(hidden_at, now()) from public.posts where status = 'hidden' and author_id is not null
union all
select author_id, 'comment', id, coalesce(hidden_at, now()) from public.post_comments where status = 'hidden' and author_id is not null
union all
select author_id, 'doc_comment', id, coalesce(hidden_at, now()) from public.doc_comments where status = 'hidden' and author_id is not null;

-- ---------------------------------------------------------------------
-- 3. 운영자: 작성자별 최근 숨김 횟수 → {"days": 90, "counts": {"<uuid>": 2, ...}} (0회인 사람도 넣음)
-- ---------------------------------------------------------------------
create function public.hide_counts(p_users uuid[])
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  days int := coalesce((select value from public.xp_rules where key = 'hide_count_days'), 90);
begin
  if not public.is_admin() then
    raise exception '운영자만 할 수 있어요.' using errcode = '42501';
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
revoke execute on function public.hide_counts(uuid[]) from public, anon;
grant execute on function public.hide_counts(uuid[]) to authenticated;

commit;
