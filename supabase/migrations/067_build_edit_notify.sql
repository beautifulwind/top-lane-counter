-- =====================================================================
-- 067: 빌드 수정 알림 (2026-11-22, SPEC 6-84) - 새 알림 종류 build_edited, 새 표 1개, 새 트리거 1개, 알림 설정 칸 1개.
--
-- 1. 언제: 수정 기록 표(build_revisions)에 'edit'(edit_build) 또는 'revert'(revert_build → revert_build_unchecked) 줄이 생긴 직후
--    트리거 build_revisions_notify 하나가 잡는다. 새 수정 경로가 생겨도 수정 기록을 남기면 빠지지 않는다. ('create'·'migrate'는 알리지 않음)
--    - 알림 만들기를 begin … exception 블록(서브 트랜잭션) 안에서 한다 → 알림이 실패해도 경고 로그만 남고 수정 저장은 그대로 성공.
--    - edit_build·revert_build_unchecked 등 기존 함수는 하나도 고치지 않는다.
-- 2. 누구에게 (한 사람에게 한 번만, 수정한 본인은 빼고, 탈퇴한 사람은 프로필이 없으므로 저절로 빠짐):
--    ① 운영자(admin) 전원 - 감독관 제외. 운영자 모드와 관계없이 만들고 보인다(운영자 모드를 꺼도 숨기지 않음 - 설정에서 끌 수 있음).
--    ② 그 빌드의 원 작성자(builds.author_id)  ③ 그 빌드에 이전에 기여한 사람(build_editors) - 최근에 고친 순으로 50명까지.
--    - 한 사람이 여럿에 해당하면 작성자 > 기여자 > 운영자 순서의 문장 하나로.
--    - 차단(061): 받는 사람과 수정한 사람 사이에 어느 쪽이든 차단이 있으면 작성자·기여자 알림은 만들지 않는다(운영자 알림은 차단과 무관).
--    - 알림 설정 push_settings.build_edits(새 칸, 기본 켜짐)를 끈 사람에게는 만들지 않는다(앱 안 알림·휴대폰 알림 모두).
-- 3. 문장 (상대법 이름은 DB에 한글 챔피언 이름이 없어 화면이 "빌드" 뒤에 「(가렌 vs 다리우스)」를 끼워 넣는다):
--    운영자: 「○○님이 △△님의 빌드를 수정했습니다.」(자기 빌드면 「○○님이 자기 빌드를 …」, 작성자 탈퇴면 「… 탈퇴한 사용자의 빌드를 …」)
--    작성자: 「○○님이 회원님의 빌드를 수정했습니다.」  기여자: 「○○님이 회원님이 참여한 빌드를 수정했습니다.」
--    되돌리기는 「…를 되돌렸습니다.」. 수정한 사람이 탈퇴하면 「탈퇴한 사용자가 …」.
-- 4. 10분 묶기: 같은 사람이 같은 빌드를 10분 안에 또 고치면, 받는 사람마다 아직 안 읽은 그 알림을 새로 만들지 않고
--    「… (N번 수정)」으로 고친다(시각도 최근으로). 휴대폰 알림은 새 줄이 생길 때만 가므로 처음 한 번만 울린다.
-- 5. 탈퇴: 새 표 build_edit_notices(알림 ↔ 수정한 사람·작성자 id)가 문장을 다시 만든다. 수정한 사람·작성자가 탈퇴하면(프로필 삭제 →
--    on delete set null) 그 알림 문장의 닉네임이 「탈퇴한 사용자」로 바뀐다. 받는 사람이 탈퇴하면 알림과 함께 지워진다.
-- 6. 푸시: push_group('build_edited') = 새 묶음 'build_edits', push_wanted가 push_settings.build_edits(기본 true)를 본다.
--    Edge Function(web-push)은 바꾸지 않는다 → 휴대폰 알림은 제목 「탑신병자」, 내용은 위 문장, 누르면 알림 목록(/notifications).
-- 7. 옛 앱(1.1 이하): 모르는 종류는 알림 목록에 문장만 보여 준다(누르는 곳 없음). 옛 앱이 알림 설정을 저장해도 새 칸은 건드리지 않는다.
--
-- 실행 전 supabase/scripts/check_build_edit_notify_before.sql, 실행 뒤 check_build_edit_notify_after.sql.
-- 066까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 그 뒤에 새 화면을 배포(푸시)한다.
-- (먼저 배포해도 화면은 죽지 않는다: 설정 저장은 새 칸 없이 다시 시도하고, 새 종류 알림은 아직 생기지 않는다.)
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 066 상태로 돌아간다.
--    067이 만든 build_edited 알림과 설정 칸 build_edits(끈 기록 포함)도 지워진다. 기존 빌드·투표·수정 기록은 067이 바꾸지 않았다.
--     begin;
--     drop trigger if exists build_revisions_notify on public.build_revisions;
--     drop function if exists public.build_revisions_notify();
--     drop function if exists public.notify_build_edit(bigint, uuid, text);
--     drop trigger if exists build_edit_notices_rerender on public.build_edit_notices;
--     drop function if exists public.build_edit_notices_rerender();
--     delete from public.notifications where kind = 'build_edited';  -- 067이 만든 알림 (아래 종류 목록에서 빠지므로 먼저 지움)
--     drop table if exists public.build_edit_notices;
--     drop function if exists public.build_edit_message(text, uuid, uuid, integer, text);
--     create or replace function public.push_group(p_kind text)
--     returns text language sql immutable set search_path = ''
--     as $$
--       select case
--         when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
--                         'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
--         when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--                         'revision_request', 'counter_restored', 'build_restored',
--                         'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--                         'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
--                         'profile_photo_removed') then 'my_results'  -- 062: 링크 삭제와 같은 묶음
--         when p_kind in ('followed_build_created') then 'follow_builds'
--         when p_kind in ('notice_posted') then 'notice'
--         when p_kind in ('new_followers') then 'new_followers'
--       end;
--     $$;
--     create or replace function public.push_wanted(p_user uuid, p_kind text)
--     returns boolean language sql stable security definer set search_path = ''
--     as $$
--       select case public.push_group(p_kind)
--         when 'staff_new' then
--           exists (select 1 from public.profiles p
--                    where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
--           and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
--         when 'my_results' then
--           coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
--         when 'follow_builds' then
--           coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
--         when 'notice' then
--           coalesce((select s.notice from public.push_settings s where s.user_id = p_user), true)
--         when 'new_followers' then
--           coalesce((select s.new_followers from public.push_settings s where s.user_id = p_user), false)  -- 설정 줄이 없으면 꺼짐
--         else false
--       end
--       and exists (select 1 from public.push_subscriptions where user_id = p_user);
--     $$;
--     alter table public.notifications drop constraint notifications_kind_check;
--     alter table public.notifications add constraint notifications_kind_check check (kind in (
--       'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved',
--       'build_rejected', 'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
--       'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment',
--       'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked', 'inquiry_answered',
--       'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored', 'matchup_created',
--       'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created', 'error_reported',
--       'error_report_handled', 'report_received', 'influencer_applied', 'influencer_received', 'influencer_expiring',
--       'influencer_approved', 'influencer_rejected', 'influencer_expired', 'influencer_revoked',
--       'nickname_reset_soon', 'nickname_reset', 'link_removed', 'followed_build_created', 'notice_posted',
--       'new_followers', 'comment_reply', 'profile_photo_removed'));
--     alter table public.push_settings drop column if exists build_edits;  -- 칸 권한(grant update)도 함께 없어짐
--     commit;
-- =====================================================================

begin;

-- 알림 설정: 빌드 수정 알림 (기본 켜짐)
alter table public.push_settings add column build_edits boolean not null default true;
grant update (build_edits) on public.push_settings to authenticated;  -- 본인 줄만 (RLS 그대로, 050·051·052와 같은 방식)

-- 새 알림 종류
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in (
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved',
  'build_rejected', 'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment',
  'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked', 'inquiry_answered',
  'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored', 'matchup_created',
  'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created', 'error_reported',
  'error_report_handled', 'report_received', 'influencer_applied', 'influencer_received', 'influencer_expiring',
  'influencer_approved', 'influencer_rejected', 'influencer_expired', 'influencer_revoked',
  'nickname_reset_soon', 'nickname_reset', 'link_removed', 'followed_build_created', 'notice_posted',
  'new_followers', 'comment_reply', 'profile_photo_removed',
  'build_edited'));

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored',
                    'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
                    'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
                    'profile_photo_removed') then 'my_results'  -- 062: 링크 삭제와 같은 묶음
    when p_kind in ('followed_build_created') then 'follow_builds'
    when p_kind in ('notice_posted') then 'notice'
    when p_kind in ('new_followers') then 'new_followers'
    when p_kind in ('build_edited') then 'build_edits'  -- 067 빌드 수정 알림
  end;
$$;

create or replace function public.push_wanted(p_user uuid, p_kind text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case public.push_group(p_kind)
    when 'staff_new' then
      exists (select 1 from public.profiles p
               where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
      and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
    when 'my_results' then
      coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
    when 'follow_builds' then
      coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
    when 'notice' then
      coalesce((select s.notice from public.push_settings s where s.user_id = p_user), true)
    when 'new_followers' then
      coalesce((select s.new_followers from public.push_settings s where s.user_id = p_user), false)  -- 설정 줄이 없으면 꺼짐
    when 'build_edits' then
      coalesce((select s.build_edits from public.push_settings s where s.user_id = p_user), true)  -- 067
    else false
  end
  and exists (select 1 from public.push_subscriptions where user_id = p_user);
$$;

-- 알림 ↔ 수정한 사람·작성자 (문장을 다시 만들기 위한 짝. 화면·사용자는 읽지 않는다)
create table public.build_edit_notices (
  notification_id bigint primary key references public.notifications (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,      -- 받는 사람
  build_id bigint not null references public.builds (id) on delete cascade,
  editor_id uuid references public.profiles (id) on delete set null,            -- 수정한 사람 (탈퇴하면 null)
  author_id uuid references public.profiles (id) on delete set null,            -- 빌드 원 작성자 (탈퇴하면 null)
  audience text not null check (audience in ('staff', 'author', 'contributor')),
  edits integer not null default 1 check (edits >= 1),
  last_kind text not null check (last_kind in ('edit', 'revert')),
  last_at timestamptz not null default now()
);
comment on table public.build_edit_notices is '067 빌드 수정 알림의 짝(수정한 사람·작성자 id). 탈퇴하면 알림 문장의 닉네임을 「탈퇴한 사용자」로 바꾸고, 10분 묶기에 쓴다';
create index build_edit_notices_bundle_idx on public.build_edit_notices (user_id, build_id, editor_id, last_at desc);
create index build_edit_notices_editor_idx on public.build_edit_notices (editor_id);
create index build_edit_notices_author_idx on public.build_edit_notices (author_id);
create index build_edit_notices_build_idx on public.build_edit_notices (build_id);
alter table public.build_edit_notices enable row level security;  -- 정책 없음 = 아무도 직접 못 읽음
revoke all on public.build_edit_notices from public, anon, authenticated;

-- 문장 만들기 (닉네임은 지금 프로필에서, 없으면 「탈퇴한 사용자」)
create function public.build_edit_message(p_audience text, p_editor uuid, p_author uuid, p_edits integer, p_kind text)
returns text language plpgsql stable set search_path = ''
as $$
declare
  e text := (select nickname from public.profiles where id = p_editor);
  a text := (select nickname from public.profiles where id = p_author);
  who text := case when p_editor is null or e is null then '탈퇴한 사용자가' else e || '님이' end;
  verb text := case when p_kind = 'revert' then '되돌렸습니다' else '수정했습니다' end;
  whose text;
begin
  whose := case p_audience
    when 'author' then '회원님의 빌드를'
    when 'contributor' then '회원님이 참여한 빌드를'
    else case
      when p_author is null or a is null then '탈퇴한 사용자의 빌드를'
      when p_author = p_editor then '자기 빌드를'
      else a || '님의 빌드를'
    end
  end;
  return who || ' ' || whose || ' ' || verb || '.' || case when p_edits > 1 then ' (' || p_edits || '번 수정)' else '' end;
end;
$$;

-- 알림 만들기 (수정 한 번). 받는 사람마다: 10분 안 같은 사람의 안 읽은 알림이 있으면 고치고, 없으면 새로
create function public.notify_build_edit(p_build bigint, p_editor uuid, p_kind text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  b public.builds%rowtype;
  r record;
  old_id bigint;
  x public.build_edit_notices%rowtype;
  nid bigint;
begin
  if p_editor is null then return; end if;
  select * into b from public.builds where id = p_build;
  if not found then return; end if;
  for r in
    with cand as (
      select b.author_id as uid, 1 as pri, 'author'::text as audience where b.author_id is not null
      union all
      select e.user_id, 2, 'contributor' from (
        select user_id from public.build_editors where build_id = p_build and user_id <> p_editor
         order by last_at desc nulls last limit 50) e
      union all
      select p.id, 3, 'staff' from public.profiles p where p.role = 'admin'
    ), one as (
      select distinct on (uid) uid, audience from cand where uid <> p_editor order by uid, pri
    )
    select o.uid, o.audience from one o
      join public.profiles p on p.id = o.uid                                        -- 탈퇴한 사람은 빠짐
     where coalesce((select s.build_edits from public.push_settings s where s.user_id = o.uid), true)
       and (o.audience = 'staff' or not exists (                                    -- 061 차단: 작성자·기여자만
             select 1 from public.user_blocks k
              where (k.blocker_id = o.uid and k.blocked_id = p_editor) or (k.blocker_id = p_editor and k.blocked_id = o.uid)))
  loop
    select x2.notification_id into old_id
      from public.build_edit_notices x2 join public.notifications n on n.id = x2.notification_id
     where x2.user_id = r.uid and x2.build_id = p_build and x2.editor_id = p_editor
       and n.read_at is null and x2.last_at > now() - interval '10 minutes'
     order by x2.last_at desc limit 1
     for update of x2;
    if old_id is not null then
      update public.build_edit_notices
         set edits = edits + 1, last_kind = p_kind, last_at = now(), audience = r.audience
       where notification_id = old_id returning * into x;
      update public.notifications
         set message = public.build_edit_message(x.audience, x.editor_id, x.author_id, x.edits, x.last_kind), created_at = now()
       where id = old_id;
    else
      insert into public.notifications (user_id, kind, message, build_id, counter_id)
        values (r.uid, 'build_edited', public.build_edit_message(r.audience, p_editor, b.author_id, 1, p_kind), p_build, b.counter_id)
        returning id into nid;
      insert into public.build_edit_notices (notification_id, user_id, build_id, editor_id, author_id, audience, last_kind)
        values (nid, r.uid, p_build, p_editor, b.author_id, r.audience, p_kind);
    end if;
  end loop;
end;
$$;

-- 수정 기록 트리거: 알림이 실패해도 수정은 그대로 (서브 트랜잭션)
create function public.build_revisions_notify()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  begin
    perform public.notify_build_edit(new.build_id, new.editor_id, new.kind);
  exception when others then
    raise warning '빌드 수정 알림을 만들지 못했습니다 (빌드 %, 수정 기록 %): %', new.build_id, new.id, sqlerrm;
  end;
  return null;
end;
$$;
create trigger build_revisions_notify after insert on public.build_revisions
  for each row when (new.kind in ('edit', 'revert')) execute function public.build_revisions_notify();

-- 수정한 사람·작성자가 탈퇴하면(on delete set null) 그 알림 문장을 다시 만든다 → 닉네임이 「탈퇴한 사용자」로
create function public.build_edit_notices_rerender()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update public.notifications
     set message = public.build_edit_message(new.audience, new.editor_id, new.author_id, new.edits, new.last_kind)
   where id = new.notification_id;
  return null;
end;
$$;
create trigger build_edit_notices_rerender after update of editor_id, author_id on public.build_edit_notices
  for each row when (new.editor_id is distinct from old.editor_id or new.author_id is distinct from old.author_id)
  execute function public.build_edit_notices_rerender();

revoke execute on function public.build_edit_message(text, uuid, uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.notify_build_edit(bigint, uuid, text) from public, anon, authenticated;
revoke execute on function public.build_revisions_notify() from public, anon, authenticated;
revoke execute on function public.build_edit_notices_rerender() from public, anon, authenticated;

commit;
