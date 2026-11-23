-- =====================================================================
-- 068: 운영자 활동 제한 (2026-11-23, SPEC 6-85) - 새 표 2개, 새 함수 9개, 새 트리거 29개, 기존 함수 37개 다시 정의, 정책 3개·제약 2개 고침.
--
-- 1. 운영자(admin, 운영자 모드 켬)만 restrict_user(대상, 일수 1~365, 사유 1~500자)로 건다. 풀리는 시각 = 지금 + 일수(분 단위 올림).
--    기간이 지나면 저절로 풀린다(cron 없음 - 매번 ends_at > now()로 본다). lift_restriction(번호, 메모)로 직접 풀 수 있다.
--    이미 걸려 있으면 새로 못 건다(먼저 해제). 자기 자신·운영자·감독관에게는 못 건다. 제한 중인 사람은 감독관으로 지정할 수 없다(set_moderator).
--    기록 표 user_restrictions: 본인·운영자만 읽기(RLS), 탈퇴하면 함께 지워진다(on delete cascade). 처리 기록(moderation_log)에는 기간만 남긴다.
-- 2. 두 겹으로 막는다:
--    ① 일반 사용자가 부르는 쓰기 함수 29개 맨 앞에 assert_can_write() (선언부 첫 줄 - 입력 검사보다 먼저):
--       빌드·상대법 등록(create_build·create_matchup)·수정(edit_build·edit_my_build·resubmit_build), 제안 고치기·다시 보내기,
--       추천(vote_build·vote_post), 글·댓글·문서 댓글 쓰기·고치기(+ begin_edit), 신고 6종, 장인 팔로우, 빌드 저장(save_build),
--       장인 신청, 사진 올리기(set_profile_photo·set_application_photo), 장인 링크(set_build_link·set_profile_links).
--       함수 본문은 067과 같고 그 한 줄만 더했다(067 DB의 pg_get_functiondef를 그대로 옮김).
--    ② 표 트리거 restriction_guard: 지금 로그인한 사람이 제한 중이면 내용 표에 새 줄·내용 고치기를 막는다(지우기는 막지 않음).
--       빌드·수정 기록·상대법·매치업 문서·제안·글·댓글·문서 댓글·첨부·추천 2종·신고 4종·팔로우·저장·장인 신청·외부 링크·프로필(닉네임·대표 칭호·사진).
--       남의 일은 막지 않는다 → 운영자가 제한된 사람의 빌드를 숨기거나, 다른 사람이 그 사람 빌드에 추천하는 일은 그대로 된다.
--    + 직접 넣기 정책 2개(builds·edit_proposals)에 can_write(), 사진 올리기 사전 검사 2개(Storage 정책이 부름)가 제한 문장을 돌려준다.
-- 3. 막지 않는 일: 읽기, 로그인, 내 정보 보기, 계정 삭제, 팔로우 취소, 저장 해제, 차단·차단 해제, 내 글·댓글·문서 댓글·문의 지우기,
--    알림 읽음·알림 설정, [문의하기] 보내기, 내 사진 지우기, 내 장인 신청 취소. (허용 목록 표 restriction_exemptions에 이유와 함께)
-- 4. 문장: 「활동이 제한된 상태입니다. 2026-12-01 15:21에 풀립니다. 사유: …」(한국 시각, 오류 코드 TL423).
--    옛 앱(1.1 이하)도 서버의 한국어 문장을 그대로 띄운다(화면 코드가 한글 오류 문장을 그대로 보여 줌).
-- 5. 문의 분류 「이의 제기」(appeal) 추가 - 계정·탈퇴처럼 운영자만 읽고 답한다(감독관 제외).
-- 6. 빠뜨림 방지: tests/restriction_coverage_test.sql·scripts/check_restrictions_after.sql이 일반 사용자가 부를 수 있는 모든 쓰기 함수·쓰기 정책을
--    뽑아 "검사가 있거나 허용 목록에 있어야" 통과시킨다. 새 쓰기 함수를 만들면 assert_can_write()를 넣거나 허용 목록에 이유와 함께 넣는다.
--
-- 실행 전 supabase/scripts/check_restrictions_before.sql, 실행 뒤 check_restrictions_after.sql.
-- 067까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 그 뒤에 새 화면을 배포(푸시)한다.
-- (먼저 배포해도 화면은 죽지 않는다: 068 전 DB면 띠·운영자 칸이 「준비 중」으로 보이고, 이의 제기 분류는 숨는다.)
-- 기존 빌드·추천·수정 기록·알림·북마크 등 데이터는 바꾸지 않는다(실행 전후 확인이 줄 수·가장 큰 id·추천 합계·내용 지문을 비교).
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 067 상태로 돌아간다.
--    068이 만든 제한 기록·허용 목록은 지워지고, 처리 기록 중 restrict_user·lift_restriction 줄도 지워진다(종류 목록에서 빠지므로).
--    「이의 제기」 문의가 있으면 「계정·탈퇴」로 옮긴다(둘 다 운영자만 보는 분류). 기존 함수는 067 내용(pg_get_functiondef 그대로)으로 돌아간다.
--     begin;
--     -- 1) 정책·트리거·제약을 067 모양으로
--     alter policy "builds: 본인 이름으로 대기 빌드 등록" on public.builds
--       with check (author_id = (select auth.uid()) and public.has_nickname() and status = 'pending'
--                   and reviewed_by is null and reviewed_at is null and reject_reason is null and up_count = 0 and down_count = 0);
--     alter policy "edit_proposals: 본인 이름으로 대기 제안 작성" on public.edit_proposals
--       with check (proposer_id = (select auth.uid()) and public.has_nickname() and status = 'pending'
--                   and reviewed_by is null and reviewed_at is null and reject_reason is null);
--     update public.inquiries set category = 'account' where category = 'appeal';
--     alter policy "inquiries: 본인·운영진 읽기" on public.inquiries
--       using (user_id = (select auth.uid()) or public.is_admin() or (public.is_moderator() and category <> 'account'));
--     alter table public.inquiries drop constraint inquiries_category_check;
--     alter table public.inquiries add constraint inquiries_category_check check (category in ('bug', 'idea', 'account', 'other'));
--     drop trigger inquiries_notify_staff_move on public.inquiries;
--     create trigger inquiries_notify_staff_move after update of category on public.inquiries
--       for each row when (old.category = 'account' and new.category <> 'account')
--       execute function public.notify_staff_new_inquiry();
--     delete from public.moderation_log where action in ('restrict_user', 'lift_restriction');
--     alter table public.moderation_log drop constraint moderation_log_action_check;
--     alter table public.moderation_log add constraint moderation_log_action_check check (action in (
--       'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
--       'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report',
--       'dismiss_report', 'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
--       'remove_link', 'add_link_domain', 'remove_link_domain', 'grant_influencer', 'grant_title', 'revoke_title',
--       'remove_profile_photo'));
--     -- 2) 표 트리거 29개
--     drop trigger a_restriction on public.builds;
--     drop trigger a_restriction_edit on public.builds;
--     drop trigger a_restriction on public.build_revisions;
--     drop trigger a_restriction on public.counters;
--     drop trigger a_restriction on public.matchup_docs;
--     drop trigger a_restriction_edit on public.matchup_docs;
--     drop trigger a_restriction on public.edit_proposals;
--     drop trigger a_restriction_edit on public.edit_proposals;
--     drop trigger a_restriction on public.posts;
--     drop trigger a_restriction_edit on public.posts;
--     drop trigger a_restriction on public.post_comments;
--     drop trigger a_restriction_edit on public.post_comments;
--     drop trigger a_restriction on public.doc_comments;
--     drop trigger a_restriction_edit on public.doc_comments;
--     drop trigger a_restriction on public.board_attachments;
--     drop trigger a_restriction on public.build_votes;
--     drop trigger a_restriction_edit on public.build_votes;
--     drop trigger a_restriction on public.post_votes;
--     drop trigger a_restriction on public.reports;
--     drop trigger a_restriction on public.wiki_reports;
--     drop trigger a_restriction on public.link_reports;
--     drop trigger a_restriction on public.profile_photo_reports;
--     drop trigger a_restriction on public.influencer_follows;
--     drop trigger a_restriction on public.build_bookmarks;
--     drop trigger a_restriction on public.influencer_applications;
--     drop trigger a_restriction_edit on public.influencer_applications;
--     drop trigger a_restriction on public.ext_links;
--     drop trigger a_restriction_edit on public.ext_links;
--     drop trigger a_restriction_edit on public.profiles;
--     -- 3) 기존 함수 37개를 067 내용으로 (아래 정의는 067 DB의 pg_get_functiondef 그대로)
--     CREATE OR REPLACE FUNCTION public.apply_influencer(p_kind text, p_nickname text, p_channel_url text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_riot_id text DEFAULT NULL::text, p_opgg_url text DEFAULT NULL::text)
--      RETURNS bigint
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();  -- 로그인 + 닉네임
--       prof public.profiles;
--       nick text := btrim(coalesce(p_nickname, ''));
--       k text;
--       chan text := nullif(btrim(coalesce(p_channel_url, '')), '');
--       mail text := nullif(lower(btrim(coalesce(p_email, ''))), '');
--       riot text := nullif(regexp_replace(btrim(coalesce(p_riot_id, '')), '\s*#\s*', '#'), '');
--       opgg text := nullif(btrim(coalesce(p_opgg_url, '')), '');
--       days integer := coalesce(public.xp_rule('influencer_review_days'), 14);
--       next_at timestamptz;
--       holder public.profiles;
--       aid bigint;
--     begin
--       select * into prof from public.profiles where id = me for update;
--       if prof.is_guest then
--         raise exception E'장인 인증은 구글\u00B7카카오로 로그인한 회원만 신청할 수 있습니다.' using errcode = '42501';
--       end if;
--       if prof.role = 'admin' then
--         raise exception '운영자 계정은 장인 인증을 신청할 수 없습니다.' using errcode = '42501';
--       end if;
--       if prof.influencer is not null then
--         raise exception '이미 인증된 장인입니다.' using errcode = '23514';
--       end if;
--       if exists (select 1 from public.influencer_applications where user_id = me and status = 'pending') then
--         raise exception '이미 심사 중인 신청이 있습니다.' using errcode = '23514';
--       end if;
--       if prof.nickname_state = 'yielding' then
--         raise exception '지금 닉네임은 바뀔 예정입니다. 먼저 새 닉네임을 정한 뒤 신청해 주세요.' using errcode = '23514';
--       end if;
--       next_at := public.influencer_next_apply_at(me);
--       if next_at is not null then
--         raise exception '장인 인증은 %부터 다시 신청할 수 있습니다.',
--           to_char(next_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') using errcode = 'P0001';
--       end if;
--       if p_kind is null or p_kind not in ('creator', 'pro', 'grandmaster') then
--         raise exception '유형을 골라 주세요.' using errcode = '22023';
--       end if;
--       if char_length(nick) not between 1 and 20 then
--         raise exception '희망 닉네임은 1~20자로 적어 주세요.' using errcode = '22023';
--       end if;
--
--       if p_kind in ('creator', 'pro') then
--         if chan is null or char_length(chan) > 300 or chan !~* '^https?://[^\s/]+\.[^\s]+$' then
--           raise exception E'채널\u00B7방송 링크를 https://로 시작하는 주소로 적어 주세요.' using errcode = '22023';
--         end if;
--         if mail is null or char_length(mail) > 254 or mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
--           raise exception '공식 이메일을 적어 주세요. (채널 소개란이나 팀 공식 페이지에 공개된 이메일)' using errcode = '22023';
--         end if;
--         riot := null;
--         opgg := null;
--         if exists (select 1 from public.influencer_applications
--                     where channel_key = public.influencer_channel_key(chan) and status in ('pending', 'approved')) then
--           raise exception '이미 신청됐거나 인증된 채널입니다. 본인의 채널이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
--         end if;
--       else
--         if riot is null or riot !~ '^[^#]{3,16}#[^#\s]{3,5}$' then
--           raise exception '라이엇 닉네임#태그를 적어 주세요. (예: 닉네임#KR1)' using errcode = '22023';
--         end if;
--         if opgg is null or char_length(opgg) > 300 or opgg !~* '^https?://([a-z0-9-]+\.)*op\.gg(/\S*)?$' then
--           raise exception E'op.gg 링크를 적어 주세요. (https://op.gg/\u2026)' using errcode = '22023';
--         end if;
--         chan := null;
--         mail := null;
--         if exists (select 1 from public.influencer_applications
--                     where riot_key = public.influencer_riot_key(riot) and status in ('pending', 'approved')) then
--           raise exception '이미 신청됐거나 인증된 라이엇 닉네임입니다. 본인의 계정이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
--         end if;
--       end if;
--
--       -- 희망 닉네임: 다른 보통 회원 1명과만 겹칠 수 있다 (승인되면 그 회원이 3일 유예 뒤 임시 닉네임으로)
--       k := public.nickname_key(nick);
--       perform pg_advisory_xact_lock(hashtext('nickname_key:' || k));
--       if exists (select 1 from public.profiles o where o.nickname_key = k and o.id <> me and o.nickname_state = 'pending') then
--         raise exception '이미 장인 인증을 신청 중인 닉네임입니다. 본인의 닉네임이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
--       end if;
--       select * into holder from public.profiles o where o.nickname_key = k and o.id <> me limit 1;
--       if found and (holder.influencer is not null or holder.nickname_state = 'yielding') then
--         raise exception '이미 인증된 장인이 쓰는 닉네임입니다.' using errcode = '23505';
--       end if;
--       if found and holder.role <> 'user' then
--         raise exception '운영진이 쓰는 닉네임이라 신청할 수 없습니다.' using errcode = '23505';
--       end if;
--
--       insert into public.influencer_applications
--         (user_id, kind, nickname, old_nickname, channel_url, channel_key, official_email, riot_id, riot_key, opgg_url, expires_at)
--       values (me, p_kind, nick, prof.nickname, chan, public.influencer_channel_key(chan), mail, riot,
--               case when riot is not null then public.influencer_riot_key(riot) end, opgg, now() + make_interval(days => days))
--       returning id into aid;
--
--       -- 닉네임을 희망 닉네임으로 + 인증 대기 (사칭 금지 검사는 트리거가 그대로 한다)
--       perform public.system_set_nickname(me, nick, 'pending', null, 'apply');
--
--       -- 신청자에게 접수 알림 (본인 알림이라 notify()를 거치지 않음), 운영자에게 새 신청 알림
--       insert into public.notifications (user_id, kind, message)
--       values (me, 'influencer_received', case when p_kind = 'grandmaster'
--         then format('신청이 접수됐습니다. %s일 안에 운영자 계정 {운영자 닉네임}으로 친구 요청을 보내 주세요. '
--                     '요청이 도착하면 이 닉네임의 주인이 맞는지 확인합니다. 수락은 하지 않습니다.', days)
--         else format('신청이 접수됐습니다. 적어 주신 공식 이메일로 확인 메일을 보냅니다. %s일 안에 "본인입니다"라고 회신해 주세요.', days) end);
--       insert into public.notifications (user_id, kind, message)
--       select u.id, 'influencer_applied', format(E'장인 인증 신청이 들어왔습니다. (%s \u00B7 %s)', nick, public.influencer_kind_label(p_kind))
--         from public.profiles u where u.role = 'admin' and u.id <> me;
--       return aid;
--     end;
--     $function$;
--
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
--           else
--             update public.doc_comments set edit_grace_until = grace where id = p_id;
--           end if;
--         end if;
--       end if;
--       perform public.require_edit_window(p_kind, created, grace);
--       return public.edit_deadline(p_kind, created, grace);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.create_build(p_counter bigint, p_build jsonb)
--      RETURNS bigint
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       c jsonb := public.clean_wiki_build(p_build);
--       bid bigint;
--     begin
--       if not exists (select 1 from public.counters where id = p_counter and status = 'approved') then
--         raise exception '빌드를 등록할 상대법을 찾지 못했습니다.' using errcode = '23514';
--       end if;
--       perform public.wiki_throttle('create');
--       bid := public.wiki_insert_build(p_counter, me, c);
--       perform public.notify_admins_wiki('build_created', '새 빌드가 등록됐습니다.', p_counter, bid);
--       return bid;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.create_comment(p_post bigint, p_body text, p_media text[] DEFAULT '{}'::text[], p_parent bigint DEFAULT NULL::bigint)
--      RETURNS bigint
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       b text := public.board_text_or_empty(p_body, '댓글', 1000, cardinality(coalesce(p_media, '{}')) > 0);
--       p public.posts%rowtype;
--       par public.post_comments%rowtype;
--       new_id bigint;
--     begin
--       if public.is_guest(me) then
--         raise exception '비회원은 댓글을 달 수 없습니다. 구글·카카오를 연결하면 달 수 있습니다.' using errcode = '42501';
--       end if;
--       select * into p from public.posts where id = p_post;
--       if not found or p.status <> 'visible' then
--         raise exception '글을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if p.deleted_at is not null then
--         raise exception '삭제된 글에는 댓글을 달 수 없습니다.' using errcode = '23514';
--       end if;
--       if p_parent is not null then
--         select * into par from public.post_comments where id = p_parent;
--         if not found or par.post_id <> p.id or par.deleted_at is not null or par.status <> 'visible' then
--           raise exception '답글을 달 댓글을 찾지 못했습니다. (지워졌거나 숨겨졌을 수 있습니다)' using errcode = 'P0002';
--         end if;
--         if par.parent_id is not null then
--           raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
--         end if;
--       end if;
--       perform public.board_throttle(me, 'comment');
--       insert into public.post_comments (post_id, author_id, body, parent_id) values (p.id, me, b, p_parent) returning id into new_id;
--       perform public.media_set(null, new_id, me, p_media);
--       perform public.notify_new_comment('post', p.id, p.author_id, par.author_id, p_parent is not null);
--       return new_id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.create_doc_comment(p_counter bigint, p_body text, p_parent bigint DEFAULT NULL::bigint)
--      RETURNS bigint
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       b text := public.board_text(p_body, '댓글', 1000);
--       k public.counters%rowtype;
--       par public.doc_comments%rowtype;
--       new_id bigint;
--     begin
--       select * into k from public.counters where id = p_counter;
--       if not found or k.status <> 'approved' then
--         raise exception '댓글을 달 수 없는 문서입니다.' using errcode = 'P0002';
--       end if;
--       if p_parent is not null then
--         if public.is_guest(me) then
--           raise exception '비회원은 답글을 달 수 없습니다. 구글·카카오를 연결하면 달 수 있습니다.' using errcode = '42501';
--         end if;
--         select * into par from public.doc_comments where id = p_parent;
--         if not found or par.counter_id <> k.id or par.deleted_at is not null or par.status <> 'visible' then
--           raise exception '답글을 달 댓글을 찾지 못했습니다. (지워졌거나 숨겨졌을 수 있습니다)' using errcode = 'P0002';
--         end if;
--         if par.parent_id is not null then
--           raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
--         end if;
--       end if;
--       perform public.board_throttle(me, 'comment');
--       insert into public.doc_comments (counter_id, author_id, body, parent_id) values (k.id, me, b, p_parent) returning id into new_id;
--       perform public.notify_new_comment('doc', k.id,
--         (select proposer_id from public.edit_proposals where id = public.origin_proposal_id(k.id)),
--         par.author_id, p_parent is not null);
--       return new_id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.create_matchup(p_target text, p_mine text, p_build jsonb)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();  -- 로그인 + 닉네임 (비회원 가능)
--       c jsonb := public.clean_wiki_build(p_build);
--       st text;
--       cid bigint;
--       bid bigint;
--     begin
--       if coalesce(p_target, '') !~ '^[A-Za-z]{1,30}$' or coalesce(p_mine, '') !~ '^[A-Za-z]{1,30}$' then
--         raise exception '챔피언을 다시 골라 주세요.' using errcode = '23514';
--       end if;
--       if p_target = p_mine then
--         raise exception '같은 챔피언끼리는 상대법을 만들 수 없습니다.' using errcode = '23514';
--       end if;
--       select status into st from public.counters where target_champion = p_target and counter_champion = p_mine;
--       if st = 'approved' then
--         raise exception '이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.' using errcode = '23505';
--       elsif st is not null then
--         raise exception '운영진이 숨긴 상대법이라 새로 등록할 수 없습니다.' using errcode = '23514';
--       end if;
--       perform public.wiki_throttle('create');
--
--       begin
--         insert into public.counters (target_champion, counter_champion, sort_order, status, proposed_by, wiki)
--         values (p_target, p_mine,
--                 (select coalesce(max(sort_order), 0) + 1 from public.counters where target_champion = p_target),
--                 'approved', me, true)
--         returning id into cid;
--       exception when unique_violation then
--         raise exception '이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.' using errcode = '23505';
--       end;
--       -- 옛 화면용 사본 (PWA에 남은 옛 상대법 화면·챔피언 목록이 내용을 보여 주게). 이후 빌드 수정은 반영하지 않는다
--       insert into public.matchup_docs (counter_id, summary, level_notes, lane_cautions, updated_by)
--       values (cid, c ->> 'summary', c -> 'level_notes', c ->> 'lane_cautions', me);
--       bid := public.wiki_insert_build(cid, me, c);
--       update public.counters set first_build_id = bid where id = cid;
--       perform public.notify_admins_wiki('matchup_created', '새 상대법이 등록됐습니다.', cid, bid);
--       return jsonb_build_object('counter_id', cid, 'build_id', bid);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.create_post(p_title text, p_body text, p_media text[] DEFAULT '{}'::text[])
--      RETURNS bigint
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       t text := public.board_text(p_title, '제목', 100);
--       b text := public.board_text_or_empty(p_body, '본문', 10000, cardinality(coalesce(p_media, '{}')) > 0);
--       new_id bigint;
--     begin
--       perform public.board_throttle(me, 'post');
--       insert into public.posts (author_id, title, body) values (me, t, b) returning id into new_id;
--       perform public.media_set(new_id, null, me, p_media);
--       return new_id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.edit_build(p_id bigint, p_version integer, p_build jsonb)
--      RETURNS integer
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       b public.builds;
--       nb public.builds;
--       c jsonb;
--       before jsonb;
--       same_build boolean;
--     begin
--       select * into b from public.builds where id = p_id for update;
--       if not found then
--         raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       perform public.build_edit_check(b, me);  -- 043: 공개 여부·비회원 규칙 (잠금이 들어올 자리)
--       if p_version is distinct from b.version then
--         raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
--       end if;
--       c := public.clean_wiki_build(p_build);
--       if not (p_build ? 'skill_sequence') then  -- 065: 옛 앱은 이 칸을 모른다 -> 지우지 않고 그대로
--         c := c || jsonb_build_object('skill_sequence', b.skill_sequence);
--       end if;
--       if (c ->> 'skill_sequence') is distinct from b.skill_sequence then
--         perform public.check_skill_sequence(c ->> 'skill_sequence', b.counter_id);
--       end if;
--       before := public.wiki_snapshot(b);
--       if c - 'patch' = before - 'patch' then
--         raise exception '바뀐 내용이 없습니다.' using errcode = '23514';
--       end if;
--       same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' - 'skill_sequence' = public.build_signature(b);
--       if not same_build and exists (
--         select 1 from public.builds x
--          where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
--            and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' - 'skill_sequence'
--       ) then
--         raise exception '똑같은 빌드가 이미 공개돼 있습니다. 그 빌드를 추천해 주세요.' using errcode = '23514';
--       end if;
--       perform public.wiki_throttle('edit');
--
--       update public.builds
--          set runes = c -> 'runes',
--              summoner_spells = array(select jsonb_array_elements_text(c -> 'summoner_spells')),
--              starting_items = array(select jsonb_array_elements_text(c -> 'starting_items')),
--              core_items = array(select jsonb_array_elements_text(c -> 'core_items')),
--              max_skill = c ->> 'max_skill',
--              patch = case when same_build then b.patch else c ->> 'patch' end,  -- 글·스킬 순서만 고치면 패치 그대로
--              name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
--              skill_sequence = c ->> 'skill_sequence',
--              version = b.version + 1, updated_at = now(), updated_by = me
--        where id = b.id
--        returning * into nb;  -- 핵심 템트리·강타·시작 골드는 바뀐 칸만 트리거가 검사
--       insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
--       values (b.id, b.counter_id, me, 'edit', before, public.wiki_snapshot(nb), nb.version);
--       if me is distinct from b.author_id then
--         insert into public.build_editors (build_id, user_id) values (b.id, me)
--         on conflict (build_id, user_id) do update set last_at = now(), edits = public.build_editors.edits + 1;
--       end if;
--       return nb.version;  -- 수정마다 알림은 보내지 않는다. 경험치도 없다
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.edit_comment(p_id bigint, p_body text, p_media text[] DEFAULT NULL::text[])
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       c public.post_comments%rowtype;
--       keep_count integer;
--       b text;
--       changed boolean;
--     begin
--       select * into c from public.post_comments where id = p_id for update;
--       if not found or c.deleted_at is not null or not public.post_live(c.post_id) then
--         raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if c.author_id <> me then
--         raise exception '내 댓글만 고칠 수 있습니다.' using errcode = '42501';
--       end if;
--       if c.status <> 'visible' or exists (select 1 from public.posts where id = c.post_id and status <> 'visible') then
--         raise exception '운영진이 숨긴 댓글·글은 고칠 수 없습니다.' using errcode = '23514';
--       end if;
--       perform public.require_edit_window('comment', c.created_at, c.edit_grace_until);
--       keep_count := coalesce(cardinality(p_media), (select count(*) from public.board_attachments where comment_id = c.id));
--       b := public.board_text_or_empty(p_body, '댓글', 1000, keep_count > 0);
--       changed := false;
--       if p_media is not null then
--         changed := public.media_set(null, c.id, me, p_media);
--       end if;
--       if b = c.body and not changed then
--         return;
--       end if;
--       update public.post_comments set body = b, edited_at = now() where id = c.id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.edit_doc_comment(p_id bigint, p_body text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       b text := public.board_text(p_body, '댓글', 1000);
--       d public.doc_comments%rowtype := public.doc_comment_for_update(p_id);
--     begin
--       if d.deleted_at is not null then
--         raise exception '댓글을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if d.author_id <> me then
--         raise exception '내 댓글만 고칠 수 있습니다.' using errcode = '42501';
--       end if;
--       if d.status <> 'visible' or exists (select 1 from public.counters where id = d.counter_id and status <> 'approved') then
--         raise exception '숨긴 댓글·문서는 고칠 수 없습니다.' using errcode = '23514';
--       end if;
--       perform public.require_edit_window('doc_comment', d.created_at, d.edit_grace_until);
--       if b = d.body then
--         return;
--       end if;
--       update public.doc_comments set body = b, edited_at = now() where id = d.id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.edit_my_build(p_id bigint, p_build jsonb)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       b public.builds%rowtype;
--       nb jsonb;
--     begin
--       select * into b from public.builds where id = p_id for update;
--       if not found or b.author_id is distinct from (select auth.uid()) then
--         raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if b.status = 'revision_requested' then
--         raise exception '재검토 요청을 받은 빌드는 [고쳐서 다시 보내기]로 고쳐 주세요.' using errcode = '23514';
--       end if;
--       if b.status <> 'pending' then
--         raise exception '승인 대기 중인 빌드만 고칠 수 있습니다.' using errcode = '23514';
--       end if;
--       if (select status from public.counters where id = b.counter_id) is distinct from 'approved' then
--         raise exception '이 매치업은 지금 고칠 수 없습니다.' using errcode = '23514';
--       end if;
--       nb := public.clean_build(p_build);
--       if nb - 'patch' = public.build_signature(b) then
--         raise exception '고친 내용이 없습니다.' using errcode = '23514';
--       end if;
--       if exists (
--         select 1 from public.builds x
--         where x.counter_id = b.counter_id and x.status = 'approved' and public.build_signature(x) = nb - 'patch'
--       ) then
--         raise exception '똑같은 빌드가 이미 공개돼 있습니다. 추천으로 응원해 주세요.' using errcode = '23514';
--       end if;
--
--       perform public.set_build_fields(b.id, nb);
--       update public.builds set version = version + 1, edited_at = now() where id = b.id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.edit_my_proposal(p_id bigint, p_content jsonb, p_build jsonb)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       p public.edit_proposals%rowtype;
--       new_content jsonb;
--       new_build jsonb;
--       st text;
--     begin
--       select * into p from public.edit_proposals where id = p_id for update;
--       if not found or p.proposer_id is distinct from (select auth.uid()) then
--         raise exception '제안을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if p.status = 'revision_requested' then
--         raise exception '재검토 요청을 받은 제안은 [고쳐서 다시 보내기]로 고쳐 주세요.' using errcode = '23514';
--       end if;
--       if p.status <> 'pending' then
--         raise exception '승인 대기 중인 제안만 고칠 수 있습니다.' using errcode = '23514';
--       end if;
--       new_content := public.clean_doc_content(p_content);
--
--       if p.type = 'new_counter' then
--         if p_build is null then
--           raise exception '빌드도 함께 채워 주세요. 새 상대법 제안에는 빌드가 꼭 있어야 합니다.' using errcode = '23514';
--         end if;
--         new_build := public.clean_build(p_build);
--         if public.is_hidden_counter_flow(p) then
--           select status into st from public.counters where id = p.counter_id;
--           if st is distinct from 'hidden' then
--             raise exception '이 상대법은 지금 고칠 수 없습니다.' using errcode = '23514';
--           end if;
--         else
--           select status into st from public.counters
--            where target_champion = p.target_champion and counter_champion = p.counter_champion and status in ('approved', 'hidden');
--           if st = 'approved' then
--             raise exception '그 사이 같은 상대법이 등록됐습니다. 문서 수정 제안을 이용해 주세요.' using errcode = '23514';
--           end if;
--           if st = 'hidden' then
--             raise exception '운영자가 숨긴 상대법이라 지금은 고칠 수 없습니다.' using errcode = '23514';
--           end if;
--         end if;
--       else  -- doc_edit
--         if p_build is not null then
--           raise exception '문서 수정 제안에는 빌드를 넣지 않습니다.' using errcode = '23514';
--         end if;
--         select status into st from public.counters where id = p.counter_id;
--         if st = 'approved' and new_content = (
--           select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
--           from public.matchup_docs d where d.counter_id = p.counter_id
--         ) then
--           raise exception '지금 문서와 달라진 내용이 없습니다.' using errcode = '23514';
--         end if;
--       end if;
--
--       if new_content = public.clean_doc_content(p.content)
--          and (p.type = 'doc_edit' or (p.build is not null and new_build - 'patch' = p.build - 'patch')) then
--         raise exception '고친 내용이 없습니다.' using errcode = '23514';
--       end if;
--
--       update public.edit_proposals
--          set content = new_content, build = coalesce(new_build, build), version = version + 1, edited_at = now()
--        where id = p.id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.edit_post(p_id bigint, p_title text, p_body text, p_media text[] DEFAULT NULL::text[])
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       p public.posts%rowtype := public.board_post_for_update(p_id);
--       keep_count integer;
--       t text;
--       b text;
--       changed boolean;
--     begin
--       if p.author_id is distinct from me then
--         raise exception '내 글만 고칠 수 있습니다.' using errcode = '42501';
--       end if;
--       if p.deleted_at is not null then
--         raise exception '삭제된 글입니다.' using errcode = '23514';
--       end if;
--       if p.status <> 'visible' then
--         raise exception '운영진이 숨긴 글은 고칠 수 없습니다.' using errcode = '23514';
--       end if;
--       perform public.require_edit_window('post', p.created_at, p.edit_grace_until);
--       keep_count := coalesce(cardinality(p_media), (select count(*) from public.board_attachments where post_id = p.id));
--       t := public.board_text(p_title, '제목', 100);
--       b := public.board_text_or_empty(p_body, '본문', 10000, keep_count > 0);
--       changed := false;
--       if p_media is not null then
--         changed := public.media_set(p.id, null, me, p_media);
--       end if;
--       if t = p.title and b = p.body and not changed then
--         return;  -- 바뀐 게 없으면 "수정됨"도 붙이지 않는다
--       end if;
--       update public.posts set title = t, body = b, edited_at = now() where id = p.id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.follow_influencer(p_user uuid)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--     begin
--       if me is null then
--         raise exception '로그인해 주세요.' using errcode = '42501';
--       end if;
--       return public.follow_influencer_unchecked(me, p_user);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.report_comment(p_id bigint, p_reason text, p_detail text DEFAULT NULL::text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       d text := public.board_report_check(p_reason, p_detail);
--       c public.post_comments%rowtype;
--     begin
--       select * into c from public.post_comments where id = p_id;
--       if not found or c.status <> 'visible' or c.deleted_at is not null
--          or exists (select 1 from public.posts where id = c.post_id and (status <> 'visible' or deleted_at is not null)) then
--         raise exception '신고할 수 없는 댓글입니다.' using errcode = 'P0002';
--       end if;
--       if c.author_id = me then
--         raise exception '내 댓글은 신고할 수 없습니다.' using errcode = '23514';
--       end if;
--       insert into public.reports (reporter_id, comment_id, reason, detail) values (me, c.id, p_reason, d);
--     exception when unique_violation then
--       raise exception '이미 신고한 댓글입니다.' using errcode = '23505';
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.report_doc_comment(p_id bigint, p_reason text, p_detail text DEFAULT NULL::text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       dt text := public.board_report_check(p_reason, p_detail);
--       d public.doc_comments%rowtype;
--     begin
--       select * into d from public.doc_comments where id = p_id;
--       if not found or d.status <> 'visible' or d.deleted_at is not null
--          or exists (select 1 from public.counters where id = d.counter_id and status <> 'approved') then
--         raise exception '신고할 수 없는 댓글입니다.' using errcode = 'P0002';
--       end if;
--       if d.author_id = me then
--         raise exception '내 댓글은 신고할 수 없습니다.' using errcode = '23514';
--       end if;
--       insert into public.reports (reporter_id, doc_comment_id, reason, detail) values (me, d.id, p_reason, dt);
--     exception when unique_violation then
--       raise exception '이미 신고한 댓글입니다.' using errcode = '23505';
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.report_link(p_link bigint, p_reason text, p_detail text DEFAULT NULL::text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       d text := nullif(btrim(coalesce(p_detail, '')), '');
--       owner uuid;
--     begin
--       if public.is_guest(me) then
--         raise exception '비회원은 신고할 수 없습니다. 구글/카카오를 연결하면 할 수 있습니다.' using errcode = '42501';
--       end if;
--       if p_reason is null or p_reason not in ('spam', 'obscene', 'malicious', 'not_own', 'other') then
--         raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
--       end if;
--       if p_reason = 'other' and d is null then
--         raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
--       end if;
--       if char_length(d) > 500 then
--         raise exception '신고 내용은 500자 이하로 적어 주세요.' using errcode = '23514';
--       end if;
--       select l.owner_id into owner from public.ext_links l where l.id = p_link;
--       if not found or not public.ext_link_visible(p_link) then
--         raise exception '신고할 수 없는 링크입니다.' using errcode = 'P0002';
--       end if;
--       if owner = me then
--         raise exception '내 링크는 신고할 수 없습니다.' using errcode = '23514';
--       end if;
--       insert into public.link_reports (link_id, reporter_id, reason, detail) values (p_link, me, p_reason, d);
--     exception when unique_violation then
--       raise exception '이미 신고한 링크입니다.' using errcode = '23505';
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.report_post(p_id bigint, p_reason text, p_detail text DEFAULT NULL::text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       d text := public.board_report_check(p_reason, p_detail);
--       p public.posts%rowtype;
--     begin
--       select * into p from public.posts where id = p_id;
--       if not found or p.status <> 'visible' or p.deleted_at is not null then
--         raise exception '신고할 수 없는 글입니다.' using errcode = 'P0002';
--       end if;
--       if p.author_id = me then
--         raise exception '내 글은 신고할 수 없습니다.' using errcode = '23514';
--       end if;
--       insert into public.reports (reporter_id, post_id, reason, detail) values (me, p.id, p_reason, d);
--     exception when unique_violation then
--       raise exception '이미 신고한 글입니다.' using errcode = '23505';
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.report_profile_photo(p_user uuid, p_reason text, p_detail text DEFAULT NULL::text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       d text := nullif(btrim(coalesce(p_detail, '')), '');
--       path text;
--     begin
--       if public.is_guest(me) then
--         raise exception '비회원은 신고할 수 없습니다. 구글/카카오를 연결하면 할 수 있습니다.' using errcode = '42501';
--       end if;
--       if p_reason is null or p_reason not in ('obscene', 'hate', 'impersonation', 'spam', 'other') then
--         raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
--       end if;
--       if p_reason = 'other' and d is null then
--         raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
--       end if;
--       if char_length(d) > 500 then
--         raise exception '신고 내용은 500자 이하로 적어 주세요.' using errcode = '23514';
--       end if;
--       if p_user = me then
--         raise exception '내 사진은 신고할 수 없습니다.' using errcode = '23514';
--       end if;
--       select photo_path into path from public.profiles where id = p_user and influencer is not null;
--       if path is null then
--         raise exception '신고할 수 없는 사진입니다. 이미 바뀌었거나 지워졌을 수 있습니다.' using errcode = 'P0002';
--       end if;
--       insert into public.profile_photo_reports (owner_id, photo_path, reporter_id, reason, detail) values (p_user, path, me, p_reason, d);
--     exception when unique_violation then
--       raise exception '이미 신고한 사진입니다.' using errcode = '23505';
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.report_wiki(p_counter bigint, p_build bigint, p_reason text, p_memo text DEFAULT NULL::text)
--      RETURNS bigint
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();  -- 로그인 + 닉네임
--       m text := nullif(btrim(coalesce(p_memo, '')), '');
--       cid bigint := p_counter;
--       b public.builds;
--       cap integer := coalesce(public.xp_rule('error_report_daily_cap'), 10);
--       today integer;
--       first_open boolean;
--       rid bigint;
--     begin
--       if public.is_guest(me) then
--         raise exception '오류 신고는 구글·카카오로 로그인한 회원만 할 수 있습니다.' using errcode = '42501';
--       end if;
--       if p_build is not null then
--         select * into b from public.builds where id = p_build;
--         if not found or b.status <> 'approved' or (cid is not null and b.counter_id <> cid) then
--           raise exception '신고할 빌드를 찾지 못했습니다.' using errcode = 'P0002';
--         end if;
--         cid := b.counter_id;
--       end if;
--       if cid is null or not exists (select 1 from public.counters where id = cid and status = 'approved') then
--         raise exception '신고할 상대법을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if p_reason is null or p_reason not in ('wrong', 'outdated', 'vandal', 'duplicate', 'other')
--          or (p_build is null and p_reason not in ('wrong', 'vandal', 'other')) then
--         raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
--       end if;
--       if p_reason = 'other' and m is null then
--         raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
--       end if;
--       if char_length(m) > 200 then
--         raise exception '메모는 200자 이하로 적어 주세요.' using errcode = '23514';
--       end if;
--
--       perform pg_advisory_xact_lock(hashtext('wiki_report:' || me::text));  -- 같은 사람이 동시에 여러 번 눌러도 상한을 넘지 않게
--       select count(*) into today from public.wiki_reports
--        where reporter_id = me
--          and created_at >= ((now() at time zone 'Asia/Seoul')::date::timestamp at time zone 'Asia/Seoul');
--       if today >= cap then
--         raise exception '오류 신고는 하루에 %건까지 할 수 있습니다. 내일 다시 해 주세요.', cap using errcode = '23514';
--       end if;
--
--       perform 1 from public.counters where id = cid for update;  -- 같은 대상의 "첫 신고" 판단이 겹치지 않게
--       first_open := not exists (
--         select 1 from public.wiki_reports
--          where counter_id = cid and build_id is not distinct from p_build and status = 'open');
--       begin
--         insert into public.wiki_reports (counter_id, build_id, reporter_id, reason, memo)
--         values (cid, p_build, me, p_reason, m)
--         returning id into rid;
--       exception when unique_violation then
--         raise exception '이미 신고한 내용이 처리를 기다리고 있습니다.' using errcode = '23505';
--       end;
--
--       -- 운영진 알림: 그 대상에 처리 전 신고가 처음 생길 때만 (운영자 + 감독관, 신고자 본인 제외)
--       if first_open then
--         insert into public.notifications (user_id, kind, message, counter_id, build_id)
--         select u.id, 'error_reported',
--                format('새 오류 신고가 들어왔습니다. (%s)', public.wiki_report_reason_label(p_reason)), cid, p_build
--           from public.profiles u
--          where u.role in ('admin', 'moderator') and u.id <> me;
--       end if;
--       return rid;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.resubmit_build(p_id bigint, p_build jsonb)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       b public.builds%rowtype;
--       nb jsonb;
--     begin
--       select * into b from public.builds where id = p_id for update;
--       if not found or b.author_id is distinct from (select auth.uid()) then
--         raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if b.status <> 'revision_requested' then
--         raise exception '재검토 요청을 받은 빌드만 다시 보낼 수 있습니다.' using errcode = '23514';
--       end if;
--       if (select status from public.counters where id = b.counter_id) is distinct from 'approved' then
--         raise exception '이 매치업은 지금 다시 보낼 수 없습니다.' using errcode = '23514';
--       end if;
--       nb := public.clean_build(p_build);
--       if nb - 'patch' = public.build_signature(b) then
--         raise exception '고친 내용이 없습니다. 운영자 메모를 보고 고쳐 주세요.' using errcode = '23514';
--       end if;
--       if exists (
--         select 1 from public.builds x
--         where x.counter_id = b.counter_id and x.status = 'approved' and public.build_signature(x) = nb - 'patch'
--       ) then
--         raise exception '똑같은 빌드가 이미 공개돼 있습니다. 추천으로 응원해 주세요.' using errcode = '23514';
--       end if;
--
--       perform public.set_build_fields(b.id, nb);
--       update public.builds set status = 'pending', resubmitted_at = now() where id = b.id;
--       insert into public.build_status_log (build_id, action, reason, actor)
--       values (b.id, 'resubmit', '작성자가 고쳐서 다시 보냄', (select auth.uid()));
--       update public.notifications set read_at = now()
--        where build_id = b.id and kind = 'revision_request' and read_at is null;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.resubmit_proposal(p_id bigint, p_content jsonb, p_build jsonb)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       p public.edit_proposals%rowtype;
--       hidden_flow boolean;
--       st text;
--       new_content jsonb;
--       new_build jsonb;
--     begin
--       select * into p from public.edit_proposals where id = p_id for update;
--       if not found or p.proposer_id is distinct from (select auth.uid()) then
--         raise exception '제안을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if p.status <> 'revision_requested' then
--         raise exception '재검토 요청을 받은 제안만 다시 보낼 수 있습니다.' using errcode = '23514';
--       end if;
--       hidden_flow := public.is_hidden_counter_flow(p);
--       new_content := public.clean_doc_content(p_content);
--
--       if p.type = 'new_counter' then
--         if p_build is null then
--           raise exception '빌드도 함께 채워 주세요. 새 상대법 제안에는 빌드가 꼭 있어야 합니다.' using errcode = '23514';
--         end if;
--         new_build := public.clean_build(p_build);
--         if hidden_flow then
--           select status into st from public.counters where id = p.counter_id for update;
--           if st is distinct from 'hidden' then
--             raise exception '이 상대법은 지금 다시 보낼 수 없습니다.' using errcode = '23514';
--           end if;
--         else
--           select status into st from public.counters
--            where target_champion = p.target_champion and counter_champion = p.counter_champion and status in ('approved', 'hidden');
--           if st = 'approved' then
--             raise exception '그 사이 같은 상대법이 등록됐습니다. 문서 수정 제안을 이용해 주세요.' using errcode = '23514';
--           end if;
--           if st = 'hidden' then
--             raise exception '운영자가 숨긴 상대법이라 지금은 다시 보낼 수 없습니다.' using errcode = '23514';
--           end if;
--         end if;
--       else  -- doc_edit
--         if p_build is not null then
--           raise exception '문서 수정 제안에는 빌드를 넣지 않습니다.' using errcode = '23514';
--         end if;
--         select status into st from public.counters where id = p.counter_id;
--         if st is distinct from 'approved' then
--           raise exception '이 매치업은 지금 다시 보낼 수 없습니다.' using errcode = '23514';
--         end if;
--         if new_content = (
--           select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
--           from public.matchup_docs d where d.counter_id = p.counter_id
--         ) then
--           raise exception '지금 문서와 달라진 내용이 없습니다.' using errcode = '23514';
--         end if;
--       end if;
--
--       if new_content = public.clean_doc_content(p.content)
--          and (p.type = 'doc_edit' or (p.build is not null and new_build - 'patch' = p.build - 'patch')) then
--         raise exception '고친 내용이 없습니다. 운영자 메모를 보고 고쳐 주세요.' using errcode = '23514';
--       end if;
--
--       update public.edit_proposals
--          set status = 'pending', content = new_content, build = coalesce(new_build, build), resubmitted_at = now(),
--              reviewed_by = null, reviewed_at = null
--        where id = p.id;
--
--       update public.notifications set read_at = now()
--        where proposal_id = p.id and kind = 'revision_request' and read_at is null;
--
--       if hidden_flow then
--         insert into public.counter_status_log (counter_id, action, proposal_id, actor)
--         values (p.counter_id, 'resubmit', p.id, (select auth.uid()));
--       end if;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.save_build(p_build bigint)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--       n integer;
--     begin
--       if me is null then
--         raise exception '로그인이 필요합니다.' using errcode = '42501';
--       end if;
--       if not public.has_nickname() then
--         raise exception '닉네임을 정한 뒤에 저장할 수 있습니다.' using errcode = '42501';
--       end if;
--       if not exists (
--         select 1 from public.builds b join public.counters c on c.id = b.counter_id
--          where b.id = p_build and b.status = 'approved' and c.status = 'approved'
--       ) then
--         raise exception '공개된 빌드만 저장할 수 있습니다.' using errcode = '23514';
--       end if;
--       -- 같은 사람이 동시에 여러 번 눌러도 한도를 넘지 않게 그 사람 줄을 잠근다
--       perform 1 from public.profiles where id = me for update;
--       if exists (select 1 from public.build_bookmarks where user_id = me and build_id = p_build) then
--         select count(*) into n from public.build_bookmarks where user_id = me;
--         return jsonb_build_object('saved', true, 'count', n);
--       end if;
--       select count(*) into n from public.build_bookmarks where user_id = me;
--       if n >= public.save_build_limit() then
--         raise exception '저장은 %개까지 할 수 있습니다. 안 보는 빌드를 해제해 주세요.', public.save_build_limit() using errcode = '23514';
--       end if;
--       insert into public.build_bookmarks (user_id, build_id) values (me, p_build);
--       return jsonb_build_object('saved', true, 'count', n + 1);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.set_application_photo(p_path text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       a public.influencer_applications%rowtype;
--       o record;
--       m text;
--       sz bigint;
--       daily integer := public.xp_rule('profile_photo_daily_max');
--     begin
--       select * into a from public.influencer_applications where user_id = me and status = 'pending' for update;
--       if not found then
--         raise exception '심사 중인 장인 인증 신청이 없습니다.' using errcode = 'P0002';
--       end if;
--       if p_path is null or p_path !~ ('^' || me::text || '/[0-9A-Za-z_-]{1,64}\.(webp|jpg)$') then
--         raise exception '사진을 다시 골라 주세요.' using errcode = '22023';
--       end if;
--       if p_path = a.photo_path then
--         return;  -- 이미 이 사진
--       end if;
--       select ob.owner_id, ob.metadata into o from storage.objects ob where ob.bucket_id = 'profile-photos' and ob.name = p_path;
--       if not found or o.owner_id is distinct from me::text then
--         raise exception '올린 사진을 찾지 못했습니다. 사진을 다시 골라 주세요.' using errcode = '23514';
--       end if;
--       m := o.metadata ->> 'mimetype';
--       sz := coalesce((o.metadata ->> 'size')::bigint, 0);
--       if m is null or m not in ('image/webp', 'image/jpeg') or sz <= 0 or sz > 1048576 then
--         raise exception '사진 형식이나 크기가 맞지 않습니다. 다른 사진을 골라 주세요.' using errcode = '23514';
--       end if;
--       delete from public.profile_photo_changes where user_id = me and created_at < now() - interval '2 days';
--       if (select count(*) from public.profile_photo_changes where user_id = me and created_at > now() - interval '24 hours') >= daily then
--         raise exception '프로필 사진은 하루에 %번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily using errcode = '54000';
--       end if;
--       update public.influencer_applications set photo_path = p_path, photo_updated_at = now() where id = a.id;
--       insert into public.profile_photo_changes (user_id) values (me);
--       delete from public.profile_photo_trash where path = p_path;  -- 혹시 대기열에 있던 내 파일을 다시 쓰면 지우지 않는다
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.set_build_link(p_build bigint, p_url text)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       b_author uuid;
--       parsed text[];
--       cur public.ext_links%rowtype;
--     begin
--       if not exists (select 1 from public.profiles where id = me and influencer is not null) then
--         raise exception '인증된 장인만 링크를 올릴 수 있습니다.' using errcode = '42501';
--       end if;
--       select b.author_id into b_author from public.builds b where b.id = p_build;
--       if not found then
--         raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if b_author is distinct from me then
--         raise exception '내가 처음 만든 빌드에만 링크를 달 수 있습니다.' using errcode = '42501';
--       end if;
--       perform pg_advisory_xact_lock(hashtext('ext_links:' || me::text));
--       select * into cur from public.ext_links where build_id = p_build;
--       if nullif(btrim(coalesce(p_url, '')), '') is null then
--         delete from public.ext_links where build_id = p_build;
--         return null;
--       end if;
--       parsed := public.ext_link_parse(p_url);
--       if cur.id is not null and cur.url = parsed[1] then
--         return public.ext_link_json(cur.id);
--       end if;
--       delete from public.ext_links where build_id = p_build;
--       insert into public.ext_links (owner_id, build_id, url, host, sort) values (me, p_build, parsed[1], parsed[2], 0)
--       returning * into cur;
--       return public.ext_link_json(cur.id);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.set_profile_links(p_urls text[])
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       lim integer := coalesce(public.xp_rule('influencer_profile_links_max'), 5);
--       parsed text[];
--       urls text[] := '{}';
--       hosts text[] := '{}';
--       i integer;
--     begin
--       if not exists (select 1 from public.profiles where id = me and influencer is not null) then
--         raise exception '인증된 장인만 링크를 올릴 수 있습니다.' using errcode = '42501';
--       end if;
--       if coalesce(cardinality(p_urls), 0) > 20 then
--         raise exception '프로필 링크는 %개까지 올릴 수 있습니다.', lim using errcode = '23514';
--       end if;
--       for i in 1 .. coalesce(cardinality(p_urls), 0) loop
--         if nullif(btrim(coalesce(p_urls[i], '')), '') is null then
--           continue;
--         end if;
--         parsed := public.ext_link_parse(p_urls[i]);
--         if parsed[1] = any (urls) then
--           raise exception '같은 주소를 두 번 올릴 수 없습니다.' using errcode = '23514';
--         end if;
--         urls := urls || parsed[1];
--         hosts := hosts || parsed[2];
--       end loop;
--       if cardinality(urls) > lim then
--         raise exception '프로필 링크는 %개까지 올릴 수 있습니다.', lim using errcode = '23514';
--       end if;
--       perform pg_advisory_xact_lock(hashtext('ext_links:' || me::text));
--       delete from public.ext_links where owner_id = me and build_id is null and not (url = any (urls));
--       for i in 1 .. cardinality(urls) loop
--         update public.ext_links set sort = i - 1, updated_at = now()
--          where owner_id = me and build_id is null and url = urls[i] and sort <> i - 1;
--         if not exists (select 1 from public.ext_links where owner_id = me and build_id is null and url = urls[i]) then
--           insert into public.ext_links (owner_id, build_id, url, host, sort) values (me, null, urls[i], hosts[i], i - 1);
--         end if;
--       end loop;
--       return coalesce((select jsonb_agg(public.ext_link_json(l.id) order by l.sort)
--                          from public.ext_links l where l.owner_id = me and l.build_id is null), '[]'::jsonb);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.set_profile_photo(p_path text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       p public.profiles%rowtype;
--       o record;
--       m text;
--       sz bigint;
--       daily integer := public.xp_rule('profile_photo_daily_max');
--     begin
--       select * into p from public.profiles where id = me for update;
--       if p.influencer is null or p.is_guest then
--         raise exception '인증된 장인만 프로필 사진을 올릴 수 있습니다.' using errcode = '42501';
--       end if;
--       if p_path is null or p_path !~ ('^' || me::text || '/[0-9A-Za-z_-]{1,64}\.(webp|jpg)$') then
--         raise exception '사진을 다시 골라 주세요.' using errcode = '22023';
--       end if;
--       if p_path = p.photo_path then
--         return;  -- 이미 이 사진
--       end if;
--       select ob.owner_id, ob.metadata into o from storage.objects ob where ob.bucket_id = 'profile-photos' and ob.name = p_path;
--       if not found or o.owner_id is distinct from me::text then
--         raise exception '올린 사진을 찾지 못했습니다. 사진을 다시 골라 주세요.' using errcode = '23514';
--       end if;
--       m := o.metadata ->> 'mimetype';
--       sz := coalesce((o.metadata ->> 'size')::bigint, 0);
--       if m is null or m not in ('image/webp', 'image/jpeg') or sz <= 0 or sz > 1048576 then
--         raise exception '사진 형식이나 크기가 맞지 않습니다. 다른 사진을 골라 주세요.' using errcode = '23514';
--       end if;
--       delete from public.profile_photo_changes where user_id = me and created_at < now() - interval '2 days';
--       if (select count(*) from public.profile_photo_changes where user_id = me and created_at > now() - interval '24 hours') >= daily then
--         raise exception '프로필 사진은 하루에 %번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily using errcode = '54000';
--       end if;
--       update public.profiles set photo_path = p_path, photo_updated_at = now() where id = me;
--       insert into public.profile_photo_changes (user_id) values (me);
--       delete from public.profile_photo_trash where path = p_path;  -- 혹시 대기열에 있던 내 파일을 다시 쓰면 지우지 않는다
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.vote_build(p_build_id bigint, p_value smallint)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--       b public.builds%rowtype;
--       cst text;
--       old_v smallint;
--     begin
--       if me is null then
--         raise exception '로그인이 필요합니다.' using errcode = '42501';
--       end if;
--       if not public.has_nickname() then
--         raise exception '닉네임을 정한 뒤에 투표할 수 있습니다.' using errcode = '42501';
--       end if;
--       if p_value is not null and p_value not in (1, -1) then
--         raise exception '투표 값이 잘못됐습니다.' using errcode = '23514';
--       end if;
--       select * into b from public.builds where id = p_build_id for update;
--       select status into cst from public.counters where id = b.counter_id;
--       if not found or b.status <> 'approved' or cst is distinct from 'approved' then
--         raise exception '공개된 빌드에만 투표할 수 있습니다.' using errcode = '23514';
--       end if;
--       if b.author_id = me then
--         raise exception '내 빌드에는 투표할 수 없습니다.' using errcode = '23514';
--       end if;
--
--       select value into old_v from public.build_votes where build_id = b.id and user_id = me;
--       if p_value is null then
--         delete from public.build_votes where build_id = b.id and user_id = me;
--       elsif old_v is null then
--         insert into public.build_votes (build_id, user_id, value) values (b.id, me, p_value);
--       elsif old_v <> p_value then
--         update public.build_votes set value = p_value where build_id = b.id and user_id = me;
--       end if;
--
--       if old_v is distinct from p_value then
--         insert into public.build_vote_log (build_id, counter_id, author_id, voter_id, old_value, new_value)
--         values (b.id, b.counter_id, b.author_id, me, old_v, p_value);
--         -- (6단계) 추천 받음 경험치(+2, 하루 상한)는 이 기록으로 계산
--       end if;
--
--       return (select jsonb_build_object('up', up_count, 'down', down_count, 'mine', p_value) from public.builds where id = b.id);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.vote_post(p_id bigint)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := public.board_writer();
--       p public.posts%rowtype := public.board_post_for_update(p_id);
--       mine boolean;
--     begin
--       if p.deleted_at is not null or p.status <> 'visible' then
--         raise exception '추천할 수 없는 글입니다.' using errcode = '23514';
--       end if;
--       if p.author_id = me then
--         raise exception '내 글은 추천할 수 없습니다.' using errcode = '23514';
--       end if;
--       delete from public.post_votes where post_id = p.id and user_id = me;
--       mine := not found;
--       if mine then
--         insert into public.post_votes (post_id, user_id) values (p.id, me);
--       end if;
--       update public.posts set up_count = (select count(*) from public.post_votes where post_id = p.id)
--       where id = p.id returning up_count into p.up_count;
--       return jsonb_build_object('up', p.up_count, 'mine', mine);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.media_upload_problem()
--      RETURNS text
--      LANGUAGE plpgsql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--       today integer;
--     begin
--       if me is null then
--         return '로그인해야 사진을 올릴 수 있습니다.';
--       end if;
--       if not public.has_nickname() then
--         return '닉네임을 정해야 사진을 올릴 수 있습니다.';
--       end if;
--       if public.is_guest(me) then
--         return '비회원은 사진을 올릴 수 없습니다. 구글·카카오를 연결하면 할 수 있습니다.';
--       end if;
--       if public.media_used_bytes() >= public.xp_rule('media_block_mb')::bigint * 1024 * 1024 then
--         return '지금은 사진 저장 공간이 거의 차서 사진을 올릴 수 없습니다. 글은 그대로 쓸 수 있습니다.';
--       end if;
--       select count(*) into today from storage.objects o
--        where o.bucket_id = 'board-media' and o.owner_id = me::text and o.created_at > now() - interval '24 hours';
--       if today >= public.xp_rule('media_daily_max') then
--         return format('사진은 하루에 %s개까지 올릴 수 있습니다. 내일 다시 해 주세요.', public.xp_rule('media_daily_max'));
--       end if;
--       return null;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.profile_photo_upload_problem()
--      RETURNS text
--      LANGUAGE plpgsql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--       daily integer := public.xp_rule('profile_photo_daily_max');
--     begin
--       if me is null then
--         return '로그인해야 프로필 사진을 올릴 수 있습니다.';
--       end if;
--       if not exists (select 1 from public.profiles p where p.id = me and p.nickname is not null and not p.is_guest
--                        and (p.influencer is not null
--                             or exists (select 1 from public.influencer_applications a where a.user_id = me and a.status = 'pending'))) then
--         return '인증된 장인이나 장인 인증을 신청한 회원만 프로필 사진을 올릴 수 있습니다.';
--       end if;
--       if (select count(*) from storage.objects o where o.bucket_id = 'profile-photos' and o.owner_id = me::text) >= 5 then
--         return '올려 두고 쓰지 않은 사진이 많습니다. 하루 뒤 다시 시도해 주세요.';
--       end if;
--       if (select count(*) from public.profile_photo_changes c where c.user_id = me and c.created_at > now() - interval '24 hours') >= daily then
--         return format('프로필 사진은 하루에 %s번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily);
--       end if;
--       return null;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.set_moderator(p_user uuid, p_on boolean, p_note text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       note text;
--       u public.profiles%rowtype;
--     begin
--       perform public.require_operator();
--       note := public.require_note(p_note, '메모');
--       select * into u from public.profiles where id = p_user for update;
--       if not found then
--         raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if u.role = 'admin' then
--         raise exception '운영자는 감독관으로 바꿀 수 없습니다.' using errcode = '23514';
--       end if;
--       if p_on then
--         if u.role = 'moderator' then
--           raise exception '이미 감독관입니다.' using errcode = '23514';
--         end if;
--         if u.nickname is null or u.is_guest then
--           raise exception '닉네임을 정한 정식 회원만 감독관으로 지정할 수 있습니다.' using errcode = '23514';
--         end if;
--         update public.profiles set role = 'moderator' where id = u.id;
--         perform public.notify(u.id, 'moderator_granted',
--           format('감독관으로 지정됐습니다. 처리 기록은 탈퇴 후에도 남습니다. 메모: %s', note), null, null);
--       else
--         if u.role <> 'moderator' then
--           raise exception '감독관이 아닙니다.' using errcode = '23514';
--         end if;
--         update public.profiles set role = 'user' where id = u.id;
--         perform public.notify(u.id, 'moderator_revoked', format('감독관에서 해제됐습니다. 메모: %s', note), null, null);
--       end if;
--       perform public.log_moderation(case when p_on then 'grant_moderator' else 'revoke_moderator' end,
--         'user', u.id::text, note, u.nickname);
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.create_inquiry(p_category text, p_body text)
--      RETURNS bigint
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--       text_body text := btrim(coalesce(p_body, ''), E' \t\r\n');
--       len integer := char_length(btrim(coalesce(p_body, ''), E' \t\r\n'));
--       min_len integer := public.xp_rule('inquiry_min');
--       max_len integer := public.xp_rule('inquiry_max');
--       daily integer := public.xp_rule('inquiry_daily_max');
--       today date := (now() at time zone 'Asia/Seoul')::date;
--       q public.inquiry_quota%rowtype;
--       new_id bigint;
--     begin
--       if me is null then
--         raise exception '로그인해 주세요.' using errcode = '42501';
--       end if;
--       if p_category is null or p_category not in ('bug', 'idea', 'account', 'other') then
--         raise exception '분류를 골라 주세요.' using errcode = '22023';
--       end if;
--       if len < min_len then
--         raise exception '내용을 %자 이상 적어 주세요.', min_len using errcode = '22023';
--       end if;
--       if len > max_len then
--         raise exception '내용은 %자까지 적을 수 있습니다.', max_len using errcode = '22023';
--       end if;
--       perform 1 from public.profiles where id = me for update;  -- 같은 사람의 동시 요청을 한 줄로
--       if not found then
--         raise exception '로그인해 주세요.' using errcode = '42501';
--       end if;
--       select * into q from public.inquiry_quota where user_id = me;
--       if not found then
--         insert into public.inquiry_quota (user_id, day, sent) values (me, today, 0);
--         q.day := today; q.sent := 0;
--       elsif q.day <> today then
--         q.day := today; q.sent := 0;
--       end if;
--       if q.sent >= daily then
--         raise exception '문의는 하루에 %건까지 보낼 수 있습니다. 내일 다시 보내 주세요.', daily using errcode = 'P0001';
--       end if;
--       update public.inquiry_quota set day = today, sent = q.sent + 1 where user_id = me;
--       insert into public.inquiries (user_id, category, body) values (me, p_category, text_body) returning id into new_id;
--       return new_id;
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.set_inquiry_category(p_id bigint, p_category text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       i public.inquiries%rowtype;
--     begin
--       perform public.require_operator();
--       if p_category is null or p_category not in ('bug', 'idea', 'account', 'other') then
--         raise exception '분류를 골라 주세요.' using errcode = '22023';
--       end if;
--       select * into i from public.inquiries where id = p_id for update;
--       if not found then
--         raise exception '문의를 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if i.category = p_category then
--         raise exception '이미 같은 분류입니다.' using errcode = '23514';
--       end if;
--       update public.inquiries set category = p_category where id = i.id;
--       perform public.log_moderation('move_inquiry', 'inquiry', i.id::text,
--         format('%s → %s', public.inquiry_category_label(i.category), public.inquiry_category_label(p_category)));
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.inquiry_category_label(p_category text)
--      RETURNS text
--      LANGUAGE sql
--      IMMUTABLE
--      SET search_path TO ''
--     AS $function$
--       select case p_category when 'bug' then '오류 신고' when 'idea' then '건의' when 'account' then '계정·탈퇴' else '기타' end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.answer_inquiry(p_id bigint, p_answer text)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--       ans text := btrim(coalesce(p_answer, ''), E' \t\r\n');
--       max_len integer := public.xp_rule('inquiry_answer_max');
--       i public.inquiries%rowtype;
--     begin
--       perform public.require_staff();
--       select * into i from public.inquiries where id = p_id for update;
--       if not found then
--         raise exception '문의를 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if i.answer is not null then
--         raise exception '이미 다른 분이 처리했습니다.' using errcode = 'TL409';
--       end if;
--       if i.user_id = me then
--         raise exception '본인이 보낸 문의에는 답변할 수 없습니다.' using errcode = '42501';
--       end if;
--       if i.category = 'account' and public.is_moderator() then  -- require_staff를 지났으니 운영자가 아니면 감독관
--         raise exception '"계정·탈퇴" 문의는 운영자만 답변할 수 있습니다.' using errcode = '42501';
--       end if;
--       if ans = '' then
--         raise exception '답변을 적어 주세요.' using errcode = '22023';
--       end if;
--       if char_length(ans) > max_len then
--         raise exception '답변은 %자까지 적을 수 있습니다.', max_len using errcode = '22023';
--       end if;
--       update public.inquiries set answer = ans, answered_at = now() where id = i.id;
--       perform public.notify(i.user_id, 'inquiry_answered',
--         format('"%s" 문의에 답변이 도착했습니다.', public.inquiry_category_label(i.category)), null, null);
--       perform public.log_moderation('answer_inquiry', 'inquiry', i.id::text, null);  -- 문의 내용은 기록에 넣지 않는다
--     end;
--     $function$;
--
--     CREATE OR REPLACE FUNCTION public.notify_staff_new_inquiry()
--      RETURNS trigger
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     begin
--       if tg_op = 'UPDATE' then
--         -- 운영자가 분류를 옮겨서 감독관에게 보이게 됐을 때 (계정·탈퇴 → 다른 분류), 아직 답이 없을 때만
--         if new.answer is not null or old.category <> 'account' or new.category = 'account' then
--           return null;
--         end if;
--         insert into public.notifications (user_id, kind, message)
--         select u.id, 'inquiry_received',
--                format('새 문의가 들어왔습니다. (분류: %s)', public.inquiry_category_label(new.category))
--           from public.profiles u
--          where u.role = 'moderator' and u.id is distinct from new.user_id;
--         return null;
--       end if;
--       insert into public.notifications (user_id, kind, message)
--       select u.id, 'inquiry_received',
--              format('새 문의가 들어왔습니다. (분류: %s)', public.inquiry_category_label(new.category))
--         from public.profiles u
--        where (u.role = 'admin' or (u.role = 'moderator' and new.category <> 'account'))
--          and u.id is distinct from new.user_id;
--       return null;
--     end;
--     $function$;
--     -- 4) 068이 만든 함수·표
--     drop function public.restriction_guard();
--     drop function public.admin_member_restrictions(uuid);
--     drop function public.lift_restriction(bigint, text);
--     drop function public.restrict_user(uuid, integer, text);
--     drop function public.my_restriction();
--     drop function public.can_write();
--     drop function public.assert_can_write();
--     drop function public.restriction_message(uuid);
--     drop function public.active_restriction_id(uuid);
--     drop table public.restriction_exemptions;
--     drop table public.user_restrictions;
--     commit;
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 활동 제한 기록 표 (탈퇴하면 함께 지워진다 - 2026-11-22 결정)
-- ---------------------------------------------------------------------
create table public.user_restrictions (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,      -- 제한 받는 사람 (탈퇴 → 기록 삭제)
  reason     text not null check (char_length(btrim(reason)) between 1 and 500),   -- 사유 (본인에게 그대로 보인다)
  days       integer not null check (days between 1 and 365),                      -- 건 기간 (일)
  starts_at  timestamptz not null default now(),
  ends_at    timestamptz not null,                                                 -- 이 시각부터 저절로 풀림 (cron 없음)
  created_by uuid references public.profiles (id) on delete set null,              -- 건 운영자
  lifted_at  timestamptz,                                                          -- 운영자가 직접 푼 시각
  lifted_by  uuid references public.profiles (id) on delete set null,
  lift_note  text check (lift_note is null or char_length(lift_note) <= 500),
  check (ends_at > starts_at),
  check (lifted_at is not null or (lifted_by is null and lift_note is null))
);
comment on table public.user_restrictions is '068 활동 제한 기록. 운영자만 건다(restrict_user). ends_at이 지나거나 lifted_at이 있으면 풀린 것. 본인·운영자만 읽는다. 탈퇴하면 지워진다';
create index user_restrictions_user_idx on public.user_restrictions (user_id, ends_at desc);
create index user_restrictions_created_by_idx on public.user_restrictions (created_by);
create index user_restrictions_lifted_by_idx on public.user_restrictions (lifted_by);
alter table public.user_restrictions enable row level security;
revoke all on public.user_restrictions from public, anon, authenticated;
grant select on public.user_restrictions to authenticated;
create policy "user_restrictions: 본인·운영자 읽기" on public.user_restrictions
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());

-- ---------------------------------------------------------------------
-- 2. 지금 걸려 있는 제한 · 문장 · 검사
-- ---------------------------------------------------------------------
-- 지금 걸려 있는 제한 번호 (없으면 null). 이미 걸린 제한이 있으면 새로 못 걸므로 한 사람에게 하나뿐이다
create function public.active_restriction_id(p_user uuid)
returns bigint language sql stable security definer set search_path = ''
as $$
  select r.id from public.user_restrictions r
   where r.user_id = p_user and r.lifted_at is null and r.ends_at > now()
   order by r.ends_at desc limit 1;
$$;

-- 제한 중이면 「활동이 제한된 상태입니다. 2026-12-01 15:21에 풀립니다. 사유: …」, 아니면 null (시각은 한국 시각)
create function public.restriction_message(p_user uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select '활동이 제한된 상태입니다. '
         || to_char(r.ends_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') || '에 풀립니다. 사유: ' || r.reason
    from public.user_restrictions r
   where r.id = public.active_restriction_id(p_user);
$$;

-- 쓰기 함수 맨 앞 검사: 제한 중이면 위 문장으로 멈춘다(오류 코드 TL423). 아니면 true.
-- 로그인하지 않은 호출(서버 작업 포함)은 여기서 막지 않는다 - 로그인 검사는 각 함수가 따로 한다.
create function public.assert_can_write()
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare
  m text := public.restriction_message((select auth.uid()));
begin
  if m is not null then
    raise exception '%', m using errcode = 'TL423';
  end if;
  return true;
end;
$$;

-- RLS 정책용 (직접 넣기 경로 - 빌드·제안): 제한 중이 아니면 true
create function public.can_write()
returns boolean language sql stable security definer set search_path = ''
as $$
  select (select auth.uid()) is null or public.active_restriction_id((select auth.uid())) is null;
$$;

-- 화면 띠: 내 제한 (없으면 null) { id, reason, ends_at, message }
create function public.my_restriction()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('id', r.id, 'reason', r.reason, 'ends_at', r.ends_at,
                            'message', public.restriction_message(r.user_id))
    from public.user_restrictions r
   where r.id = public.active_restriction_id((select auth.uid()));
$$;

-- ---------------------------------------------------------------------
-- 3. 운영자: 걸기 · 풀기 · 기록 보기
-- ---------------------------------------------------------------------
create function public.restrict_user(p_user uuid, p_days integer, p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  reason text := btrim(coalesce(p_reason, ''), E' \t\r\n');
  u public.profiles%rowtype;
  cur bigint;
  r public.user_restrictions%rowtype;
begin
  perform public.require_operator();
  if reason = '' then
    raise exception '제한 사유를 적어 주세요.' using errcode = '22023';
  end if;
  if char_length(reason) > 500 then
    raise exception '사유는 500자까지 적을 수 있습니다.' using errcode = '22023';
  end if;
  if p_days is null or p_days < 1 or p_days > 365 then
    raise exception '기간은 1일부터 365일까지 정할 수 있습니다.' using errcode = '22023';
  end if;
  select * into u from public.profiles where id = p_user for update;  -- 같은 사람에게 동시에 두 번 걸지 않게
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if u.id = me then
    raise exception '자기 자신에게는 활동 제한을 걸 수 없습니다.' using errcode = '42501';
  end if;
  if u.role = 'admin' then
    raise exception '운영자에게는 활동 제한을 걸 수 없습니다.' using errcode = '42501';
  end if;
  if u.role = 'moderator' then
    raise exception '감독관에게는 활동 제한을 걸 수 없습니다. 먼저 감독관에서 해제해 주세요.' using errcode = '42501';
  end if;
  cur := public.active_restriction_id(u.id);
  if cur is not null then
    raise exception '이미 활동 제한 중입니다(%까지). 기간을 바꾸려면 먼저 해제한 뒤 다시 걸어 주세요.',
      (select to_char(x.ends_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') from public.user_restrictions x where x.id = cur)
      using errcode = 'TL409';
  end if;
  -- 풀리는 시각은 분 단위로 올림 (화면에 보이는 시각이 되면 바로 풀린다)
  insert into public.user_restrictions (user_id, reason, days, ends_at, created_by)
  values (u.id, reason, p_days, date_trunc('minute', now() + make_interval(days => p_days)) + interval '1 minute', me)
  returning * into r;
  -- 처리 기록에는 기간만 (사유는 탈퇴 때 함께 지워지도록 제한 기록에만 둔다)
  perform public.log_moderation('restrict_user', 'user', u.id::text, format('%s일', p_days), u.nickname);
  return jsonb_build_object('id', r.id, 'ends_at', r.ends_at);
end;
$$;

create function public.lift_restriction(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text := nullif(btrim(coalesce(p_note, ''), E' \t\r\n'), '');
  r public.user_restrictions%rowtype;
begin
  perform public.require_operator();
  if char_length(note) > 500 then
    raise exception '메모는 500자까지 적을 수 있습니다.' using errcode = '22023';
  end if;
  select * into r from public.user_restrictions where id = p_id for update;
  if not found then
    raise exception '제한 기록을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if r.lifted_at is not null then
    raise exception '이미 해제된 제한입니다.' using errcode = 'TL409';
  end if;
  if r.ends_at <= now() then
    raise exception '이미 기간이 끝나 풀린 제한입니다.' using errcode = 'TL409';
  end if;
  update public.user_restrictions set lifted_at = now(), lifted_by = (select auth.uid()), lift_note = note where id = r.id;
  perform public.log_moderation('lift_restriction', 'user', r.user_id::text, null,
    (select p.nickname from public.profiles p where p.id = r.user_id));
end;
$$;

-- 회원 관리 화면: 그 회원의 제한 기록 (최근 것부터)
create function public.admin_member_restrictions(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'reason', r.reason, 'days', r.days, 'starts_at', r.starts_at, 'ends_at', r.ends_at,
             'created_by', c.nickname, 'lifted_at', r.lifted_at, 'lifted_by', l.nickname, 'lift_note', r.lift_note,
             'state', case when r.lifted_at is not null then 'lifted' when r.ends_at <= now() then 'ended' else 'active' end)
           order by r.id desc)
      from public.user_restrictions r
      left join public.profiles c on c.id = r.created_by
      left join public.profiles l on l.id = r.lifted_by
     where r.user_id = p_user), '[]'::jsonb);
end;
$$;

alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action in (
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report',
  'dismiss_report', 'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
  'remove_link', 'add_link_domain', 'remove_link_domain', 'grant_influencer', 'grant_title', 'revoke_title',
  'remove_profile_photo',
  'restrict_user', 'lift_restriction'));

-- ---------------------------------------------------------------------
-- 4. 둘째 겹: 표 트리거 (쓰기 함수가 검사를 빠뜨려도 여기서 막힌다)
--    누가: 지금 로그인한 사람(auth.uid())이 제한 중일 때만. 서버 작업(로그인 없음)·운영자·다른 사람의 일은 막지 않는다
--      → 운영자가 제한된 사람의 빌드를 숨기거나, 남이 그 사람 빌드에 추천하면 그대로 된다.
--    무엇을: 새 줄 넣기, 그리고 인자로 준 "내용 칸"이 바뀌는 고치기. 지우기(DELETE)는 막지 않는다(내 글 지우기·팔로우 취소·탈퇴).
--      칸 이름 끝 '?' = 그 칸을 비우는(null) 것은 막지 않음 (사진 지우기, 대표 칭호 빼기)
--      deleted_at이 있는 줄(지운 글·댓글, 탈퇴 껍데기)로 바뀌는 고치기는 막지 않는다
--    트리거 이름 a_restriction(_edit): before 트리거는 이름순으로 돌므로 입력 검사 트리거보다 먼저 제한 문장이 나온다
-- ---------------------------------------------------------------------
create function public.restriction_guard()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  nj jsonb;
  oj jsonb;
  col text;
  changed boolean := false;
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    nj := to_jsonb(new);
    oj := to_jsonb(old);
    if nj ? 'deleted_at' and nj ->> 'deleted_at' is not null then
      return new;
    end if;
    foreach col in array tg_argv loop
      if right(col, 1) = '?' then
        col := left(col, -1);
        if nj -> col is distinct from oj -> col and nj -> col <> 'null'::jsonb then
          changed := true;
        end if;
      elsif nj -> col is distinct from oj -> col then
        changed := true;
      end if;
    end loop;
    if not changed then
      return new;
    end if;
  end if;
  perform public.assert_can_write();
  return new;
end;
$$;

create trigger a_restriction before insert on public.builds
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of runes, summoner_spells, starting_items, core_items, patch, max_skill,
  name, summary, level_notes, lane_cautions, skill_sequence on public.builds
  for each row execute function public.restriction_guard('runes', 'summoner_spells', 'starting_items', 'core_items', 'patch',
    'max_skill', 'name', 'summary', 'level_notes', 'lane_cautions', 'skill_sequence');
create trigger a_restriction before insert on public.build_revisions
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.counters
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.matchup_docs
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of level_notes, lane_cautions, summary on public.matchup_docs
  for each row execute function public.restriction_guard('level_notes', 'lane_cautions', 'summary');
create trigger a_restriction before insert on public.edit_proposals
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of content, build on public.edit_proposals
  for each row execute function public.restriction_guard('content', 'build');
create trigger a_restriction before insert on public.posts
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of title, body on public.posts
  for each row execute function public.restriction_guard('title', 'body');
create trigger a_restriction before insert on public.post_comments
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of body on public.post_comments
  for each row execute function public.restriction_guard('body');
create trigger a_restriction before insert on public.doc_comments
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of body on public.doc_comments
  for each row execute function public.restriction_guard('body');
create trigger a_restriction before insert on public.board_attachments
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.build_votes
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of value on public.build_votes
  for each row execute function public.restriction_guard('value');
create trigger a_restriction before insert on public.post_votes
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.reports
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.wiki_reports
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.link_reports
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.profile_photo_reports
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.influencer_follows
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.build_bookmarks
  for each row execute function public.restriction_guard();
create trigger a_restriction before insert on public.influencer_applications
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of photo_path on public.influencer_applications
  for each row execute function public.restriction_guard('photo_path?');
create trigger a_restriction before insert on public.ext_links
  for each row execute function public.restriction_guard();
create trigger a_restriction_edit before update of url on public.ext_links
  for each row execute function public.restriction_guard('url');
create trigger a_restriction_edit before update of nickname, main_title, photo_path on public.profiles
  for each row execute function public.restriction_guard('nickname', 'main_title?', 'photo_path?');

-- 직접 넣기 경로(옛 승인 흐름의 빌드 등록, 제안 보내기)의 RLS 정책에도 한 겹 (트리거가 먼저 한국어 문장으로 막는다)
alter policy "builds: 본인 이름으로 대기 빌드 등록" on public.builds
  with check (author_id = (select auth.uid()) and public.has_nickname() and status = 'pending'
              and reviewed_by is null and reviewed_at is null and reject_reason is null and up_count = 0 and down_count = 0
              and public.can_write());
alter policy "edit_proposals: 본인 이름으로 대기 제안 작성" on public.edit_proposals
  with check (proposer_id = (select auth.uid()) and public.has_nickname() and status = 'pending'
              and reviewed_by is null and reviewed_at is null and reject_reason is null
              and public.can_write());

-- ---------------------------------------------------------------------
-- 5. 문의 분류 「이의 제기」(appeal) - 계정·탈퇴처럼 운영자만 읽고 답한다 (감독관 제외)
-- ---------------------------------------------------------------------
alter table public.inquiries drop constraint inquiries_category_check;
alter table public.inquiries add constraint inquiries_category_check check (category in ('bug', 'idea', 'account', 'appeal', 'other'));
alter policy "inquiries: 본인·운영진 읽기" on public.inquiries
  using (user_id = (select auth.uid()) or public.is_admin() or (public.is_moderator() and category not in ('account', 'appeal')));
drop trigger inquiries_notify_staff_move on public.inquiries;
create trigger inquiries_notify_staff_move after update of category on public.inquiries
  for each row when (old.category in ('account', 'appeal') and new.category not in ('account', 'appeal'))
  execute function public.notify_staff_new_inquiry();

-- ---------------------------------------------------------------------
-- 6. 기존 함수 다시 정의 (067 DB의 pg_get_functiondef 그대로 + 표시한 줄만 다름)
--    6-1. 일반 사용자 쓰기 함수 29개: 선언부 첫 줄에 assert_can_write()
-- ---------------------------------------------------------------------

-- apply_influencer(text, text, text, text, text, text)
CREATE OR REPLACE FUNCTION public.apply_influencer(p_kind text, p_nickname text, p_channel_url text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_riot_id text DEFAULT NULL::text, p_opgg_url text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();  -- 로그인 + 닉네임
  prof public.profiles;
  nick text := btrim(coalesce(p_nickname, ''));
  k text;
  chan text := nullif(btrim(coalesce(p_channel_url, '')), '');
  mail text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  riot text := nullif(regexp_replace(btrim(coalesce(p_riot_id, '')), '\s*#\s*', '#'), '');
  opgg text := nullif(btrim(coalesce(p_opgg_url, '')), '');
  days integer := coalesce(public.xp_rule('influencer_review_days'), 14);
  next_at timestamptz;
  holder public.profiles;
  aid bigint;
begin
  select * into prof from public.profiles where id = me for update;
  if prof.is_guest then
    raise exception E'장인 인증은 구글\u00B7카카오로 로그인한 회원만 신청할 수 있습니다.' using errcode = '42501';
  end if;
  if prof.role = 'admin' then
    raise exception '운영자 계정은 장인 인증을 신청할 수 없습니다.' using errcode = '42501';
  end if;
  if prof.influencer is not null then
    raise exception '이미 인증된 장인입니다.' using errcode = '23514';
  end if;
  if exists (select 1 from public.influencer_applications where user_id = me and status = 'pending') then
    raise exception '이미 심사 중인 신청이 있습니다.' using errcode = '23514';
  end if;
  if prof.nickname_state = 'yielding' then
    raise exception '지금 닉네임은 바뀔 예정입니다. 먼저 새 닉네임을 정한 뒤 신청해 주세요.' using errcode = '23514';
  end if;
  next_at := public.influencer_next_apply_at(me);
  if next_at is not null then
    raise exception '장인 인증은 %부터 다시 신청할 수 있습니다.',
      to_char(next_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') using errcode = 'P0001';
  end if;
  if p_kind is null or p_kind not in ('creator', 'pro', 'grandmaster') then
    raise exception '유형을 골라 주세요.' using errcode = '22023';
  end if;
  if char_length(nick) not between 1 and 20 then
    raise exception '희망 닉네임은 1~20자로 적어 주세요.' using errcode = '22023';
  end if;

  if p_kind in ('creator', 'pro') then
    if chan is null or char_length(chan) > 300 or chan !~* '^https?://[^\s/]+\.[^\s]+$' then
      raise exception E'채널\u00B7방송 링크를 https://로 시작하는 주소로 적어 주세요.' using errcode = '22023';
    end if;
    if mail is null or char_length(mail) > 254 or mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception '공식 이메일을 적어 주세요. (채널 소개란이나 팀 공식 페이지에 공개된 이메일)' using errcode = '22023';
    end if;
    riot := null;
    opgg := null;
    if exists (select 1 from public.influencer_applications
                where channel_key = public.influencer_channel_key(chan) and status in ('pending', 'approved')) then
      raise exception '이미 신청됐거나 인증된 채널입니다. 본인의 채널이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
    end if;
  else
    if riot is null or riot !~ '^[^#]{3,16}#[^#\s]{3,5}$' then
      raise exception '라이엇 닉네임#태그를 적어 주세요. (예: 닉네임#KR1)' using errcode = '22023';
    end if;
    if opgg is null or char_length(opgg) > 300 or opgg !~* '^https?://([a-z0-9-]+\.)*op\.gg(/\S*)?$' then
      raise exception E'op.gg 링크를 적어 주세요. (https://op.gg/\u2026)' using errcode = '22023';
    end if;
    chan := null;
    mail := null;
    if exists (select 1 from public.influencer_applications
                where riot_key = public.influencer_riot_key(riot) and status in ('pending', 'approved')) then
      raise exception '이미 신청됐거나 인증된 라이엇 닉네임입니다. 본인의 계정이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
    end if;
  end if;

  -- 희망 닉네임: 다른 보통 회원 1명과만 겹칠 수 있다 (승인되면 그 회원이 3일 유예 뒤 임시 닉네임으로)
  k := public.nickname_key(nick);
  perform pg_advisory_xact_lock(hashtext('nickname_key:' || k));
  if exists (select 1 from public.profiles o where o.nickname_key = k and o.id <> me and o.nickname_state = 'pending') then
    raise exception '이미 장인 인증을 신청 중인 닉네임입니다. 본인의 닉네임이라면 [문의하기]로 알려 주세요.' using errcode = '23505';
  end if;
  select * into holder from public.profiles o where o.nickname_key = k and o.id <> me limit 1;
  if found and (holder.influencer is not null or holder.nickname_state = 'yielding') then
    raise exception '이미 인증된 장인이 쓰는 닉네임입니다.' using errcode = '23505';
  end if;
  if found and holder.role <> 'user' then
    raise exception '운영진이 쓰는 닉네임이라 신청할 수 없습니다.' using errcode = '23505';
  end if;

  insert into public.influencer_applications
    (user_id, kind, nickname, old_nickname, channel_url, channel_key, official_email, riot_id, riot_key, opgg_url, expires_at)
  values (me, p_kind, nick, prof.nickname, chan, public.influencer_channel_key(chan), mail, riot,
          case when riot is not null then public.influencer_riot_key(riot) end, opgg, now() + make_interval(days => days))
  returning id into aid;

  -- 닉네임을 희망 닉네임으로 + 인증 대기 (사칭 금지 검사는 트리거가 그대로 한다)
  perform public.system_set_nickname(me, nick, 'pending', null, 'apply');

  -- 신청자에게 접수 알림 (본인 알림이라 notify()를 거치지 않음), 운영자에게 새 신청 알림
  insert into public.notifications (user_id, kind, message)
  values (me, 'influencer_received', case when p_kind = 'grandmaster'
    then format('신청이 접수됐습니다. %s일 안에 운영자 계정 {운영자 닉네임}으로 친구 요청을 보내 주세요. '
                '요청이 도착하면 이 닉네임의 주인이 맞는지 확인합니다. 수락은 하지 않습니다.', days)
    else format('신청이 접수됐습니다. 적어 주신 공식 이메일로 확인 메일을 보냅니다. %s일 안에 "본인입니다"라고 회신해 주세요.', days) end);
  insert into public.notifications (user_id, kind, message)
  select u.id, 'influencer_applied', format(E'장인 인증 신청이 들어왔습니다. (%s \u00B7 %s)', nick, public.influencer_kind_label(p_kind))
    from public.profiles u where u.role = 'admin' and u.id <> me;
  return aid;
end;
$function$;

-- begin_edit(text, bigint)
CREATE OR REPLACE FUNCTION public.begin_edit(p_kind text, p_id bigint)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
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

-- create_build(bigint, jsonb)
CREATE OR REPLACE FUNCTION public.create_build(p_counter bigint, p_build jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  c jsonb := public.clean_wiki_build(p_build);
  bid bigint;
begin
  if not exists (select 1 from public.counters where id = p_counter and status = 'approved') then
    raise exception '빌드를 등록할 상대법을 찾지 못했습니다.' using errcode = '23514';
  end if;
  perform public.wiki_throttle('create');
  bid := public.wiki_insert_build(p_counter, me, c);
  perform public.notify_admins_wiki('build_created', '새 빌드가 등록됐습니다.', p_counter, bid);
  return bid;
end;
$function$;

-- create_comment(bigint, text, text[], bigint)
CREATE OR REPLACE FUNCTION public.create_comment(p_post bigint, p_body text, p_media text[] DEFAULT '{}'::text[], p_parent bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  b text := public.board_text_or_empty(p_body, '댓글', 1000, cardinality(coalesce(p_media, '{}')) > 0);
  p public.posts%rowtype;
  par public.post_comments%rowtype;
  new_id bigint;
begin
  if public.is_guest(me) then
    raise exception '비회원은 댓글을 달 수 없습니다. 구글·카카오를 연결하면 달 수 있습니다.' using errcode = '42501';
  end if;
  select * into p from public.posts where id = p_post;
  if not found or p.status <> 'visible' then
    raise exception '글을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if p.deleted_at is not null then
    raise exception '삭제된 글에는 댓글을 달 수 없습니다.' using errcode = '23514';
  end if;
  if p_parent is not null then
    select * into par from public.post_comments where id = p_parent;
    if not found or par.post_id <> p.id or par.deleted_at is not null or par.status <> 'visible' then
      raise exception '답글을 달 댓글을 찾지 못했습니다. (지워졌거나 숨겨졌을 수 있습니다)' using errcode = 'P0002';
    end if;
    if par.parent_id is not null then
      raise exception '답글에는 답글을 달 수 없습니다. (댓글은 2단계까지)' using errcode = '23514';
    end if;
  end if;
  perform public.board_throttle(me, 'comment');
  insert into public.post_comments (post_id, author_id, body, parent_id) values (p.id, me, b, p_parent) returning id into new_id;
  perform public.media_set(null, new_id, me, p_media);
  perform public.notify_new_comment('post', p.id, p.author_id, par.author_id, p_parent is not null);
  return new_id;
end;
$function$;

-- create_doc_comment(bigint, text, bigint)
CREATE OR REPLACE FUNCTION public.create_doc_comment(p_counter bigint, p_body text, p_parent bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
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
$function$;

-- create_matchup(text, text, jsonb)
CREATE OR REPLACE FUNCTION public.create_matchup(p_target text, p_mine text, p_build jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();  -- 로그인 + 닉네임 (비회원 가능)
  c jsonb := public.clean_wiki_build(p_build);
  st text;
  cid bigint;
  bid bigint;
begin
  if coalesce(p_target, '') !~ '^[A-Za-z]{1,30}$' or coalesce(p_mine, '') !~ '^[A-Za-z]{1,30}$' then
    raise exception '챔피언을 다시 골라 주세요.' using errcode = '23514';
  end if;
  if p_target = p_mine then
    raise exception '같은 챔피언끼리는 상대법을 만들 수 없습니다.' using errcode = '23514';
  end if;
  select status into st from public.counters where target_champion = p_target and counter_champion = p_mine;
  if st = 'approved' then
    raise exception '이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.' using errcode = '23505';
  elsif st is not null then
    raise exception '운영진이 숨긴 상대법이라 새로 등록할 수 없습니다.' using errcode = '23514';
  end if;
  perform public.wiki_throttle('create');

  begin
    insert into public.counters (target_champion, counter_champion, sort_order, status, proposed_by, wiki)
    values (p_target, p_mine,
            (select coalesce(max(sort_order), 0) + 1 from public.counters where target_champion = p_target),
            'approved', me, true)
    returning id into cid;
  exception when unique_violation then
    raise exception '이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.' using errcode = '23505';
  end;
  -- 옛 화면용 사본 (PWA에 남은 옛 상대법 화면·챔피언 목록이 내용을 보여 주게). 이후 빌드 수정은 반영하지 않는다
  insert into public.matchup_docs (counter_id, summary, level_notes, lane_cautions, updated_by)
  values (cid, c ->> 'summary', c -> 'level_notes', c ->> 'lane_cautions', me);
  bid := public.wiki_insert_build(cid, me, c);
  update public.counters set first_build_id = bid where id = cid;
  perform public.notify_admins_wiki('matchup_created', '새 상대법이 등록됐습니다.', cid, bid);
  return jsonb_build_object('counter_id', cid, 'build_id', bid);
end;
$function$;

-- create_post(text, text, text[])
CREATE OR REPLACE FUNCTION public.create_post(p_title text, p_body text, p_media text[] DEFAULT '{}'::text[])
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
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
$function$;

-- edit_build(bigint, integer, jsonb)
CREATE OR REPLACE FUNCTION public.edit_build(p_id bigint, p_version integer, p_build jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  b public.builds;
  nb public.builds;
  c jsonb;
  before jsonb;
  same_build boolean;
begin
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  perform public.build_edit_check(b, me);  -- 043: 공개 여부·비회원 규칙 (잠금이 들어올 자리)
  if p_version is distinct from b.version then
    raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
  end if;
  c := public.clean_wiki_build(p_build);
  if not (p_build ? 'skill_sequence') then  -- 065: 옛 앱은 이 칸을 모른다 -> 지우지 않고 그대로
    c := c || jsonb_build_object('skill_sequence', b.skill_sequence);
  end if;
  if (c ->> 'skill_sequence') is distinct from b.skill_sequence then
    perform public.check_skill_sequence(c ->> 'skill_sequence', b.counter_id);
  end if;
  before := public.wiki_snapshot(b);
  if c - 'patch' = before - 'patch' then
    raise exception '바뀐 내용이 없습니다.' using errcode = '23514';
  end if;
  same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' - 'skill_sequence' = public.build_signature(b);
  if not same_build and exists (
    select 1 from public.builds x
     where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
       and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' - 'skill_sequence'
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있습니다. 그 빌드를 추천해 주세요.' using errcode = '23514';
  end if;
  perform public.wiki_throttle('edit');

  update public.builds
     set runes = c -> 'runes',
         summoner_spells = array(select jsonb_array_elements_text(c -> 'summoner_spells')),
         starting_items = array(select jsonb_array_elements_text(c -> 'starting_items')),
         core_items = array(select jsonb_array_elements_text(c -> 'core_items')),
         max_skill = c ->> 'max_skill',
         patch = case when same_build then b.patch else c ->> 'patch' end,  -- 글·스킬 순서만 고치면 패치 그대로
         name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
         skill_sequence = c ->> 'skill_sequence',
         version = b.version + 1, updated_at = now(), updated_by = me
   where id = b.id
   returning * into nb;  -- 핵심 템트리·강타·시작 골드는 바뀐 칸만 트리거가 검사
  insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
  values (b.id, b.counter_id, me, 'edit', before, public.wiki_snapshot(nb), nb.version);
  if me is distinct from b.author_id then
    insert into public.build_editors (build_id, user_id) values (b.id, me)
    on conflict (build_id, user_id) do update set last_at = now(), edits = public.build_editors.edits + 1;
  end if;
  return nb.version;  -- 수정마다 알림은 보내지 않는다. 경험치도 없다
end;
$function$;

-- edit_comment(bigint, text, text[])
CREATE OR REPLACE FUNCTION public.edit_comment(p_id bigint, p_body text, p_media text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
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
$function$;

-- edit_doc_comment(bigint, text)
CREATE OR REPLACE FUNCTION public.edit_doc_comment(p_id bigint, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
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
$function$;

-- edit_my_build(bigint, jsonb)
CREATE OR REPLACE FUNCTION public.edit_my_build(p_id bigint, p_build jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  b public.builds%rowtype;
  nb jsonb;
begin
  select * into b from public.builds where id = p_id for update;
  if not found or b.author_id is distinct from (select auth.uid()) then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if b.status = 'revision_requested' then
    raise exception '재검토 요청을 받은 빌드는 [고쳐서 다시 보내기]로 고쳐 주세요.' using errcode = '23514';
  end if;
  if b.status <> 'pending' then
    raise exception '승인 대기 중인 빌드만 고칠 수 있습니다.' using errcode = '23514';
  end if;
  if (select status from public.counters where id = b.counter_id) is distinct from 'approved' then
    raise exception '이 매치업은 지금 고칠 수 없습니다.' using errcode = '23514';
  end if;
  nb := public.clean_build(p_build);
  if nb - 'patch' = public.build_signature(b) then
    raise exception '고친 내용이 없습니다.' using errcode = '23514';
  end if;
  if exists (
    select 1 from public.builds x
    where x.counter_id = b.counter_id and x.status = 'approved' and public.build_signature(x) = nb - 'patch'
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있습니다. 추천으로 응원해 주세요.' using errcode = '23514';
  end if;

  perform public.set_build_fields(b.id, nb);
  update public.builds set version = version + 1, edited_at = now() where id = b.id;
end;
$function$;

-- edit_my_proposal(bigint, jsonb, jsonb)
CREATE OR REPLACE FUNCTION public.edit_my_proposal(p_id bigint, p_content jsonb, p_build jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  p public.edit_proposals%rowtype;
  new_content jsonb;
  new_build jsonb;
  st text;
begin
  select * into p from public.edit_proposals where id = p_id for update;
  if not found or p.proposer_id is distinct from (select auth.uid()) then
    raise exception '제안을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if p.status = 'revision_requested' then
    raise exception '재검토 요청을 받은 제안은 [고쳐서 다시 보내기]로 고쳐 주세요.' using errcode = '23514';
  end if;
  if p.status <> 'pending' then
    raise exception '승인 대기 중인 제안만 고칠 수 있습니다.' using errcode = '23514';
  end if;
  new_content := public.clean_doc_content(p_content);

  if p.type = 'new_counter' then
    if p_build is null then
      raise exception '빌드도 함께 채워 주세요. 새 상대법 제안에는 빌드가 꼭 있어야 합니다.' using errcode = '23514';
    end if;
    new_build := public.clean_build(p_build);
    if public.is_hidden_counter_flow(p) then
      select status into st from public.counters where id = p.counter_id;
      if st is distinct from 'hidden' then
        raise exception '이 상대법은 지금 고칠 수 없습니다.' using errcode = '23514';
      end if;
    else
      select status into st from public.counters
       where target_champion = p.target_champion and counter_champion = p.counter_champion and status in ('approved', 'hidden');
      if st = 'approved' then
        raise exception '그 사이 같은 상대법이 등록됐습니다. 문서 수정 제안을 이용해 주세요.' using errcode = '23514';
      end if;
      if st = 'hidden' then
        raise exception '운영자가 숨긴 상대법이라 지금은 고칠 수 없습니다.' using errcode = '23514';
      end if;
    end if;
  else  -- doc_edit
    if p_build is not null then
      raise exception '문서 수정 제안에는 빌드를 넣지 않습니다.' using errcode = '23514';
    end if;
    select status into st from public.counters where id = p.counter_id;
    if st = 'approved' and new_content = (
      select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
      from public.matchup_docs d where d.counter_id = p.counter_id
    ) then
      raise exception '지금 문서와 달라진 내용이 없습니다.' using errcode = '23514';
    end if;
  end if;

  if new_content = public.clean_doc_content(p.content)
     and (p.type = 'doc_edit' or (p.build is not null and new_build - 'patch' = p.build - 'patch')) then
    raise exception '고친 내용이 없습니다.' using errcode = '23514';
  end if;

  update public.edit_proposals
     set content = new_content, build = coalesce(new_build, build), version = version + 1, edited_at = now()
   where id = p.id;
end;
$function$;

-- edit_post(bigint, text, text, text[])
CREATE OR REPLACE FUNCTION public.edit_post(p_id bigint, p_title text, p_body text, p_media text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  p public.posts%rowtype := public.board_post_for_update(p_id);
  keep_count integer;
  t text;
  b text;
  changed boolean;
begin
  if p.author_id is distinct from me then
    raise exception '내 글만 고칠 수 있습니다.' using errcode = '42501';
  end if;
  if p.deleted_at is not null then
    raise exception '삭제된 글입니다.' using errcode = '23514';
  end if;
  if p.status <> 'visible' then
    raise exception '운영진이 숨긴 글은 고칠 수 없습니다.' using errcode = '23514';
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
$function$;

-- follow_influencer(uuid)
CREATE OR REPLACE FUNCTION public.follow_influencer(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  return public.follow_influencer_unchecked(me, p_user);
end;
$function$;

-- report_comment(bigint, text, text)
CREATE OR REPLACE FUNCTION public.report_comment(p_id bigint, p_reason text, p_detail text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
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
$function$;

-- report_doc_comment(bigint, text, text)
CREATE OR REPLACE FUNCTION public.report_doc_comment(p_id bigint, p_reason text, p_detail text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
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
$function$;

-- report_link(bigint, text, text)
CREATE OR REPLACE FUNCTION public.report_link(p_link bigint, p_reason text, p_detail text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  d text := nullif(btrim(coalesce(p_detail, '')), '');
  owner uuid;
begin
  if public.is_guest(me) then
    raise exception '비회원은 신고할 수 없습니다. 구글/카카오를 연결하면 할 수 있습니다.' using errcode = '42501';
  end if;
  if p_reason is null or p_reason not in ('spam', 'obscene', 'malicious', 'not_own', 'other') then
    raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
  end if;
  if p_reason = 'other' and d is null then
    raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(d) > 500 then
    raise exception '신고 내용은 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  select l.owner_id into owner from public.ext_links l where l.id = p_link;
  if not found or not public.ext_link_visible(p_link) then
    raise exception '신고할 수 없는 링크입니다.' using errcode = 'P0002';
  end if;
  if owner = me then
    raise exception '내 링크는 신고할 수 없습니다.' using errcode = '23514';
  end if;
  insert into public.link_reports (link_id, reporter_id, reason, detail) values (p_link, me, p_reason, d);
exception when unique_violation then
  raise exception '이미 신고한 링크입니다.' using errcode = '23505';
end;
$function$;

-- report_post(bigint, text, text)
CREATE OR REPLACE FUNCTION public.report_post(p_id bigint, p_reason text, p_detail text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  d text := public.board_report_check(p_reason, p_detail);
  p public.posts%rowtype;
begin
  select * into p from public.posts where id = p_id;
  if not found or p.status <> 'visible' or p.deleted_at is not null then
    raise exception '신고할 수 없는 글입니다.' using errcode = 'P0002';
  end if;
  if p.author_id = me then
    raise exception '내 글은 신고할 수 없습니다.' using errcode = '23514';
  end if;
  insert into public.reports (reporter_id, post_id, reason, detail) values (me, p.id, p_reason, d);
exception when unique_violation then
  raise exception '이미 신고한 글입니다.' using errcode = '23505';
end;
$function$;

-- report_profile_photo(uuid, text, text)
CREATE OR REPLACE FUNCTION public.report_profile_photo(p_user uuid, p_reason text, p_detail text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  d text := nullif(btrim(coalesce(p_detail, '')), '');
  path text;
begin
  if public.is_guest(me) then
    raise exception '비회원은 신고할 수 없습니다. 구글/카카오를 연결하면 할 수 있습니다.' using errcode = '42501';
  end if;
  if p_reason is null or p_reason not in ('obscene', 'hate', 'impersonation', 'spam', 'other') then
    raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
  end if;
  if p_reason = 'other' and d is null then
    raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(d) > 500 then
    raise exception '신고 내용은 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  if p_user = me then
    raise exception '내 사진은 신고할 수 없습니다.' using errcode = '23514';
  end if;
  select photo_path into path from public.profiles where id = p_user and influencer is not null;
  if path is null then
    raise exception '신고할 수 없는 사진입니다. 이미 바뀌었거나 지워졌을 수 있습니다.' using errcode = 'P0002';
  end if;
  insert into public.profile_photo_reports (owner_id, photo_path, reporter_id, reason, detail) values (p_user, path, me, p_reason, d);
exception when unique_violation then
  raise exception '이미 신고한 사진입니다.' using errcode = '23505';
end;
$function$;

-- report_wiki(bigint, bigint, text, text)
CREATE OR REPLACE FUNCTION public.report_wiki(p_counter bigint, p_build bigint, p_reason text, p_memo text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();  -- 로그인 + 닉네임
  m text := nullif(btrim(coalesce(p_memo, '')), '');
  cid bigint := p_counter;
  b public.builds;
  cap integer := coalesce(public.xp_rule('error_report_daily_cap'), 10);
  today integer;
  first_open boolean;
  rid bigint;
begin
  if public.is_guest(me) then
    raise exception '오류 신고는 구글·카카오로 로그인한 회원만 할 수 있습니다.' using errcode = '42501';
  end if;
  if p_build is not null then
    select * into b from public.builds where id = p_build;
    if not found or b.status <> 'approved' or (cid is not null and b.counter_id <> cid) then
      raise exception '신고할 빌드를 찾지 못했습니다.' using errcode = 'P0002';
    end if;
    cid := b.counter_id;
  end if;
  if cid is null or not exists (select 1 from public.counters where id = cid and status = 'approved') then
    raise exception '신고할 상대법을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if p_reason is null or p_reason not in ('wrong', 'outdated', 'vandal', 'duplicate', 'other')
     or (p_build is null and p_reason not in ('wrong', 'vandal', 'other')) then
    raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
  end if;
  if p_reason = 'other' and m is null then
    raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(m) > 200 then
    raise exception '메모는 200자 이하로 적어 주세요.' using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(hashtext('wiki_report:' || me::text));  -- 같은 사람이 동시에 여러 번 눌러도 상한을 넘지 않게
  select count(*) into today from public.wiki_reports
   where reporter_id = me
     and created_at >= ((now() at time zone 'Asia/Seoul')::date::timestamp at time zone 'Asia/Seoul');
  if today >= cap then
    raise exception '오류 신고는 하루에 %건까지 할 수 있습니다. 내일 다시 해 주세요.', cap using errcode = '23514';
  end if;

  perform 1 from public.counters where id = cid for update;  -- 같은 대상의 "첫 신고" 판단이 겹치지 않게
  first_open := not exists (
    select 1 from public.wiki_reports
     where counter_id = cid and build_id is not distinct from p_build and status = 'open');
  begin
    insert into public.wiki_reports (counter_id, build_id, reporter_id, reason, memo)
    values (cid, p_build, me, p_reason, m)
    returning id into rid;
  exception when unique_violation then
    raise exception '이미 신고한 내용이 처리를 기다리고 있습니다.' using errcode = '23505';
  end;

  -- 운영진 알림: 그 대상에 처리 전 신고가 처음 생길 때만 (운영자 + 감독관, 신고자 본인 제외)
  if first_open then
    insert into public.notifications (user_id, kind, message, counter_id, build_id)
    select u.id, 'error_reported',
           format('새 오류 신고가 들어왔습니다. (%s)', public.wiki_report_reason_label(p_reason)), cid, p_build
      from public.profiles u
     where u.role in ('admin', 'moderator') and u.id <> me;
  end if;
  return rid;
end;
$function$;

-- resubmit_build(bigint, jsonb)
CREATE OR REPLACE FUNCTION public.resubmit_build(p_id bigint, p_build jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  b public.builds%rowtype;
  nb jsonb;
begin
  select * into b from public.builds where id = p_id for update;
  if not found or b.author_id is distinct from (select auth.uid()) then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if b.status <> 'revision_requested' then
    raise exception '재검토 요청을 받은 빌드만 다시 보낼 수 있습니다.' using errcode = '23514';
  end if;
  if (select status from public.counters where id = b.counter_id) is distinct from 'approved' then
    raise exception '이 매치업은 지금 다시 보낼 수 없습니다.' using errcode = '23514';
  end if;
  nb := public.clean_build(p_build);
  if nb - 'patch' = public.build_signature(b) then
    raise exception '고친 내용이 없습니다. 운영자 메모를 보고 고쳐 주세요.' using errcode = '23514';
  end if;
  if exists (
    select 1 from public.builds x
    where x.counter_id = b.counter_id and x.status = 'approved' and public.build_signature(x) = nb - 'patch'
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있습니다. 추천으로 응원해 주세요.' using errcode = '23514';
  end if;

  perform public.set_build_fields(b.id, nb);
  update public.builds set status = 'pending', resubmitted_at = now() where id = b.id;
  insert into public.build_status_log (build_id, action, reason, actor)
  values (b.id, 'resubmit', '작성자가 고쳐서 다시 보냄', (select auth.uid()));
  update public.notifications set read_at = now()
   where build_id = b.id and kind = 'revision_request' and read_at is null;
end;
$function$;

-- resubmit_proposal(bigint, jsonb, jsonb)
CREATE OR REPLACE FUNCTION public.resubmit_proposal(p_id bigint, p_content jsonb, p_build jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  p public.edit_proposals%rowtype;
  hidden_flow boolean;
  st text;
  new_content jsonb;
  new_build jsonb;
begin
  select * into p from public.edit_proposals where id = p_id for update;
  if not found or p.proposer_id is distinct from (select auth.uid()) then
    raise exception '제안을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if p.status <> 'revision_requested' then
    raise exception '재검토 요청을 받은 제안만 다시 보낼 수 있습니다.' using errcode = '23514';
  end if;
  hidden_flow := public.is_hidden_counter_flow(p);
  new_content := public.clean_doc_content(p_content);

  if p.type = 'new_counter' then
    if p_build is null then
      raise exception '빌드도 함께 채워 주세요. 새 상대법 제안에는 빌드가 꼭 있어야 합니다.' using errcode = '23514';
    end if;
    new_build := public.clean_build(p_build);
    if hidden_flow then
      select status into st from public.counters where id = p.counter_id for update;
      if st is distinct from 'hidden' then
        raise exception '이 상대법은 지금 다시 보낼 수 없습니다.' using errcode = '23514';
      end if;
    else
      select status into st from public.counters
       where target_champion = p.target_champion and counter_champion = p.counter_champion and status in ('approved', 'hidden');
      if st = 'approved' then
        raise exception '그 사이 같은 상대법이 등록됐습니다. 문서 수정 제안을 이용해 주세요.' using errcode = '23514';
      end if;
      if st = 'hidden' then
        raise exception '운영자가 숨긴 상대법이라 지금은 다시 보낼 수 없습니다.' using errcode = '23514';
      end if;
    end if;
  else  -- doc_edit
    if p_build is not null then
      raise exception '문서 수정 제안에는 빌드를 넣지 않습니다.' using errcode = '23514';
    end if;
    select status into st from public.counters where id = p.counter_id;
    if st is distinct from 'approved' then
      raise exception '이 매치업은 지금 다시 보낼 수 없습니다.' using errcode = '23514';
    end if;
    if new_content = (
      select jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
      from public.matchup_docs d where d.counter_id = p.counter_id
    ) then
      raise exception '지금 문서와 달라진 내용이 없습니다.' using errcode = '23514';
    end if;
  end if;

  if new_content = public.clean_doc_content(p.content)
     and (p.type = 'doc_edit' or (p.build is not null and new_build - 'patch' = p.build - 'patch')) then
    raise exception '고친 내용이 없습니다. 운영자 메모를 보고 고쳐 주세요.' using errcode = '23514';
  end if;

  update public.edit_proposals
     set status = 'pending', content = new_content, build = coalesce(new_build, build), resubmitted_at = now(),
         reviewed_by = null, reviewed_at = null
   where id = p.id;

  update public.notifications set read_at = now()
   where proposal_id = p.id and kind = 'revision_request' and read_at is null;

  if hidden_flow then
    insert into public.counter_status_log (counter_id, action, proposal_id, actor)
    values (p.counter_id, 'resubmit', p.id, (select auth.uid()));
  end if;
end;
$function$;

-- save_build(bigint)
CREATE OR REPLACE FUNCTION public.save_build(p_build bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := (select auth.uid());
  n integer;
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  if not public.has_nickname() then
    raise exception '닉네임을 정한 뒤에 저장할 수 있습니다.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.builds b join public.counters c on c.id = b.counter_id
     where b.id = p_build and b.status = 'approved' and c.status = 'approved'
  ) then
    raise exception '공개된 빌드만 저장할 수 있습니다.' using errcode = '23514';
  end if;
  -- 같은 사람이 동시에 여러 번 눌러도 한도를 넘지 않게 그 사람 줄을 잠근다
  perform 1 from public.profiles where id = me for update;
  if exists (select 1 from public.build_bookmarks where user_id = me and build_id = p_build) then
    select count(*) into n from public.build_bookmarks where user_id = me;
    return jsonb_build_object('saved', true, 'count', n);
  end if;
  select count(*) into n from public.build_bookmarks where user_id = me;
  if n >= public.save_build_limit() then
    raise exception '저장은 %개까지 할 수 있습니다. 안 보는 빌드를 해제해 주세요.', public.save_build_limit() using errcode = '23514';
  end if;
  insert into public.build_bookmarks (user_id, build_id) values (me, p_build);
  return jsonb_build_object('saved', true, 'count', n + 1);
end;
$function$;

-- set_application_photo(text)
CREATE OR REPLACE FUNCTION public.set_application_photo(p_path text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  a public.influencer_applications%rowtype;
  o record;
  m text;
  sz bigint;
  daily integer := public.xp_rule('profile_photo_daily_max');
begin
  select * into a from public.influencer_applications where user_id = me and status = 'pending' for update;
  if not found then
    raise exception '심사 중인 장인 인증 신청이 없습니다.' using errcode = 'P0002';
  end if;
  if p_path is null or p_path !~ ('^' || me::text || '/[0-9A-Za-z_-]{1,64}\.(webp|jpg)$') then
    raise exception '사진을 다시 골라 주세요.' using errcode = '22023';
  end if;
  if p_path = a.photo_path then
    return;  -- 이미 이 사진
  end if;
  select ob.owner_id, ob.metadata into o from storage.objects ob where ob.bucket_id = 'profile-photos' and ob.name = p_path;
  if not found or o.owner_id is distinct from me::text then
    raise exception '올린 사진을 찾지 못했습니다. 사진을 다시 골라 주세요.' using errcode = '23514';
  end if;
  m := o.metadata ->> 'mimetype';
  sz := coalesce((o.metadata ->> 'size')::bigint, 0);
  if m is null or m not in ('image/webp', 'image/jpeg') or sz <= 0 or sz > 1048576 then
    raise exception '사진 형식이나 크기가 맞지 않습니다. 다른 사진을 골라 주세요.' using errcode = '23514';
  end if;
  delete from public.profile_photo_changes where user_id = me and created_at < now() - interval '2 days';
  if (select count(*) from public.profile_photo_changes where user_id = me and created_at > now() - interval '24 hours') >= daily then
    raise exception '프로필 사진은 하루에 %번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily using errcode = '54000';
  end if;
  update public.influencer_applications set photo_path = p_path, photo_updated_at = now() where id = a.id;
  insert into public.profile_photo_changes (user_id) values (me);
  delete from public.profile_photo_trash where path = p_path;  -- 혹시 대기열에 있던 내 파일을 다시 쓰면 지우지 않는다
end;
$function$;

-- set_build_link(bigint, text)
CREATE OR REPLACE FUNCTION public.set_build_link(p_build bigint, p_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  b_author uuid;
  parsed text[];
  cur public.ext_links%rowtype;
begin
  if not exists (select 1 from public.profiles where id = me and influencer is not null) then
    raise exception '인증된 장인만 링크를 올릴 수 있습니다.' using errcode = '42501';
  end if;
  select b.author_id into b_author from public.builds b where b.id = p_build;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if b_author is distinct from me then
    raise exception '내가 처음 만든 빌드에만 링크를 달 수 있습니다.' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('ext_links:' || me::text));
  select * into cur from public.ext_links where build_id = p_build;
  if nullif(btrim(coalesce(p_url, '')), '') is null then
    delete from public.ext_links where build_id = p_build;
    return null;
  end if;
  parsed := public.ext_link_parse(p_url);
  if cur.id is not null and cur.url = parsed[1] then
    return public.ext_link_json(cur.id);
  end if;
  delete from public.ext_links where build_id = p_build;
  insert into public.ext_links (owner_id, build_id, url, host, sort) values (me, p_build, parsed[1], parsed[2], 0)
  returning * into cur;
  return public.ext_link_json(cur.id);
end;
$function$;

-- set_profile_links(text[])
CREATE OR REPLACE FUNCTION public.set_profile_links(p_urls text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  lim integer := coalesce(public.xp_rule('influencer_profile_links_max'), 5);
  parsed text[];
  urls text[] := '{}';
  hosts text[] := '{}';
  i integer;
begin
  if not exists (select 1 from public.profiles where id = me and influencer is not null) then
    raise exception '인증된 장인만 링크를 올릴 수 있습니다.' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_urls), 0) > 20 then
    raise exception '프로필 링크는 %개까지 올릴 수 있습니다.', lim using errcode = '23514';
  end if;
  for i in 1 .. coalesce(cardinality(p_urls), 0) loop
    if nullif(btrim(coalesce(p_urls[i], '')), '') is null then
      continue;
    end if;
    parsed := public.ext_link_parse(p_urls[i]);
    if parsed[1] = any (urls) then
      raise exception '같은 주소를 두 번 올릴 수 없습니다.' using errcode = '23514';
    end if;
    urls := urls || parsed[1];
    hosts := hosts || parsed[2];
  end loop;
  if cardinality(urls) > lim then
    raise exception '프로필 링크는 %개까지 올릴 수 있습니다.', lim using errcode = '23514';
  end if;
  perform pg_advisory_xact_lock(hashtext('ext_links:' || me::text));
  delete from public.ext_links where owner_id = me and build_id is null and not (url = any (urls));
  for i in 1 .. cardinality(urls) loop
    update public.ext_links set sort = i - 1, updated_at = now()
     where owner_id = me and build_id is null and url = urls[i] and sort <> i - 1;
    if not exists (select 1 from public.ext_links where owner_id = me and build_id is null and url = urls[i]) then
      insert into public.ext_links (owner_id, build_id, url, host, sort) values (me, null, urls[i], hosts[i], i - 1);
    end if;
  end loop;
  return coalesce((select jsonb_agg(public.ext_link_json(l.id) order by l.sort)
                     from public.ext_links l where l.owner_id = me and l.build_id is null), '[]'::jsonb);
end;
$function$;

-- set_profile_photo(text)
CREATE OR REPLACE FUNCTION public.set_profile_photo(p_path text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  p public.profiles%rowtype;
  o record;
  m text;
  sz bigint;
  daily integer := public.xp_rule('profile_photo_daily_max');
begin
  select * into p from public.profiles where id = me for update;
  if p.influencer is null or p.is_guest then
    raise exception '인증된 장인만 프로필 사진을 올릴 수 있습니다.' using errcode = '42501';
  end if;
  if p_path is null or p_path !~ ('^' || me::text || '/[0-9A-Za-z_-]{1,64}\.(webp|jpg)$') then
    raise exception '사진을 다시 골라 주세요.' using errcode = '22023';
  end if;
  if p_path = p.photo_path then
    return;  -- 이미 이 사진
  end if;
  select ob.owner_id, ob.metadata into o from storage.objects ob where ob.bucket_id = 'profile-photos' and ob.name = p_path;
  if not found or o.owner_id is distinct from me::text then
    raise exception '올린 사진을 찾지 못했습니다. 사진을 다시 골라 주세요.' using errcode = '23514';
  end if;
  m := o.metadata ->> 'mimetype';
  sz := coalesce((o.metadata ->> 'size')::bigint, 0);
  if m is null or m not in ('image/webp', 'image/jpeg') or sz <= 0 or sz > 1048576 then
    raise exception '사진 형식이나 크기가 맞지 않습니다. 다른 사진을 골라 주세요.' using errcode = '23514';
  end if;
  delete from public.profile_photo_changes where user_id = me and created_at < now() - interval '2 days';
  if (select count(*) from public.profile_photo_changes where user_id = me and created_at > now() - interval '24 hours') >= daily then
    raise exception '프로필 사진은 하루에 %번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily using errcode = '54000';
  end if;
  update public.profiles set photo_path = p_path, photo_updated_at = now() where id = me;
  insert into public.profile_photo_changes (user_id) values (me);
  delete from public.profile_photo_trash where path = p_path;  -- 혹시 대기열에 있던 내 파일을 다시 쓰면 지우지 않는다
end;
$function$;

-- vote_build(bigint, smallint)
CREATE OR REPLACE FUNCTION public.vote_build(p_build_id bigint, p_value smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := (select auth.uid());
  b public.builds%rowtype;
  cst text;
  old_v smallint;
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  if not public.has_nickname() then
    raise exception '닉네임을 정한 뒤에 투표할 수 있습니다.' using errcode = '42501';
  end if;
  if p_value is not null and p_value not in (1, -1) then
    raise exception '투표 값이 잘못됐습니다.' using errcode = '23514';
  end if;
  select * into b from public.builds where id = p_build_id for update;
  select status into cst from public.counters where id = b.counter_id;
  if not found or b.status <> 'approved' or cst is distinct from 'approved' then
    raise exception '공개된 빌드에만 투표할 수 있습니다.' using errcode = '23514';
  end if;
  if b.author_id = me then
    raise exception '내 빌드에는 투표할 수 없습니다.' using errcode = '23514';
  end if;

  select value into old_v from public.build_votes where build_id = b.id and user_id = me;
  if p_value is null then
    delete from public.build_votes where build_id = b.id and user_id = me;
  elsif old_v is null then
    insert into public.build_votes (build_id, user_id, value) values (b.id, me, p_value);
  elsif old_v <> p_value then
    update public.build_votes set value = p_value where build_id = b.id and user_id = me;
  end if;

  if old_v is distinct from p_value then
    insert into public.build_vote_log (build_id, counter_id, author_id, voter_id, old_value, new_value)
    values (b.id, b.counter_id, b.author_id, me, old_v, p_value);
    -- (6단계) 추천 받음 경험치(+2, 하루 상한)는 이 기록으로 계산
  end if;

  return (select jsonb_build_object('up', up_count, 'down', down_count, 'mine', p_value) from public.builds where id = b.id);
end;
$function$;

-- vote_post(bigint)
CREATE OR REPLACE FUNCTION public.vote_post(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();
  p public.posts%rowtype := public.board_post_for_update(p_id);
  mine boolean;
begin
  if p.deleted_at is not null or p.status <> 'visible' then
    raise exception '추천할 수 없는 글입니다.' using errcode = '23514';
  end if;
  if p.author_id = me then
    raise exception '내 글은 추천할 수 없습니다.' using errcode = '23514';
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
$function$;

-- 6-2. 그 밖의 8개: 사진 올리기 사전 검사 2개(제한 문장), 감독관 지정(제한 중이면 거절), 문의 분류 「이의 제기」 5개

-- media_upload_problem()
CREATE OR REPLACE FUNCTION public.media_upload_problem()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := (select auth.uid());
  today integer;
begin
  if me is null then
    return '로그인해야 사진을 올릴 수 있습니다.';
  end if;
  if public.restriction_message(me) is not null then  -- 068 활동 제한: 제한 중이면 그 문장 (옛 앱도 올리기 실패 때 이 문장을 보여 준다)
    return public.restriction_message(me);
  end if;
  if not public.has_nickname() then
    return '닉네임을 정해야 사진을 올릴 수 있습니다.';
  end if;
  if public.is_guest(me) then
    return '비회원은 사진을 올릴 수 없습니다. 구글·카카오를 연결하면 할 수 있습니다.';
  end if;
  if public.media_used_bytes() >= public.xp_rule('media_block_mb')::bigint * 1024 * 1024 then
    return '지금은 사진 저장 공간이 거의 차서 사진을 올릴 수 없습니다. 글은 그대로 쓸 수 있습니다.';
  end if;
  select count(*) into today from storage.objects o
   where o.bucket_id = 'board-media' and o.owner_id = me::text and o.created_at > now() - interval '24 hours';
  if today >= public.xp_rule('media_daily_max') then
    return format('사진은 하루에 %s개까지 올릴 수 있습니다. 내일 다시 해 주세요.', public.xp_rule('media_daily_max'));
  end if;
  return null;
end;
$function$;

-- profile_photo_upload_problem()
CREATE OR REPLACE FUNCTION public.profile_photo_upload_problem()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := (select auth.uid());
  daily integer := public.xp_rule('profile_photo_daily_max');
begin
  if me is null then
    return '로그인해야 프로필 사진을 올릴 수 있습니다.';
  end if;
  if public.restriction_message(me) is not null then  -- 068 활동 제한: 제한 중이면 그 문장 (옛 앱도 올리기 실패 때 이 문장을 보여 준다)
    return public.restriction_message(me);
  end if;
  if not exists (select 1 from public.profiles p where p.id = me and p.nickname is not null and not p.is_guest
                   and (p.influencer is not null
                        or exists (select 1 from public.influencer_applications a where a.user_id = me and a.status = 'pending'))) then
    return '인증된 장인이나 장인 인증을 신청한 회원만 프로필 사진을 올릴 수 있습니다.';
  end if;
  if (select count(*) from storage.objects o where o.bucket_id = 'profile-photos' and o.owner_id = me::text) >= 5 then
    return '올려 두고 쓰지 않은 사진이 많습니다. 하루 뒤 다시 시도해 주세요.';
  end if;
  if (select count(*) from public.profile_photo_changes c where c.user_id = me and c.created_at > now() - interval '24 hours') >= daily then
    return format('프로필 사진은 하루에 %s번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily);
  end if;
  return null;
end;
$function$;

-- set_moderator(uuid, boolean, text)
CREATE OR REPLACE FUNCTION public.set_moderator(p_user uuid, p_on boolean, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    if public.active_restriction_id(u.id) is not null then  -- 068: 활동 제한 중인 사람은 감독관으로 지정하지 않는다
      raise exception '활동이 제한된 회원은 감독관으로 지정할 수 없습니다. 제한이 풀린 뒤 다시 해 주세요.' using errcode = '23514';
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
$function$;

-- create_inquiry(text, text)
CREATE OR REPLACE FUNCTION public.create_inquiry(p_category text, p_body text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := (select auth.uid());
  text_body text := btrim(coalesce(p_body, ''), E' \t\r\n');
  len integer := char_length(btrim(coalesce(p_body, ''), E' \t\r\n'));
  min_len integer := public.xp_rule('inquiry_min');
  max_len integer := public.xp_rule('inquiry_max');
  daily integer := public.xp_rule('inquiry_daily_max');
  today date := (now() at time zone 'Asia/Seoul')::date;
  q public.inquiry_quota%rowtype;
  new_id bigint;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  if p_category is null or p_category not in ('bug', 'idea', 'account', 'appeal', 'other') then
    raise exception '분류를 골라 주세요.' using errcode = '22023';
  end if;
  if len < min_len then
    raise exception '내용을 %자 이상 적어 주세요.', min_len using errcode = '22023';
  end if;
  if len > max_len then
    raise exception '내용은 %자까지 적을 수 있습니다.', max_len using errcode = '22023';
  end if;
  perform 1 from public.profiles where id = me for update;  -- 같은 사람의 동시 요청을 한 줄로
  if not found then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  select * into q from public.inquiry_quota where user_id = me;
  if not found then
    insert into public.inquiry_quota (user_id, day, sent) values (me, today, 0);
    q.day := today; q.sent := 0;
  elsif q.day <> today then
    q.day := today; q.sent := 0;
  end if;
  if q.sent >= daily then
    raise exception '문의는 하루에 %건까지 보낼 수 있습니다. 내일 다시 보내 주세요.', daily using errcode = 'P0001';
  end if;
  update public.inquiry_quota set day = today, sent = q.sent + 1 where user_id = me;
  insert into public.inquiries (user_id, category, body) values (me, p_category, text_body) returning id into new_id;
  return new_id;
end;
$function$;

-- set_inquiry_category(bigint, text)
CREATE OR REPLACE FUNCTION public.set_inquiry_category(p_id bigint, p_category text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  i public.inquiries%rowtype;
begin
  perform public.require_operator();
  if p_category is null or p_category not in ('bug', 'idea', 'account', 'appeal', 'other') then
    raise exception '분류를 골라 주세요.' using errcode = '22023';
  end if;
  select * into i from public.inquiries where id = p_id for update;
  if not found then
    raise exception '문의를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if i.category = p_category then
    raise exception '이미 같은 분류입니다.' using errcode = '23514';
  end if;
  update public.inquiries set category = p_category where id = i.id;
  perform public.log_moderation('move_inquiry', 'inquiry', i.id::text,
    format('%s → %s', public.inquiry_category_label(i.category), public.inquiry_category_label(p_category)));
end;
$function$;

-- inquiry_category_label(text)
CREATE OR REPLACE FUNCTION public.inquiry_category_label(p_category text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_category when 'bug' then '오류 신고' when 'idea' then '건의' when 'account' then '계정·탈퇴' when 'appeal' then '이의 제기' else '기타' end;
$function$;

-- answer_inquiry(bigint, text)
CREATE OR REPLACE FUNCTION public.answer_inquiry(p_id bigint, p_answer text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := (select auth.uid());
  ans text := btrim(coalesce(p_answer, ''), E' \t\r\n');
  max_len integer := public.xp_rule('inquiry_answer_max');
  i public.inquiries%rowtype;
begin
  perform public.require_staff();
  select * into i from public.inquiries where id = p_id for update;
  if not found then
    raise exception '문의를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if i.answer is not null then
    raise exception '이미 다른 분이 처리했습니다.' using errcode = 'TL409';
  end if;
  if i.user_id = me then
    raise exception '본인이 보낸 문의에는 답변할 수 없습니다.' using errcode = '42501';
  end if;
  if i.category in ('account', 'appeal') and public.is_moderator() then  -- require_staff를 지났으니 운영자가 아니면 감독관 (068: 이의 제기도)
    raise exception '"%" 문의는 운영자만 답변할 수 있습니다.', public.inquiry_category_label(i.category) using errcode = '42501';
  end if;
  if ans = '' then
    raise exception '답변을 적어 주세요.' using errcode = '22023';
  end if;
  if char_length(ans) > max_len then
    raise exception '답변은 %자까지 적을 수 있습니다.', max_len using errcode = '22023';
  end if;
  update public.inquiries set answer = ans, answered_at = now() where id = i.id;
  perform public.notify(i.user_id, 'inquiry_answered',
    format('"%s" 문의에 답변이 도착했습니다.', public.inquiry_category_label(i.category)), null, null);
  perform public.log_moderation('answer_inquiry', 'inquiry', i.id::text, null);  -- 문의 내용은 기록에 넣지 않는다
end;
$function$;

-- notify_staff_new_inquiry()
CREATE OR REPLACE FUNCTION public.notify_staff_new_inquiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE' then
    -- 운영자가 분류를 옮겨서 감독관에게 보이게 됐을 때 (계정·탈퇴·이의 제기 → 다른 분류), 아직 답이 없을 때만
    if new.answer is not null or old.category not in ('account', 'appeal') or new.category in ('account', 'appeal') then
      return null;
    end if;
    insert into public.notifications (user_id, kind, message)
    select u.id, 'inquiry_received',
           format('새 문의가 들어왔습니다. (분류: %s)', public.inquiry_category_label(new.category))
      from public.profiles u
     where u.role = 'moderator' and u.id is distinct from new.user_id;
    return null;
  end if;
  insert into public.notifications (user_id, kind, message)
  select u.id, 'inquiry_received',
         format('새 문의가 들어왔습니다. (분류: %s)', public.inquiry_category_label(new.category))
    from public.profiles u
   where (u.role = 'admin' or (u.role = 'moderator' and new.category not in ('account', 'appeal')))
     and u.id is distinct from new.user_id;
  return null;
end;
$function$;

-- ---------------------------------------------------------------------
-- 7. 빠뜨림 방지 허용 목록: 일반 사용자가 부를 수 있는 쓰기 함수·쓰기 정책 중 "제한 검사를 하지 않는 것"과 그 이유.
--    검사(tests/restriction_coverage_test.sql, scripts/check_restrictions_after.sql)는 쓰기 함수마다
--    assert_can_write()가 있거나 이 목록에 있어야 통과한다. 새 쓰기 함수를 만들면 둘 중 하나를 꼭 해야 한다.
--    name: 함수 = 이름(인자 형식들) (oidvectortypes 모양), 정책 = 스키마.표: 정책 이름
-- ---------------------------------------------------------------------
create table public.restriction_exemptions (
  kind   text not null check (kind in ('function', 'policy')),
  name   text not null,
  reason text not null check (char_length(reason) between 1 and 200),
  primary key (kind, name)
);
comment on table public.restriction_exemptions is '068 활동 제한 검사를 하지 않는 쓰기 함수·정책 허용 목록 (이유와 함께). 빠뜨림 방지 검사가 읽는다';
alter table public.restriction_exemptions enable row level security;  -- 정책 없음 = 화면·사용자는 못 읽음
revoke all on public.restriction_exemptions from public, anon, authenticated;

insert into public.restriction_exemptions (kind, name, reason) values
  -- 제한 중에도 되는 일 (2026-11-23 결정)
  ('function', 'create_inquiry(text, text)',                 '문의하기 보내기 (이의 제기 포함)'),
  ('function', 'delete_my_inquiry(bigint)',                  '내 문의 지우기'),
  ('function', 'delete_my_account(text)',                    '계정 삭제'),
  ('function', 'delete_my_post(bigint)',                     '내 글 지우기'),
  ('function', 'delete_my_comment(bigint)',                  '내 댓글 지우기'),
  ('function', 'delete_my_doc_comment(bigint)',              '내 문서 댓글 지우기'),
  ('function', 'unfollow_influencer(uuid)',                  '팔로우 취소'),
  ('function', 'unsave_build(bigint)',                       '빌드 저장 해제 (저장은 막음)'),
  ('function', 'mark_notifications_read(bigint[])',          '알림 읽음 처리'),
  ('function', 'mark_all_notifications_read(bigint)',        '알림 모두 읽음'),
  ('function', 'touch_last_seen()',                          '로그인 시각 기록'),
  ('function', 'cancel_influencer_application(bigint)',      '내 장인 신청 취소 (지우기와 같음)'),
  ('function', 'clear_profile_photo()',                      '내 프로필 사진 지우기'),
  ('function', 'clear_application_photo()',                  '내 신청 사진 지우기'),
  -- 운영자·감독관 전용 (운영자·감독관에게는 제한을 걸 수 없고, 제한 중인 사람은 감독관이 될 수 없다)
  ('function', 'add_offmeta(text)',                          '운영자 전용'),
  ('function', 'admin_add_link_domain(text, text)',          '운영자 전용'),
  ('function', 'admin_remove_link_domain(text, text)',       '운영자 전용'),
  ('function', 'admin_set_nickname(uuid, text, text)',       '운영자 전용'),
  ('function', 'answer_inquiry(bigint, text)',               '운영진 전용'),
  ('function', 'approve_build(bigint, text, jsonb, integer)', '운영자 전용'),
  ('function', 'approve_influencer(bigint, text)',           '운영자 전용'),
  ('function', 'approve_influencer(bigint, text, text, boolean)', '운영자 전용'),
  ('function', 'approve_proposal(bigint, text, jsonb, jsonb, integer)', '운영진 전용'),
  ('function', 'cancel_build_revision(bigint, text)',        '운영자 전용'),
  ('function', 'cancel_proposal_revision(bigint, text)',     '운영자 전용'),
  ('function', 'create_notice(text, text, text[], boolean)', '운영자 전용'),
  ('function', 'delete_counter(bigint, text, text)',         '운영자 전용'),
  ('function', 'dismiss_link_reports(bigint, text)',         '운영자 전용'),
  ('function', 'dismiss_profile_photo_reports(uuid, text)',  '운영자 전용'),
  ('function', 'dismiss_reports(bigint, bigint, text, bigint)', '운영진 전용'),
  ('function', 'end_proposal_review(bigint)',                '운영진 전용'),
  ('function', 'extend_influencer_application(bigint)',      '운영자 전용'),
  ('function', 'grant_influencer(uuid, text, text)',         '운영자 전용'),
  ('function', 'grant_title(uuid, text, text)',              '운영자 전용'),
  ('function', 'handle_wiki_report(bigint, text, text, boolean)', '운영진 전용'),
  ('function', 'hide_build(bigint, text)',                   '운영진 전용'),
  ('function', 'hide_comment(bigint, text)',                 '운영진 전용'),
  ('function', 'hide_counter(bigint, text)',                 '운영자 전용'),
  ('function', 'hide_doc_comment(bigint, text)',             '운영진 전용'),
  ('function', 'hide_post(bigint, text)',                    '운영진 전용'),
  ('function', 'lift_restriction(bigint, text)',             '운영자 전용 (068)'),
  ('function', 'reject_build(bigint, text, integer)',        '운영자 전용'),
  ('function', 'reject_influencer(bigint, text, boolean, boolean)', '운영자 전용'),
  ('function', 'reject_proposal(bigint, text, integer)',     '운영진 전용'),
  ('function', 'remove_link(bigint, text)',                  '운영진 전용'),
  ('function', 'remove_offmeta(text)',                       '운영자 전용'),
  ('function', 'remove_profile_photo(uuid, text)',           '운영자 전용'),
  ('function', 'reorder_counters(text, bigint[])',           '운영자 전용'),
  ('function', 'request_build_revision(bigint, text, integer)', '운영자 전용'),
  ('function', 'request_proposal_revision(bigint, text, integer)', '운영진 전용'),
  ('function', 'request_revision(bigint, text)',             '운영자 전용'),
  ('function', 'restore_build(bigint, text)',                '운영진 전용'),
  ('function', 'restore_comment(bigint, text)',              '운영진 전용'),
  ('function', 'restore_counter(bigint, text)',              '운영자 전용'),
  ('function', 'restore_doc_comment(bigint, text)',          '운영진 전용'),
  ('function', 'restore_post(bigint, text)',                 '운영진 전용'),
  ('function', 'restrict_user(uuid, integer, text)',         '운영자 전용 (068)'),
  ('function', 'revert_build(bigint, bigint, integer, text)', '운영자 전용'),
  ('function', 'revert_doc(bigint, text)',                   '운영자 전용'),
  ('function', 'revoke_influencer(uuid, text)',              '운영자 전용'),
  ('function', 'revoke_title(uuid, text, text)',             '운영자 전용'),
  ('function', 'set_inquiry_category(bigint, text)',         '운영자 전용'),
  ('function', 'set_item_prices(text, jsonb, jsonb)',        '운영자 전용'),
  ('function', 'set_moderator(uuid, boolean, text)',         '운영자 전용'),
  ('function', 'set_operator_mode(boolean)',                 '운영자 전용'),
  ('function', 'staff_delete_comment(bigint, text)',         '운영진 전용'),
  ('function', 'staff_delete_doc_comment(bigint, text)',     '운영진 전용'),
  ('function', 'staff_delete_post(bigint, text)',            '운영진 전용'),
  ('function', 'start_proposal_review(bigint)',              '운영진 전용'),
  -- 쓰기 정책 (직접 넣기·고치기·지우기)
  ('policy', 'public.push_settings: push_settings: 본인 넣기',         '알림 설정'),
  ('policy', 'public.push_settings: push_settings: 본인 고치기',       '알림 설정'),
  ('policy', 'public.push_subscriptions: push_subscriptions: 본인 넣기', '휴대폰 알림 켜기 (알림 설정)'),
  ('policy', 'public.push_subscriptions: push_subscriptions: 본인 지우기', '휴대폰 알림 끄기 (알림 설정)'),
  ('policy', 'public.user_blocks: user_blocks: 본인이 차단',          '차단'),
  ('policy', 'public.user_blocks: user_blocks: 본인이 해제',          '차단 해제'),
  ('policy', 'public.edit_proposals: edit_proposals: 관리자 삭제',     '운영자 전용'),
  ('policy', 'storage.objects: profile-photos 지우기',                '내 사진 파일 지우기');

-- ---------------------------------------------------------------------
-- 8. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.active_restriction_id(uuid) from public, anon, authenticated;
revoke execute on function public.restriction_message(uuid) from public, anon, authenticated;
revoke execute on function public.assert_can_write() from public, anon, authenticated;
revoke execute on function public.restriction_guard() from public, anon, authenticated;
revoke execute on function public.can_write() from public, anon;
grant execute on function public.can_write() to authenticated;                 -- RLS 정책이 부른다
revoke execute on function public.my_restriction() from public, anon;
grant execute on function public.my_restriction() to authenticated;
revoke execute on function public.restrict_user(uuid, integer, text) from public, anon;
grant execute on function public.restrict_user(uuid, integer, text) to authenticated;          -- 안에서 운영자 확인
revoke execute on function public.lift_restriction(bigint, text) from public, anon;
grant execute on function public.lift_restriction(bigint, text) to authenticated;
revoke execute on function public.admin_member_restrictions(uuid) from public, anon;
grant execute on function public.admin_member_restrictions(uuid) to authenticated;

commit;
