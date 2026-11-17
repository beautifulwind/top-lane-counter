-- =====================================================================
-- 059: 문서 댓글 답글(2단계) (2026-11-17, SPEC 6-60) - 추가만 하는 변경 (빌드 댓글 정리는 060에서, 새 화면 배포 뒤)
--
-- 1. doc_comments.parent_id: 최상위 문서 댓글에만 답글(댓글 -> 답글 2단계). 부모는 같은 문서의 댓글(복합 외래 키).
--    - 3단계는 함수(create_doc_comment)와 표 트리거(check_comment_depth에 문서 댓글 분기) 둘 다 막는다.
--    - 지웠거나 숨긴 댓글에는 답글을 달 수 없다. 부모가 지워져도(숨겨져도) 답글은 그대로, 화면이 부모 자리에 "삭제된 댓글입니다".
--    - create_doc_comment에 p_parent(기본 null) - 옛 화면(인자 2개)도 그대로 동작.
-- 2. 비회원: 최상위 문서 댓글은 지금처럼 단다. 답글은 못 단다 - 함수 + 표 트리거(block_guest_reply). 표에 직접 쓰기 권한은 원래 없다.
-- 3. 알림 (알림함만 - push_group 없음, Edge Function 재배포 없음, 새 알림 종류 없음)
--    - comment_reply: 내 문서 댓글에 답글 (counter_id만, post_id·build_id 빈칸). 자기 자신 제외, 안 읽은 것이 있으면 "새 답글 N개"로 합침.
--    - doc_comment(기존): 상대법을 처음 제안한 분에게 새 댓글·답글. 답글의 부모 작성자가 그분이면 답글 알림 하나만.
--      (create_doc_comment 안에 있던 알림을 notify_new_comment('doc')로 옮김 - 문장 그대로)
-- 4. 경험치: 답글도 문서 댓글 +1, 하루 상한 10을 함께 쓴다 (xp_should_have가 이미 문서 댓글 줄을 모두 세므로 함수 변경 없음, 설정 메모만).
-- 5. 삭제·신고·숨김·다시 공개·운영진 삭제·고치기: 기존 문서 댓글 함수 그대로 (답글도 같은 댓글 줄).
-- 6. 탈퇴: 다른 사람의 남은 답글이 달린 내 문서 댓글은 내용을 비운 "지움" 껍데기로 남기고 작성자는 비운다(058 커뮤니티 댓글과 같은 규칙).
--    나머지 내 문서 댓글은 지금처럼 지운다(지금까지는 작성자 외래 키 cascade가, 이제는 board_on_profile_delete가).
--    그래서 doc_comments.author_id를 빈칸 허용 + on delete set null, 본문 검사는 "지운 것이면 빈 본문 허용"으로 바꾼다.
--    1년 정리는 아직 남은 답글이 있는 부모를 건너뛴다.
--
-- 새 표·새 설정값·새 알림 종류·새 pg_cron 없음, Edge Function 재배포 없음.
-- 실행 전 supabase/scripts/check_doc_replies_before.sql, 실행 뒤 check_doc_replies_after.sql.
-- 058까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다 (옛 화면과 호환 - 화면 push는 059 실행 뒤에).
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 058 상태로 돌아간다.
--    되돌릴 수 없는 것: 문서 댓글 답글 알림은 지워진다. 문서 댓글 답글은 부모 연결만 풀린 채 보통 댓글로 남는다.
--    탈퇴로 생긴 문서 댓글 껍데기(작성자 빈 지운 댓글)는 지운다. 함수 내용은 058과 같다(낫표만 코드 번호로 적었다).
--     begin;
--     -- 1) 059에서만 생기는 기록 정리 (문서 댓글 답글 알림 = post_id·build_id가 빈 comment_reply)
--     delete from public.notifications where kind = 'comment_reply' and post_id is null and build_id is null;
--     -- 2) 트리거·함수
--     drop trigger doc_comments_no_guest_reply on public.doc_comments;
--     drop trigger doc_comments_depth on public.doc_comments;
--     drop function if exists public.block_guest_reply();
--     -- 3) 답글 칸을 빼고 작성자 칸·본문 검사를 058처럼 (껍데기는 지우고, 답글은 부모 연결이 풀린 채 보통 댓글로)
--     alter table public.doc_comments drop constraint doc_comments_parent_fkey;
--     delete from public.doc_comments where author_id is null;
--     set constraints all immediate;  -- 경험치 트리거(거래 끝에 도는 것)를 먼저 돌려야 표를 바꿀 수 있다
--     alter table public.doc_comments drop column parent_id;
--     alter table public.doc_comments drop constraint doc_comments_counter_id_id_key;
--     alter table public.doc_comments drop constraint doc_comments_author_or_deleted;
--     alter table public.doc_comments drop constraint doc_comments_author_id_fkey;
--     alter table public.doc_comments
--       add constraint doc_comments_author_id_fkey foreign key (author_id) references public.profiles (id) on delete cascade;
--     alter table public.doc_comments alter column author_id set not null;
--     alter table public.doc_comments drop constraint doc_comments_body_check;
--     alter table public.doc_comments add constraint doc_comments_body_check check (char_length(btrim(body)) between 1 and 1000);
--     -- 4) 경험치 설정 메모를 058로
--     update public.xp_rules set note = '탑신병자 커뮤니티 댓글 + 문서 댓글 (합쳐서 하루 상한)' where key = 'comment';
--     update public.xp_rules set note = '댓글 경험치 하루 상한 (탑신병자 커뮤니티 댓글 + 문서 댓글 합계)' where key = 'comment_daily_cap';
--     -- 5) 함수를 058 내용으로 (인자가 바뀐 create_doc_comment는 지우고 다시 만든다)
--     drop function public.create_doc_comment(bigint, text, bigint);
--     CREATE OR REPLACE FUNCTION public.create_doc_comment(p_counter bigint, p_body text)
--      RETURNS bigint
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       b text := public.board_text(p_body, '댓글', 1000);
--       k public.counters%rowtype;
--       owner uuid;
--       new_id bigint;
--       n public.notifications%rowtype;
--       cnt integer;
--     begin
--       select * into k from public.counters where id = p_counter;
--       if not found or k.status <> 'approved' then
--         raise exception '댓글을 달 수 없는 문서입니다.' using errcode = 'P0002';
--       end if;
--       perform public.board_throttle(me, 'comment');
--       insert into public.doc_comments (counter_id, author_id, body) values (k.id, me, b) returning id into new_id;
--
--       select proposer_id into owner from public.edit_proposals where id = public.origin_proposal_id(k.id);
--       if owner is not null and owner <> me then
--         select * into n from public.notifications
--         where user_id = owner and kind = 'doc_comment' and counter_id = k.id and read_at is null
--         order by created_at limit 1 for update;
--         if found then
--           select count(*) into cnt from public.doc_comments
--           where counter_id = k.id and author_id <> owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
--           update public.notifications set message = format('내가 제안한 상대법 문서에 새 댓글 %s개가 달렸습니다.', greatest(cnt, 2))
--           where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, counter_id)
--           values (owner, 'doc_comment', '내가 제안한 상대법 문서에 새 댓글이 달렸습니다.', k.id);
--         end if;
--       end if;
--       return new_id;
--     end;
--     $function$
--     ;
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
--       else
--         select parent_id into grand from public.build_comments where id = new.parent_id;
--         has_child := tg_op = 'UPDATE' and exists (select 1 from public.build_comments where parent_id = new.id);
--       end if;
--       if grand is not null or has_child then
--         raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
--       end if;
--       return new;
--     end;
--     $function$
--     ;
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
--       what text;      -- 낫표로 감싼 글 제목 또는 빌드 이름
--       ctr bigint;     -- 빌드 댓글이면 상대법 id (알림 링크)
--       n public.notifications%rowtype;
--       cnt integer;
--     begin
--       if p_kind = 'post' then
--         select lq || public.post_snippet(title) || rq into what from public.posts where id = p_target;
--       else
--         select counter_id into ctr from public.builds where id = p_target;
--         what := lq || public.post_snippet(public.build_label(p_target)) || rq;
--       end if;
--
--       -- 답글 -> 부모 댓글 작성자
--       if p_is_reply and p_parent_author is not null and p_parent_author is distinct from me then
--         select * into n from public.notifications
--          where user_id = p_parent_author and kind = 'comment_reply' and read_at is null
--            and ((p_kind = 'post' and post_id = p_target) or (p_kind = 'build' and build_id = p_target))
--          order by created_at limit 1 for update;
--         if found then
--           if p_kind = 'post' then
--             select count(*) into cnt from public.post_comments r join public.post_comments pc on pc.id = r.parent_id
--              where r.post_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
--                and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
--           else
--             select count(*) into cnt from public.build_comments r join public.build_comments pc on pc.id = r.parent_id
--              where r.build_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
--                and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
--           end if;
--           update public.notifications
--              set message = format('%s에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', case when p_kind = 'build' then '빌드 ' else '' end || what, greatest(cnt, 2))
--            where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, post_id, build_id, counter_id)
--           values (p_parent_author, 'comment_reply',
--                   format('%s에 쓴 내 댓글에 새 답글이 달렸습니다.', case when p_kind = 'build' then '빌드 ' else '' end || what),
--                   case when p_kind = 'post' then p_target end, case when p_kind = 'build' then p_target end, ctr);
--         end if;
--       end if;
--
--       -- 글·빌드 주인 (답글의 부모 작성자와 같은 사람이면 위 알림 하나로)
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
--     $function$
--     ;
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
--     $function$
--     ;
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
--       delete from public.doc_comments where deleted_at < before;
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
--     $function$
--     ;
--     revoke execute on function public.create_doc_comment(bigint, text) from public, anon;
--     grant execute on function public.create_doc_comment(bigint, text) to authenticated;
--     commit;
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 문서 댓글(doc_comments): 답글 칸, 탈퇴 껍데기를 위한 작성자 빈칸 허용·빈 본문 허용(지운 것만)
-- ---------------------------------------------------------------------
alter table public.doc_comments add column parent_id bigint;
comment on column public.doc_comments.parent_id is '답글이면 부모 댓글 id (059). 같은 문서의 최상위 댓글만 - 2단계까지 (트리거 check_comment_depth)';
-- 부모는 같은 문서의 댓글이어야 한다 (복합 외래 키). 부모가 정말 지워지면(1년 정리·탈퇴) 답글도 함께 - 정리와 탈퇴는 남은 답글이 있으면 부모를 남긴다
alter table public.doc_comments add constraint doc_comments_counter_id_id_key unique (counter_id, id);
alter table public.doc_comments add constraint doc_comments_parent_fkey
  foreign key (counter_id, parent_id) references public.doc_comments (counter_id, id) on delete cascade;
create index doc_comments_parent_idx on public.doc_comments (parent_id) where parent_id is not null;

-- 탈퇴: 다른 사람 답글이 달린 내 문서 댓글은 내용을 비운 "지움" 껍데기로 남고 작성자는 비운다 (탑신병자 커뮤니티 댓글과 같은 규칙)
-- (지금까지는 탈퇴하면 작성자 외래 키(cascade)가 문서 댓글을 모두 지웠다 - 이제 board_on_profile_delete가 직접 지운다)
alter table public.doc_comments alter column author_id drop not null;
alter table public.doc_comments drop constraint doc_comments_author_id_fkey;
alter table public.doc_comments
  add constraint doc_comments_author_id_fkey foreign key (author_id) references public.profiles (id) on delete set null;
alter table public.doc_comments
  add constraint doc_comments_author_or_deleted check (author_id is not null or deleted_at is not null);
alter table public.doc_comments drop constraint doc_comments_body_check;
alter table public.doc_comments
  add constraint doc_comments_body_check check (deleted_at is not null or char_length(btrim(body)) between 1 and 1000);

-- ---------------------------------------------------------------------
-- 2. 표 단계의 막기: 3단계 답글 금지(문서 댓글 분기 추가), 비회원 답글 금지 (함수를 거치지 않아도)
--    문서 댓글 최상위는 지금처럼 비회원도 단다
-- ---------------------------------------------------------------------
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
  elsif tg_table_name = 'doc_comments' then  -- 059
    select parent_id into grand from public.doc_comments where id = new.parent_id;
    has_child := tg_op = 'UPDATE' and exists (select 1 from public.doc_comments where parent_id = new.id);
  else
    select parent_id into grand from public.build_comments where id = new.parent_id;
    has_child := tg_op = 'UPDATE' and exists (select 1 from public.build_comments where parent_id = new.id);
  end if;
  if grand is not null or has_child then
    raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger doc_comments_depth before insert or update of parent_id on public.doc_comments
  for each row execute function public.check_comment_depth();

create function public.block_guest_reply()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.parent_id is not null and public.is_guest(new.author_id) then
    raise exception '비회원은 답글을 달 수 없습니다. 구글·카카오를 연결하면 달 수 있습니다.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke execute on function public.block_guest_reply() from public, anon, authenticated;
create trigger doc_comments_no_guest_reply before insert or update of parent_id on public.doc_comments
  for each row execute function public.block_guest_reply();

-- ---------------------------------------------------------------------
-- 3. 새 댓글·답글 알림: 문서('doc') 추가 (글·빌드는 058 그대로)
--   - 답글: 부모 댓글 작성자에게 comment_reply (counter_id만 - 빌드 답글 알림도 counter_id가 있어 build_id가 빈 것만 합친다)
--   - 상대법을 처음 제안한 분: doc_comment (기존 문장 그대로). 부모 작성자와 같은 사람이면 답글 알림 하나만
-- ---------------------------------------------------------------------
create or replace function public.notify_new_comment(p_kind text, p_target bigint, p_owner uuid, p_parent_author uuid, p_is_reply boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  lq text := chr(12300);  -- 낫표 여는 것 (SQL Editor에 붙여도 깨지지 않게 코드 번호로)
  rq text := chr(12301);
  what text;      -- 낫표로 감싼 글 제목 또는 빌드 이름 (문서는 없음 - 화면이 매치업 이름을 붙인다)
  ctr bigint;     -- 빌드·문서 댓글이면 상대법 id (알림 링크)
  n public.notifications%rowtype;
  cnt integer;
begin
  if p_kind = 'post' then
    select lq || public.post_snippet(title) || rq into what from public.posts where id = p_target;
  elsif p_kind = 'doc' then
    ctr := p_target;
  else
    select counter_id into ctr from public.builds where id = p_target;
    what := lq || public.post_snippet(public.build_label(p_target)) || rq;
  end if;

  -- 답글 -> 부모 댓글 작성자
  if p_is_reply and p_parent_author is not null and p_parent_author is distinct from me then
    select * into n from public.notifications
     where user_id = p_parent_author and kind = 'comment_reply' and read_at is null
       and ((p_kind = 'post' and post_id = p_target)
            or (p_kind = 'build' and build_id = p_target)
            or (p_kind = 'doc' and counter_id = p_target and post_id is null and build_id is null))
     order by created_at limit 1 for update;
    if found then
      if p_kind = 'post' then
        select count(*) into cnt from public.post_comments r join public.post_comments pc on pc.id = r.parent_id
         where r.post_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
           and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
      elsif p_kind = 'doc' then
        select count(*) into cnt from public.doc_comments r join public.doc_comments pc on pc.id = r.parent_id
         where r.counter_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
           and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
      else
        select count(*) into cnt from public.build_comments r join public.build_comments pc on pc.id = r.parent_id
         where r.build_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
           and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
      end if;
      update public.notifications
         set message = case when p_kind = 'doc' then format('상대법 문서에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', greatest(cnt, 2))
                            else format('%s에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', case when p_kind = 'build' then '빌드 ' else '' end || what, greatest(cnt, 2)) end
       where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, post_id, build_id, counter_id)
      values (p_parent_author, 'comment_reply',
              case when p_kind = 'doc' then '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.'
                   else format('%s에 쓴 내 댓글에 새 답글이 달렸습니다.', case when p_kind = 'build' then '빌드 ' else '' end || what) end,
              case when p_kind = 'post' then p_target end, case when p_kind = 'build' then p_target end, ctr);
    end if;
  end if;

  -- 글·빌드 주인, 문서는 상대법을 처음 제안한 분 (답글의 부모 작성자와 같은 사람이면 위 알림 하나로)
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
  elsif p_kind = 'doc' then  -- 059: 016의 create_doc_comment에 있던 알림을 여기로 (문장 그대로, 답글도 센다)
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
  else
    select * into n from public.notifications
     where user_id = p_owner and kind = 'build_comment' and build_id = p_target and read_at is null
     order by created_at limit 1 for update;
    if found then
      select count(*) into cnt from public.build_comments
       where build_id = p_target and author_id is distinct from p_owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
      update public.notifications set message = format('내 빌드 %s에 새 댓글 %s개가 달렸습니다.', what, greatest(cnt, 2)) where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, build_id, counter_id)
      values (p_owner, 'build_comment', format('내 빌드 %s에 새 댓글이 달렸습니다.', what), p_target, ctr);
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 문서 댓글 달기: 답글(p_parent) 추가. 최상위 댓글은 비회원도, 답글은 정식 회원만. 옛 화면(인자 2개)도 그대로 동작
-- ---------------------------------------------------------------------
drop function public.create_doc_comment(bigint, text);
create function public.create_doc_comment(p_counter bigint, p_body text, p_parent bigint default null)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b text := public.board_text(p_body, '댓글', 1000);
  k public.counters%rowtype;
  par public.doc_comments%rowtype;
  new_id bigint;
begin
  select * into k from public.counters where id = p_counter;
  if not found or k.status <> 'approved' then
    raise exception '댓글을 달 수 없는 문서입니다.' using errcode = 'P0002';
  end if;
  if p_parent is not null then
    if public.is_guest(me) then
      raise exception '비회원은 답글을 달 수 없습니다. 구글·카카오를 연결하면 달 수 있습니다.' using errcode = '42501';
    end if;
    select * into par from public.doc_comments where id = p_parent;
    if not found or par.counter_id <> k.id or par.deleted_at is not null or par.status <> 'visible' then
      raise exception '답글을 달 댓글을 찾지 못했습니다. (지워졌거나 숨겨졌을 수 있습니다)' using errcode = 'P0002';
    end if;
    if par.parent_id is not null then
      raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
    end if;
  end if;
  perform public.board_throttle(me, 'comment');
  insert into public.doc_comments (counter_id, author_id, body, parent_id) values (k.id, me, b, p_parent) returning id into new_id;
  perform public.notify_new_comment('doc', k.id,
    (select proposer_id from public.edit_proposals where id = public.origin_proposal_id(k.id)),
    par.author_id, p_parent is not null);
  return new_id;
end;
$$;
revoke execute on function public.create_doc_comment(bigint, text, bigint) from public, anon;
grant execute on function public.create_doc_comment(bigint, text, bigint) to authenticated;

-- ---------------------------------------------------------------------
-- 5. 탈퇴: 문서 댓글도 다른 사람의 남은 답글이 달린 내 댓글은 껍데기(작성자는 FK가 비움), 나머지 내 문서 댓글은 바로 삭제
--    (058의 탑신병자 커뮤니티·빌드 댓글, 글 규칙은 그대로)
-- ---------------------------------------------------------------------
create or replace function public.board_on_profile_delete()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  -- 058: 댓글 (탑신병자 커뮤니티 + 빌드)
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
  with shells as (
    update public.build_comments c
       set body = '', deleted_at = coalesce(c.deleted_at, now()), delete_kind = coalesce(c.delete_kind, 'author'),
           delete_note = null, hidden_note = null
     where c.author_id = old.id
       and exists (select 1 from public.build_comments r
                    where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null)
    returning c.id)
  delete from public.reports where build_comment_id in (select id from shells);
  delete from public.build_comments c
   where c.author_id = old.id
     and not exists (select 1 from public.build_comments r
                      where r.parent_id = c.id and r.author_id is distinct from old.id and r.deleted_at is null);
  -- 059: 문서 댓글
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

-- ---------------------------------------------------------------------
-- 6. 1년 정리: 문서 댓글도 아직 남은(지우지 않았거나 보관 기간 안의) 답글이 있는 부모는 남긴다
-- ---------------------------------------------------------------------
create or replace function public.purge_deleted_writings()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  before timestamptz := now() - make_interval(days => coalesce(public.xp_rule('deleted_writing_keep_days'), 365));
  n_doc integer;
  n_comment integer;
  n_build_comment integer;
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
  delete from public.build_comments c
   where c.deleted_at < before
     and not exists (select 1 from public.build_comments r where r.parent_id = c.id and (r.deleted_at is null or r.deleted_at >= before));
  get diagnostics n_build_comment = row_count;
  delete from public.posts where deleted_at < before;  -- 그 아래 다른 사람 댓글·사진·신고·알림도 함께
  get diagnostics n_post = row_count;
  return jsonb_build_object('posts', n_post, 'comments', n_comment, 'doc_comments', n_doc, 'build_comments', n_build_comment);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 경험치 설정 메모: 답글도 댓글 (값은 그대로 - 문서 댓글 답글은 xp_should_have가 이미 문서 댓글로 센다)
-- ---------------------------------------------------------------------
update public.xp_rules set note = '탑신병자 커뮤니티 댓글·답글 + 문서 댓글·답글 (합쳐서 하루 상한)' where key = 'comment';
update public.xp_rules set note = '댓글 경험치 하루 상한 (탑신병자 커뮤니티 댓글·답글 + 문서 댓글·답글 합계)' where key = 'comment_daily_cap';

commit;
