-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 023: 자유게시판 사진·GIF — 올리기 권한(회원만·내 폴더·하루 개수·전체 용량), 붙이기 제한, 보기 권한(숨김),
--      시간 안 고치기, 지우기·삭제된 글·탈퇴 → 지울 파일 대기열, 안 붙은 파일 정리, 운영자 사용량, 신고 사유
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set C '00000000-0000-0000-0000-00000000000c'
\set G '00000000-0000-0000-0000-0000000000a1'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'C', 'c@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '씨' where id = :'C';
update public.profiles set nickname = '손님' where id = :'G';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;

-- 화면이 Storage API로 올리는 것 흉내: 지금 로그인한 사람 권한으로 파일 줄을 넣는다 (규칙 검사를 받는다)
create function pg_temp.up(p_name text, p_mime text default 'image/webp', p_kb integer default 200) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('board-media', p_name, auth.uid(), auth.uid()::text, jsonb_build_object('mimetype', p_mime, 'size', p_kb * 1024));
$$;
create function pg_temp.id(key text) returns bigint language sql as $$ select v from ids where k = key $$;
create function pg_temp.media(p bigint) returns text[] language sql security definer as $$
  select coalesce(array_agg(path order by position), '{}') from public.board_attachments where post_id = p $$;
create function pg_temp.cmedia(c bigint) returns text[] language sql security definer as $$
  select coalesce(array_agg(path order by position), '{}') from public.board_attachments where comment_id = c $$;
create function pg_temp.objs() returns integer language sql security definer as $$
  select count(*)::integer from storage.objects where bucket_id = 'board-media' $$;
create function pg_temp.trash() returns text[] language sql security definer as $$
  select coalesce(array_agg(path order by path), '{}') from public.storage_trash $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

-- ===== 0. 버킷 =====
select t.ok('버킷 board-media: 비공개, 3MB, webp·jpeg·gif',
  (select not public and file_size_limit = 3145728 and allowed_mime_types = array['image/webp','image/jpeg','image/gif']
   from storage.buckets where id = 'board-media'));

-- ===== 1. 올리기 권한 =====
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인은 못 올림', $$select pg_temp.up('x/a.webp')$$, 'row-level security');
set role authenticated;
set request.jwt.claim.sub = :'G';
select t.ok('비회원: 올릴 수 없는 이유', media_upload_problem() like '비회원은 사진을 올릴 수 없어요%');
select t.fails('비회원은 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'G'), 'row-level security');
set request.jwt.claim.sub = :'B';
select t.ok('회원: 올릴 수 있음', media_upload_problem() is null);
select t.fails('남의 폴더에는 못 올림', format($$select pg_temp.up('%s/a.webp')$$, :'C'), 'row-level security');
select pg_temp.up(:'B' || '/p1.webp');
select pg_temp.up(:'B' || '/p2.webp');
select pg_temp.up(:'B' || '/p3.jpg', 'image/jpeg');
select pg_temp.up(:'B' || '/p4.webp');
select pg_temp.up(:'B' || '/p5.webp');
select pg_temp.up(:'B' || '/g1.gif', 'image/gif', 2500);
select pg_temp.up(:'B' || '/g2.gif', 'image/gif', 500);
select pg_temp.up(:'B' || '/big.webp', 'image/webp', 700);
select pg_temp.up(:'B' || '/biggif.gif', 'image/gif', 3100);
select t.ok('내 폴더에 올림', (select count(*) = 9 from storage.objects where owner_id = :'B'));

reset role;
update public.xp_rules set value = 9 where key = 'media_daily_max';
set role authenticated;
select t.ok('하루 개수를 다 쓰면 이유', media_upload_problem() like '사진은 하루에 9개까지%');
select t.fails('하루 개수 초과', format($$select pg_temp.up('%s/over.webp')$$, :'B'), 'row-level security');
reset role;
update public.xp_rules set value = 20 where key = 'media_daily_max';
update public.xp_rules set value = 0 where key = 'media_block_mb';
set role authenticated;
select t.ok('전체 용량이 차면 이유', media_upload_problem() like '지금은 사진 저장 공간이 거의 차서%');
reset role;
update public.xp_rules set value = 900 where key = 'media_block_mb';
set role authenticated;

-- ===== 2. 글에 붙이기 =====
select t.fails('사진 5개는 안 됨', format($$select create_post('제목', '본문', array['%1$s/p1.webp','%1$s/p2.webp','%1$s/p3.jpg','%1$s/p4.webp','%1$s/p5.webp'])$$, :'B'), '글에는 사진을 4개까지');
select t.fails('GIF 2개는 안 됨', format($$select create_post('제목', '본문', array['%1$s/g1.gif','%1$s/g2.gif'])$$, :'B'), 'GIF는 글 하나에 1개까지');
select t.fails('큰 사진은 안 됨', format($$select create_post('제목', '본문', array['%1$s/big.webp'])$$, :'B'), '사진이 너무 커요');
select t.fails('3MB 넘는 GIF는 안 됨', format($$select create_post('제목', '본문', array['%1$s/biggif.gif'])$$, :'B'), 'GIF는 3MB까지');
select t.fails('없는 파일은 안 됨', format($$select create_post('제목', '본문', array['%1$s/none.webp'])$$, :'B'), '올린 사진을 찾지 못했어요');
select t.fails('같은 사진 두 번은 안 됨', format($$select create_post('제목', '본문', array['%1$s/p1.webp','%1$s/p1.webp'])$$, :'B'), '같은 사진이 두 번');
select t.fails('사진도 본문도 없으면 안 됨', $$select create_post('제목', '  ')$$, '본문을 적어 주세요');
select t.ok('막히면 글이 안 생김', (select count(*) = 0 from posts));

insert into ids select 'p', create_post('사진 글', '', array[:'B' || '/p2.webp', :'B' || '/g1.gif', :'B' || '/p1.webp']);
select t.ok('사진만 있으면 본문은 비워도 됨, 고른 순서대로',
  pg_temp.media(pg_temp.id('p')) = array[:'B' || '/p2.webp', :'B' || '/g1.gif', :'B' || '/p1.webp']
  and (select body = '' from posts where id = pg_temp.id('p')));
select t.ok('첨부 줄에 형식·크기',
  (select mime = 'image/gif' and size = 2500 * 1024 from board_attachments where path = :'B' || '/g1.gif'));
select t.fails('이미 붙은 사진은 다른 글에 못 붙임', format($$select create_post('제목', '본문', array['%1$s/p1.webp'])$$, :'B'), '다른 글·댓글에 붙은 사진');
select t.fails('표에 직접 넣기 불가', format($$insert into board_attachments (post_id, author_id, path, mime, size) values (%s, auth.uid(), 'x', 'image/webp', 1)$$, pg_temp.id('p')), 'permission denied');
select t.ok('목록에 사진 수', (select (r ->> 'media_count')::int = 3 from jsonb_array_elements(board_page() -> 'rows') r where (r ->> 'id')::bigint = pg_temp.id('p')));

-- 남의 파일은 못 붙임
set request.jwt.claim.sub = :'C';
select pg_temp.up(:'C' || '/c1.webp');
select pg_temp.up(:'C' || '/c2.gif', 'image/gif', 300);
select t.fails('남이 올린 파일은 못 붙임', format($$select create_post('제목', '본문', array['%s/p3.jpg'])$$, :'B'), '올린 사진을 찾지 못했어요');

-- 비회원은 붙일 수 없음 (파일이 있어도)
reset role;
insert into storage.objects (bucket_id, name, owner_id, metadata) values ('board-media', :'G' || '/g.webp', :'G', '{"mimetype":"image/webp","size":1000}');
set role authenticated;
set request.jwt.claim.sub = :'G';
select t.fails('비회원은 사진을 붙일 수 없음', format($$select create_post('제목', '본문', array['%s/g.webp'])$$, :'G'), '비회원은 사진을 올릴 수 없어요');
select t.ok('비회원도 사진 없는 글은 씀', create_post('손님 글', '본문') > 0);

-- ===== 3. 보기 권한 =====
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인: 보이는 글의 사진 줄·파일을 봄',
  (select count(*) = 3 from board_attachments where post_id = pg_temp.id('p'))
  and (select count(*) = 3 from storage.objects where name like :'B' || '/%'));
set role authenticated;
set request.jwt.claim.sub = :'C';
select t.ok('남: 안 붙은 남의 파일은 못 봄', (select count(*) = 0 from storage.objects where name = :'B' || '/p3.jpg'));
set request.jwt.claim.sub = :'B';
select t.ok('나: 안 붙은 내 파일도 봄', (select count(*) = 1 from storage.objects where name = :'B' || '/p3.jpg'));

set request.jwt.claim.sub = :'A';
select hide_post(pg_temp.id('p'), '사진 문제');
select t.ok('운영자: 숨긴 글의 사진도 봄', (select count(*) = 3 from board_attachments where post_id = pg_temp.id('p'))
  and (select count(*) = 1 from storage.objects where name = :'B' || '/g1.gif'));
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인: 숨긴 글의 사진은 못 봄', (select count(*) = 0 from board_attachments where post_id = pg_temp.id('p'))
  and (select count(*) = 0 from storage.objects where name = :'B' || '/g1.gif'));
set role authenticated;
set request.jwt.claim.sub = :'A';
select restore_post(pg_temp.id('p'), '괜찮아요');
set role anon;
select t.ok('다시 공개하면 다시 보임', (select count(*) = 1 from storage.objects where name = :'B' || '/g1.gif'));

-- ===== 4. 고치기 (시간 안에서만) =====
set role authenticated;
set request.jwt.claim.sub = :'B';
select edit_post(pg_temp.id('p'), '사진 글', '', null);
select t.ok('사진 칸 null이면 그대로 (수정됨도 안 붙음)',
  cardinality(pg_temp.media(pg_temp.id('p'))) = 3 and (select edited_at is null from posts where id = pg_temp.id('p')));
select edit_post(pg_temp.id('p'), '사진 글', '', array[:'B' || '/p1.webp', :'B' || '/p3.jpg', :'B' || '/p2.webp']);
select t.ok('빼고·더하고·순서 바꾸기', pg_temp.media(pg_temp.id('p')) = array[:'B' || '/p1.webp', :'B' || '/p3.jpg', :'B' || '/p2.webp']
  and (select edited_at is not null from posts where id = pg_temp.id('p')));
select t.ok('뺀 사진은 지울 파일 대기열로', pg_temp.trash() = array[:'B' || '/g1.gif']);
select t.fails('사진을 다 빼면 본문이 있어야', format($$select edit_post(%s, '사진 글', '', '{}')$$, pg_temp.id('p')), '본문을 적어 주세요');
insert into ids select 'p2', create_post('두 번째', '본문', array[:'B' || '/g1.gif']);
select t.ok('빼 둔 내 사진을 다시 붙이면 대기열에서 빠짐', pg_temp.trash() = '{}' and pg_temp.media(pg_temp.id('p2')) = array[:'B' || '/g1.gif']);
reset role;
update posts set created_at = now() - interval '2 hours', edit_grace_until = null where id = pg_temp.id('p');
set role authenticated;
select t.fails('시간이 지나면 사진도 못 바꿈', format($$select edit_post(%s, '사진 글', '', array['%s/p1.webp'])$$, pg_temp.id('p'), :'B'), '고칠 수 있는 시간이 지났어요');
select t.ok('막히면 그대로', cardinality(pg_temp.media(pg_temp.id('p'))) = 3);

-- ===== 5. 댓글 =====
set request.jwt.claim.sub = :'C';
select t.fails('댓글에는 1개만', format($$select create_comment(%s, '', array['%2$s/c1.webp','%2$s/c2.gif'])$$, pg_temp.id('p'), :'C'), '댓글에는 사진을 1개까지');
insert into ids select 'c', create_comment(pg_temp.id('p'), '', array[:'C' || '/c2.gif']);
select t.ok('사진만 있는 댓글 (GIF)', pg_temp.cmedia(pg_temp.id('c')) = array[:'C' || '/c2.gif']);
select t.fails('사진을 빼면 댓글 글자가 있어야', format($$select edit_comment(%s, '', '{}')$$, pg_temp.id('c')), '댓글을 적어 주세요');
select edit_comment(pg_temp.id('c'), '움짤', array[:'C' || '/c1.webp']);
select t.ok('댓글 사진 바꾸기 → 뺀 것은 대기열', pg_temp.cmedia(pg_temp.id('c')) = array[:'C' || '/c1.webp'] and pg_temp.trash() = array[:'C' || '/c2.gif']);

-- ===== 6. 지우기 =====
set request.jwt.claim.sub = :'B';
select report_comment(pg_temp.id('c'), 'obscene');
reset role;
select t.ok('신고 사유: 음란·잔혹한 사진', (select count(*) = 1 from reports where comment_id = pg_temp.id('c') and reason = 'obscene'));
set role authenticated;
select delete_my_post(pg_temp.id('p'));
select t.ok('다른 사람 댓글이 있어 "삭제된 글"로 남아도 글의 사진은 대기열로, 남의 댓글 사진은 그대로',
  pg_temp.media(pg_temp.id('p')) = '{}'
  and pg_temp.trash() @> array[:'B' || '/p1.webp', :'B' || '/p2.webp', :'B' || '/p3.jpg']
  and pg_temp.cmedia(pg_temp.id('c')) = array[:'C' || '/c1.webp']);
set request.jwt.claim.sub = :'C';
select delete_my_comment(pg_temp.id('c'));
select t.ok('댓글을 지우면 사진도 대기열로', pg_temp.trash() @> array[:'C' || '/c1.webp']);
set request.jwt.claim.sub = :'B';
select delete_my_post(pg_temp.id('p2'));
select t.ok('글을 완전히 지우면 사진도 대기열로', pg_temp.trash() @> array[:'B' || '/g1.gif']);

-- 탈퇴: 내 글의 사진도 대기열로
insert into ids select 'p3', create_post('탈퇴 전 글', '본문', array[:'B' || '/p4.webp']);
reset role;
delete from auth.users where id = :'B';
select t.ok('탈퇴하면 사진도 대기열로', pg_temp.trash() @> array[:'B' || '/p4.webp'] and (select count(*) = 0 from board_attachments));

-- ===== 7. 정리 (service_role) =====
set role authenticated;
set request.jwt.claim.sub = :'C';
select t.fails('일반 유저는 정리 목록 못 봄', $$select media_cleanup_list()$$, 'permission denied');
reset role;
update storage.objects set created_at = now() - interval '25 hours' where name = :'B' || '/p5.webp';
set role service_role;
select t.ok('정리 목록: 대기열 + 오래된 안 붙은 파일 (막 올린 파일은 빼고)',
  (select media_cleanup_list(1000) @> (pg_temp.trash() || array[:'B' || '/p5.webp']))
  and not (select media_cleanup_list(1000) @> array[:'B' || '/big.webp']));
select media_cleanup_done(pg_temp.trash());
select t.ok('지운 경로는 대기열에서 빠짐', pg_temp.trash() = '{}');

-- ===== 8. 운영자 사용량 =====
set role authenticated;
set request.jwt.claim.sub = :'C';
select t.fails('일반 유저는 사용량 못 봄', $$select media_usage()$$, '운영자만');
set request.jwt.claim.sub = :'A';
select t.ok('운영자 사용량: 바이트·파일 수·GIF·기준',
  (select (u ->> 'files')::int = pg_temp.objs()
      and (u ->> 'bytes')::bigint > 0 and (u ->> 'gifs')::int >= 1
      and (u ->> 'total_mb')::int = 1024 and (u ->> 'warn_mb')::int = 800 and (u ->> 'block_mb')::int = 900
      and jsonb_array_length(u -> 'top') >= 1
   from (select media_usage() as u) x));
