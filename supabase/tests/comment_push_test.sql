-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_comment_push_after.sql)
-- 074 댓글·답글 푸시 묶음 comments: push_group에 댓글 3종 → 'comments', push_wanted에 push_settings.comments(기본 켜짐),
--   두 함수 본문은 그 줄만 더해짐(되빼면 069·073 지문), 기존 종류는 모든 사람 × 모든 종류에서 전과 같은 판정, 설정 칸 기본값·권한·옛 앱 저장,
--   실제 댓글·답글(글·상대법 문서) → 트리거가 Edge Function을 부름, 안 읽은 동안 더 달린 댓글은 「N개」로 고쳐지고 다시 부르지 않음,
--   읽은 뒤 댓글은 다시 부름, 끈 사람·기기 없는 사람은 알림만 생기고 안 부름, push_targets 내용, 068 쓰기 함수 수 그대로.
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
\set F '00000000-0000-0000-0000-00000000000f'
\set X '00000000-0000-0000-0000-0000000000c1'
\set M '00000000-0000-0000-0000-0000000000e1'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'D', 'd@x.com'), (:'F', 'f@x.com'), (:'X', 'x@x.com'), (:'M', 'm@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비이' where id = :'B';
update public.profiles set nickname = '디이' where id = :'D';
update public.profiles set nickname = '에프' where id = :'F';
update public.profiles set nickname = '엑스' where id = :'X';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'M';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
create function pg_temp.tk(n int) returns text language sql immutable as $$ select md5('tok' || n) || md5('ken' || n) $$;

-- 비교 기준: 069 push_group 본문, 073 push_wanted 본문 그대로 (074 전)
create function pg_temp.old_group(p_kind text) returns text language sql immutable as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored',
                    'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
                    'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
                    'profile_photo_removed',
                    'warning_received') then 'my_results'
    when p_kind in ('followed_build_created') then 'follow_builds'
    when p_kind in ('notice_posted') then 'notice'
    when p_kind in ('new_followers') then 'new_followers'
    when p_kind in ('build_edited') then 'build_edits'
  end $$;
create function pg_temp.old_wanted(p_user uuid, p_kind text) returns boolean language sql stable as $$
  select case pg_temp.old_group(p_kind)
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
      coalesce((select s.new_followers from public.push_settings s where s.user_id = p_user), false)
    when 'build_edits' then
      coalesce((select s.build_edits from public.push_settings s where s.user_id = p_user), true)
    else false
  end
  and (exists (select 1 from public.push_subscriptions where user_id = p_user)
       or exists (select 1 from public.device_push_tokens where user_id = p_user)) $$;
create function pg_temp.kinds() returns setof text language sql stable as $$
  select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] from pg_constraint where conname = 'notifications_kind_check'
  union select 'no_such_kind' $$;
create function pg_temp.is_comment(k text) returns boolean language sql immutable as $$ select k in ('post_comment', 'doc_comment', 'comment_reply') $$;
-- 트리거가 그 사람의 그 종류 알림으로 Edge Function을 부른 횟수
create function pg_temp.calls(u uuid, k text) returns integer language sql stable as $$
  select count(*)::int from net.calls c join public.notifications n on n.id = (c.body ->> 'notification_id')::bigint where n.user_id = u and n.kind = k $$;
create function pg_temp.notes(u uuid, k text) returns integer language sql stable as $$
  select count(*)::int from public.notifications where user_id = u and kind = k $$;
create function pg_temp.msg(u uuid, k text) returns text language sql stable as $$
  select message from public.notifications where user_id = u and kind = k order by id desc limit 1 $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- 기기: B 웹 구독, D 앱 토큰, F 앱 토큰(댓글 알림 끔 예정), M 감독관 웹 구독, X 기기 없음, A 운영자 앱 토큰
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth) values (:'B', 'https://push.example/b', 'k', 'a'), (:'M', 'https://push.example/m', 'k', 'a');
insert into public.device_push_tokens (user_id, platform, token) values (:'D', 'ios', pg_temp.tk(1)), (:'F', 'android', pg_temp.tk(2)), (:'A', 'ios', pg_temp.tk(3));
-- 074 전부터 있던 설정 줄 흉내: M은 내 결과 알림을 꺼 둠 (comments 칸은 074가 기본값 true로 채움)
insert into public.push_settings (user_id, my_results) values (:'M', false);
insert into vault.decrypted_secrets values ('push_function_url', 'https://fn.test/functions/v1/web-push'), ('push_webhook_secret', 's3cret');

-- ===== 1. 함수 본문: 줄 하나씩만 더해짐, 모양·권한 그대로 =====
select t.ok('본문 지문: push_group 2be75ed9… / push_wanted fa8eb83c… (074 파일 그대로)',
  (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.push_group(text)'::regprocedure) = '2be75ed999aa158e20557beda4db0814'
  and (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure) = 'fa8eb83cd5786a7155e5f2439917b04e');
select t.ok('더한 줄을 빼면 069 push_group(ba44f97f…) · 073 push_wanted(e6f1723a…) 본문 그대로',
  (select md5(replace(replace(prosrc, E'\r', ''), E'\n    when p_kind in (''post_comment'', ''doc_comment'', ''comment_reply'') then ''comments''  -- 074 댓글·답글', ''))
     from pg_proc where oid = 'public.push_group(text)'::regprocedure) = 'ba44f97f41cc99cbb3590c8528ace024'
  and (select md5(replace(replace(prosrc, E'\r', ''), E'\n    when ''comments'' then\n      coalesce((select s.comments from public.push_settings s where s.user_id = p_user), true)  -- 074 댓글·답글', ''))
     from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure) = 'e6f1723ae3a6b0126ece4b51488a067c');
select t.ok('모양 그대로: push_group(text) text immutable · push_wanted(uuid,text) boolean stable security definer, search_path "", 같은 이름 1개씩', (
  select prorettype = 'text'::regtype and provolatile = 'i' and not prosecdef and proconfig = array['search_path=""']
    from pg_proc where oid = 'public.push_group(text)'::regprocedure)
  and (select prorettype = 'boolean'::regtype and provolatile = 's' and prosecdef and proconfig = array['search_path=""']
    from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure)
  and (select count(*) from pg_proc where proname in ('push_group', 'push_wanted')) = 2);
select t.ok('push_wanted 실행 권한 그대로 (anon·authenticated·service_role 모두 없음)',
  not has_function_privilege('anon', 'public.push_wanted(uuid, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.push_wanted(uuid, text)', 'execute')
  and not has_function_privilege('service_role', 'public.push_wanted(uuid, text)', 'execute'));
select t.ok('068 쓰기 함수 수: 105 / 첫 줄 검사 31 / 허용 목록 74 (080 set_my_champion · 081 unselect_my_champion 포함)', (
  select count(*) = 105
     and count(*) filter (where p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);') = 31
     and count(*) filter (where exists (select 1 from public.restriction_exemptions e where e.kind = 'function'
                                         and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')')) = 74
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));

-- ===== 2. 묶음: 댓글 3종만 comments, 나머지는 전과 같음 =====
select t.ok('댓글 3종 → comments', push_group('post_comment') = 'comments' and push_group('doc_comment') = 'comments' and push_group('comment_reply') = 'comments');
select t.ok('comments 묶음은 댓글 3종뿐 (숨김·삭제·다시 공개 알림 등은 여전히 묶음 없음)',
  (select array_agg(k order by k) from pg_temp.kinds() k where push_group(k) = 'comments') = array['comment_reply', 'doc_comment', 'post_comment']
  and push_group('comment_hidden') is null and push_group('doc_comment_deleted') is null and push_group('post_restored') is null);
select t.ok('모든 알림 종류: 댓글 3종을 뺀 종류의 묶음은 069와 같음, 댓글 3종은 전에 없었음',
  (select bool_and(push_group(k) is not distinct from pg_temp.old_group(k)) from pg_temp.kinds() k where not pg_temp.is_comment(k))
  and (select bool_and(pg_temp.old_group(k) is null) from pg_temp.kinds() k where pg_temp.is_comment(k)));
select t.ok('검사 범위: 알림 종류 50개 이상', (select count(*) from pg_temp.kinds()) >= 50);

-- ===== 3. 설정 칸 comments =====
select t.ok('칸 comments: boolean not null default true, 074 전부터 있던 줄(M)도 켜짐',
  (select data_type = 'boolean' and is_nullable = 'NO' and column_default = 'true' from information_schema.columns
    where table_schema = 'public' and table_name = 'push_settings' and column_name = 'comments')
  and (select comments from public.push_settings where user_id = :'M'));
select t.ok('권한: 로그인 사용자는 이 칸을 고칠 수 있고(본인 줄만, RLS), 비로그인은 못 함',
  has_column_privilege('authenticated', 'public.push_settings', 'comments', 'update')
  and has_column_privilege('authenticated', 'public.push_settings', 'comments', 'insert')
  and not has_column_privilege('anon', 'public.push_settings', 'comments', 'update'));
set role authenticated;
set request.jwt.claim.sub = :'F';
insert into push_settings (user_id, staff_new, my_results, follow_builds, notice, new_followers, build_edits, comments, updated_at)
values (auth.uid(), true, true, true, true, false, true, false, now())
on conflict (user_id) do update set comments = excluded.comments, updated_at = excluded.updated_at;
select t.ok('새 화면 저장(upsert)으로 본인 댓글 알림 끄기', not (select comments from push_settings where user_id = auth.uid()));
-- 옛 앱 1.1·1.2의 저장: comments 칸을 모른다 → 그 칸은 그대로
insert into push_settings (user_id, staff_new, my_results, follow_builds, notice, new_followers, build_edits, updated_at)
values (auth.uid(), true, false, true, true, false, true, now())
on conflict (user_id) do update set staff_new = excluded.staff_new, my_results = excluded.my_results, follow_builds = excluded.follow_builds,
  notice = excluded.notice, new_followers = excluded.new_followers, build_edits = excluded.build_edits, updated_at = excluded.updated_at;
select t.ok('옛 앱 저장(comments 없이 upsert): 다른 칸만 바뀌고 댓글 알림 끔은 그대로', (select not comments and not my_results from push_settings where user_id = auth.uid()));
update push_settings set my_results = true where user_id = auth.uid();
set request.jwt.claim.sub = :'X';
insert into push_settings (user_id, staff_new, my_results, follow_builds, notice, new_followers, build_edits, updated_at)
values (auth.uid(), true, true, true, true, false, true, now())
on conflict (user_id) do update set my_results = excluded.my_results;
select t.ok('옛 앱이 새 줄을 만들면 comments는 기본값(켜짐)', (select comments from push_settings where user_id = auth.uid()));
update push_settings set comments = true where user_id = :'F';  -- RLS: X에게 F의 줄은 보이지 않아 0줄
reset role;
select t.ok('남의 설정은 못 고침: X가 F의 댓글 알림을 켜려 해도 F는 그대로 끔, X는 켬',not (select comments from push_settings where user_id = :'F') and (select comments from push_settings where user_id = :'X'));
delete from push_settings where user_id = :'X';

-- ===== 4. 사람별 판정 =====
select t.ok('웹 구독(B)·앱 토큰(D)·감독관 웹(M) → 댓글 3종 true', (
  select bool_and(push_wanted(u, k)) from unnest(array[:'B', :'D', :'M']::uuid[]) u, unnest(array['post_comment', 'doc_comment', 'comment_reply']) k));
select t.ok('기기 없음(X) → false, 댓글 알림 끔(F, 앱 토큰 있음) → false', (
  select bool_and(not push_wanted(u, k)) from unnest(array[:'X', :'F']::uuid[]) u, unnest(array['post_comment', 'doc_comment', 'comment_reply']) k));
select t.ok('댓글을 꺼도 다른 묶음은 그대로 (F: 내 결과·공지 true)', push_wanted(:'F', 'link_removed') and push_wanted(:'F', 'notice_posted'));
select t.ok('다른 묶음을 꺼도 댓글은 그대로 (M: 내 결과 끔 → 내 결과 false, 댓글 true)', not push_wanted(:'M', 'link_removed') and push_wanted(:'M', 'post_comment'));
insert into public.push_settings (user_id, staff_new, my_results, follow_builds, notice, new_followers, build_edits, comments)
values (:'D', false, false, false, false, false, false, true);
select t.ok('다른 묶음을 모두 꺼도 댓글만 켜 두면 댓글만 true (D)',
  push_wanted(:'D', 'comment_reply') and (select bool_and(not push_wanted(:'D', k)) from pg_temp.kinds() k where not pg_temp.is_comment(k)));
delete from public.push_settings where user_id = :'D';
select t.ok('모든 사람 × 댓글 3종을 뺀 모든 종류: push_wanted가 073과 같음 (운영자·감독관·설정 끔·기기 없음 포함)', (
  select bool_and(push_wanted(p.id, k) = pg_temp.old_wanted(p.id, k)) from public.profiles p, pg_temp.kinds() k where not pg_temp.is_comment(k)));
update public.profiles set operator_mode = false where id = :'A';
select t.ok('운영자 모드를 꺼도 위와 같음 (운영진 알림 false, 댓글은 그대로 true)', (
  select bool_and(push_wanted(p.id, k) = pg_temp.old_wanted(p.id, k)) from public.profiles p, pg_temp.kinds() k where not pg_temp.is_comment(k))
  and not push_wanted(:'A', 'post_created') and push_wanted(:'A', 'post_comment'));
update public.profiles set operator_mode = true where id = :'A';
select t.ok('모든 사람 × 댓글 3종: 073에선 false, 지금은 「설정 켬(기본) and (웹 or 앱)」', (
  select bool_and(not pg_temp.old_wanted(p.id, k)
                  and push_wanted(p.id, k) = (coalesce((select s.comments from public.push_settings s where s.user_id = p.id), true)
                                              and (exists (select 1 from public.push_subscriptions s where s.user_id = p.id)
                                                   or exists (select 1 from public.device_push_tokens d where d.user_id = p.id))))
    from public.profiles p, pg_temp.kinds() k where pg_temp.is_comment(k)));

-- ===== 5. 실제 글 댓글: 트리거가 부름, 안 읽은 동안은 「N개」로 고쳐지고 다시 안 부름 =====
delete from net.calls;
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_post('B 글', '본문') as p1 \gset
set request.jwt.claim.sub = :'D';
select create_comment(:p1, 'D 댓글') as c1 \gset
reset role;
select t.ok('글 댓글 → 글 주인(B, 웹)에게 post_comment 1줄 + Edge Function 1번', pg_temp.notes(:'B', 'post_comment') = 1 and pg_temp.calls(:'B', 'post_comment') = 1);
select t.ok('부르는 내용은 그대로 (주소·비밀 값 헤더·알림 번호만)', (select bool_and(url = 'https://fn.test/functions/v1/web-push'
  and headers ->> 'x-push-secret' = 's3cret' and (select array_agg(k) from jsonb_object_keys(body) k) = array['notification_id']) from net.calls));
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_comment(:p1, 'F 댓글') as c2 \gset
set request.jwt.claim.sub = :'M';
select create_comment(:p1, 'M 댓글') as c3 \gset
reset role;
select t.ok('안 읽은 동안 댓글 2개 더: 새 줄 없이 문장만 「새 댓글 3개」, Edge Function은 그대로 1번 (다시 안 울림)',
  pg_temp.notes(:'B', 'post_comment') = 1 and pg_temp.msg(:'B', 'post_comment') = '내 글 「B 글」에 새 댓글 3개가 달렸습니다.'
  and pg_temp.calls(:'B', 'post_comment') = 1);
select id as bn from public.notifications where user_id = :'B' and kind = 'post_comment' \gset
select public.push_targets(:bn) as tb \gset
select t.ok('push_targets: 지금 문장(「새 댓글 3개」)·글 번호·웹 구독 1개 → Edge Function이 그 글로 보냄',
  (:'tb'::jsonb -> 'notification' ->> 'kind') = 'post_comment' and (:'tb'::jsonb -> 'notification' ->> 'post_id')::bigint = :p1
  and (:'tb'::jsonb -> 'notification' ->> 'message') like '%새 댓글 3개%' and jsonb_array_length(:'tb'::jsonb -> 'subscriptions') = 1);
set role authenticated;
set request.jwt.claim.sub = :'B';
select mark_notifications_read(array[:bn]::bigint[]) as marked \gset
set request.jwt.claim.sub = :'D';
select create_comment(:p1, 'D 두 번째 댓글') as c4 \gset
reset role;
select t.ok('읽은 뒤 달린 댓글: 새 줄 + Edge Function 한 번 더 (모두 2번)', pg_temp.notes(:'B', 'post_comment') = 2 and pg_temp.calls(:'B', 'post_comment') = 2);

-- 답글: 부모 댓글 작성자에게 comment_reply
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_comment(:p1, 'B 답글', '{}', :c1) as r1 \gset
reset role;
select t.ok('글 답글 → 부모 댓글 작성자(D, 앱만)에게 comment_reply + Edge Function 1번', pg_temp.notes(:'D', 'comment_reply') = 1 and pg_temp.calls(:'D', 'comment_reply') = 1);
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_comment(:p1, 'D 답글', '{}', :c2) as r2 \gset
reset role;
select t.ok('댓글 알림을 끈 F: 답글 알림 줄은 생기지만(앱 안 목록) Edge Function은 안 부름', pg_temp.notes(:'F', 'comment_reply') = 1 and pg_temp.calls(:'F', 'comment_reply') = 0);
set role authenticated;
set request.jwt.claim.sub = :'X';
select create_post('X 글', '본문') as px \gset
set request.jwt.claim.sub = :'D';
select create_comment(:px, 'X 글에 댓글') as cx \gset
reset role;
select t.ok('기기가 없는 X: 알림 줄만 생기고 Edge Function은 안 부름', pg_temp.notes(:'X', 'post_comment') = 1 and pg_temp.calls(:'X', 'post_comment') = 0);
select t.ok('새 수신 대상 없음: 댓글 단 본인·관계없는 사람(운영자 A·감독관 M)에게 댓글 알림이 생기지 않음',
  pg_temp.notes(:'D', 'post_comment') = 0 and pg_temp.notes(:'A', 'post_comment') = 0 and pg_temp.notes(:'M', 'post_comment') = 0
  and pg_temp.notes(:'A', 'comment_reply') = 0);

-- ===== 6. 상대법 문서 댓글: 처음 제안한 사람(B)에게 doc_comment =====
set role authenticated;
set request.jwt.claim.sub = :'B';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build());
reset role;
select id as garen_p from edit_proposals where counter_champion = 'Garen' \gset
set role authenticated;
set request.jwt.claim.sub = :'A';
select approve_proposal(:garen_p, '좋습니다', null, null, 1) as garen \gset
set request.jwt.claim.sub = :'D';
select create_doc_comment(:garen, 'D 문서 댓글') as d1 \gset
reset role;
select t.ok('문서 댓글 → 처음 제안한 B에게 doc_comment + Edge Function 1번', pg_temp.notes(:'B', 'doc_comment') = 1 and pg_temp.calls(:'B', 'doc_comment') = 1);
select id as dn from public.notifications where user_id = :'B' and kind = 'doc_comment' \gset
select public.push_targets(:dn) as td \gset
select t.ok('push_targets: 상대법 번호·챔피언(Darius·Garen) → Edge Function이 그 상대법 댓글 칸으로 보냄',
  (:'td'::jsonb -> 'notification' ->> 'counter_id')::bigint = :garen and (:'td'::jsonb -> 'notification' ->> 'target_champion') = 'Darius'
  and (:'td'::jsonb -> 'notification' ->> 'counter_champion') = 'Garen' and (:'td'::jsonb -> 'notification' ->> 'post_id') is null);
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_doc_comment(:garen, 'B 문서 답글', :d1) as d2 \gset
reset role;
select t.ok('문서 답글 → 부모 작성자 D에게 comment_reply(post_id 없음) + Edge Function (D 답글 알림 모두 2번)',
  pg_temp.calls(:'D', 'comment_reply') = 2
  and exists (select 1 from public.notifications where user_id = :'D' and kind = 'comment_reply' and post_id is null and counter_id = :garen));
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_doc_comment(:garen, 'F 문서 댓글') as d3 \gset
reset role;
select t.ok('안 읽은 문서 댓글 알림이 있으면 「새 댓글 2개」로 고쳐지고 다시 안 부름',
  pg_temp.notes(:'B', 'doc_comment') = 1 and pg_temp.msg(:'B', 'doc_comment') = '내가 제안한 상대법 문서에 새 댓글 2개가 달렸습니다.'
  and pg_temp.calls(:'B', 'doc_comment') = 1);

-- ===== 7. 댓글이 아닌 알림의 부르기는 전과 같음 =====
delete from net.calls;
insert into public.notifications (user_id, kind, message) values
  (:'B', 'link_removed', '내 결과'), (:'M', 'link_removed', '내 결과 끔'), (:'M', 'inquiry_received', '감독관 운영진'), (:'B', 'comment_hidden', '숨김');
select t.ok('다른 종류: 켠 사람만 부름, 끈 묶음·묶음 없는 종류(댓글 숨김)는 안 부름 (073과 같음)',
  pg_temp.calls(:'B', 'link_removed') = 1 and pg_temp.calls(:'M', 'link_removed') = 0 and pg_temp.calls(:'M', 'inquiry_received') = 1
  and pg_temp.calls(:'B', 'comment_hidden') = 0);
