-- =====================================================================
-- 042: 회원 관리 통합·회원 정보 페이지용 조회 + 자유게시판 새 글 알림 (2026-11-11, SPEC 6-29)
--
-- 1. 회원 목록 (운영자 전용): admin_member_list(검색어, 역할, 쪽, 쪽 크기)
--    최근 가입 순(가입일 내림차순, 같으면 id 내림차순), 닉네임 부분 일치(대소문자 무시, 비우면 전체), 역할 거르기(user·moderator·admin),
--    쪽 크기 최대 50. 비회원(손님)도 목록에 나오고 is_guest로 구분. 이메일·로그인 ID는 읽지도 돌려주지도 않는다.
--    가입자 수는 있던 admin_member_stats()(036)를 그대로 쓴다.
-- 2. 회원 정보 (운영자 전용): admin_member_detail(회원, 개수)
--    - 있던 admin_member_info(036·040)를 그대로 불러 쓰고, 경험치(xp)와 상대법 수(matchups)만 더한다.
--    - 쓴 글·댓글 목록(지운 것은 빼고, 지운 글 밑의 댓글도 뺀다), 고친 빌드 목록(build_editors),
--      그 회원에 대한 처리 이력(moderation_log: 회원 자신·쓴 글·댓글·문서 댓글·제안이 대상인 줄. 숨김·삭제·재검토 등)
--    - 처리자가 탈퇴했으면 이름을 "탈퇴한 이용자"로 바꿔 돌려준다 (처리 기록에 남은 닉네임 사본을 내보내지 않는다).
--    - 지운 글·댓글은 여기에 넣지 않는다 → 있던 admin_deleted_writings(040, 운영자 전용)를 그대로 쓴다.
--      감독관·일반 회원·운영자 모드를 끈 운영자는 DB가 거부한다 (require_operator).
--    - 두 함수 모두 _unchecked(안쪽, 아무도 직접 못 부름) + require_operator를 먼저 하는 바깥 함수 (013과 같은 방식)
-- 3. 감독관 지정·해제는 있던 set_moderator(030)를 그대로 쓴다 (운영자만 — 바꾸지 않음. 검사만 더한다)
-- 4. 새 글 알림: 새 알림 종류 post_created
--    - 자유게시판 새 글이 공개로 올라오면(posts 넣기 트리거) 운영자에게 알림 한 줄. 글쓴이 본인 제외. 댓글은 알림 없음.
--    - 운영자 모드를 끄면 목록·빨간 점에서 빠지고 [모두 읽음]도 건드리지 않으며 푸시도 안 간다 (034·038과 같은 규칙에 종류만 더함)
--    - 푸시 묶음 staff_new (push_group). 푸시 설정 화면의 "운영진 알림" 하나로 함께 켜고 끈다.
--    - push_targets에 post_id를 더해 Edge Function이 /board/<글 번호>로 보낼 수 있게 한다 (있던 칸은 그대로)
--
-- 하위 호환: 있던 표·함수의 이름·인자·반환은 그대로. 새 함수와 새 알림 종류만 더한다. 지금 배포된 화면과 그대로 동작한다
--   (옛 화면은 모르는 알림 종류를 종 모양 + 문장으로 보여 주고 누르면 아무 데도 안 간다).
-- 순서: 이 파일 실행 → supabase/scripts/check_member_admin.sql로 확인 → (2단계) web-push 재배포 → 새 화면 push.
--   Edge Function은 042 전·후 어느 쪽이든 안전하다 (모르는 종류는 알림 목록으로 간다). 다만 글로 가는 링크는 둘 다 끝난 뒤에 된다.
-- 041까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 회원 목록
-- ---------------------------------------------------------------------
create function public.admin_member_list_unchecked(p_query text, p_role text, p_page integer, p_size integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  q text := btrim(coalesce(p_query, ''));
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  pat text;
  total bigint;
begin
  if char_length(q) > 20 then
    raise exception '닉네임은 20자까지입니다.' using errcode = '22023';
  end if;
  if p_role is not null and p_role not in ('user', 'moderator', 'admin') then
    raise exception '역할을 다시 골라 주세요.' using errcode = '22023';
  end if;
  pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  select count(*) into total from public.profiles p
   where (q = '' or p.nickname ilike pat escape '\') and (p_role is null or p.role = p_role);
  return jsonb_build_object(
    'total', total, 'page', pg, 'size', sz,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'nickname', x.nickname, 'role', x.role, 'level', x.level,
               'main_title', x.main_title, 'is_guest', x.is_guest, 'created_at', x.created_at)
             order by x.created_at desc, x.id desc)
      from (
        select p.id, p.nickname, p.role, p.level, p.main_title, p.is_guest, p.created_at
          from public.profiles p
         where (q = '' or p.nickname ilike pat escape '\') and (p_role is null or p.role = p_role)
         order by p.created_at desc, p.id desc
         limit sz offset (pg - 1) * sz
      ) x
    ), '[]'::jsonb));
end;
$$;

create function public.admin_member_list(p_query text default null, p_role text default null, p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_member_list_unchecked(p_query, p_role, p_page, p_size);
end;
$$;

-- ---------------------------------------------------------------------
-- 2. 회원 정보 (기본 정보 + 글·댓글 + 고친 빌드 + 처리 이력)
-- ---------------------------------------------------------------------
create function public.admin_member_detail_unchecked(p_user uuid, p_limit integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
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
$$;

create function public.admin_member_detail(p_user uuid, p_limit integer default 30)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_member_detail_unchecked(p_user, p_limit);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 새 글 알림: 알림 종류 · 읽기 규칙(운영자 모드) · 푸시 묶음
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
  'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
  'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
  'matchup_created', 'build_created',
  'post_deleted', 'comment_deleted', 'doc_comment_deleted',
  'post_created'  -- 042: 새 글 (운영자만)
]));

drop policy "notifications: 본인 읽기" on public.notifications;
create policy "notifications: 본인 읽기" on public.notifications
  for select using (
    user_id = (select auth.uid())
    and not (kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created')
             and public.operator_mode_off())
  );

do $$
declare
  f oid := 'public.mark_all_notifications_read'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
    $s$kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created')$s$,
    $s$kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created')$s$);
  if new_def = old_def then
    raise exception 'mark_all_notifications_read에서 바꿀 부분을 찾지 못했습니다. (이미 042를 실행했거나 정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored') then 'my_results'
  end;
$$;

-- Edge Function이 /board/<글 번호>로 보낼 수 있게 post_id를 함께 (있던 칸은 그대로 — 옛 Edge Function도 동작)
do $$
declare
  f oid := 'public.push_targets'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
$s$'proposal_id', n.proposal_id, 'build_id', n.build_id, 'counter_id', n.counter_id,$s$,
$s$'proposal_id', n.proposal_id, 'build_id', n.build_id, 'post_id', n.post_id, 'counter_id', n.counter_id,$s$);
  if new_def = old_def then
    raise exception 'push_targets에서 바꿀 부분을 찾지 못했습니다. (이미 042를 실행했거나 정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 새 글 → 운영자 알림 (글쓴이 본인 제외. 공개로 올라온 새 글만 — 댓글·고치기·다시 공개는 알림 없음)
--    운영자 모드를 끄면 목록에서 가려지고 푸시도 안 간다 (RLS·push_wanted가 이미 판단)
-- ---------------------------------------------------------------------
create function public.notify_admins_new_post()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.notifications (user_id, kind, message, post_id)
  select u.id, 'post_created', format('새 글이 올라왔습니다. 「%s」', public.post_snippet(new.title)), new.id
    from public.profiles u
   where u.role = 'admin' and u.id is distinct from new.author_id;
  return null;
end;
$$;
create trigger posts_notify_admins
  after insert on public.posts
  for each row when (new.status = 'visible' and new.deleted_at is null)
  execute function public.notify_admins_new_post();

-- ---------------------------------------------------------------------
-- 5. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.admin_member_list_unchecked(text, text, integer, integer) from public, anon, authenticated;
revoke execute on function public.admin_member_detail_unchecked(uuid, integer) from public, anon, authenticated;
revoke execute on function public.notify_admins_new_post() from public, anon, authenticated;
revoke execute on function public.admin_member_list(text, text, integer, integer) from public, anon;
revoke execute on function public.admin_member_detail(uuid, integer) from public, anon;
grant execute on function public.admin_member_list(text, text, integer, integer) to authenticated;  -- 운영자인지는 함수 안에서 검사
grant execute on function public.admin_member_detail(uuid, integer) to authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_member_admin.sql
