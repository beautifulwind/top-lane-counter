-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 029: 닉네임에 (운)·(감) 금지 (전각·대괄호·띄어쓰기·보이지 않는 글자 변형 포함) + 자주 쓰는 아이템 삭제
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
insert into auth.users (id, email, raw_app_meta_data) values
  (:'A', 'op@x.com', '{"provider":"kakao","providers":["kakao"]}'),
  (:'B', 'b@x.com', '{"provider":"kakao","providers":["kakao"]}');
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';

-- ===== 1. 판정 함수 =====
select t.ok('막는 모양', (select bool_and(public.nickname_reserved(n)) from unnest(array[
  '(운)', '(감)', '영자(운)', '(운)영자', '탑(감)신',
  U&'\FF08\C6B4\FF09', U&'\FF08\AC10\FF09', '[운]', '[감]', U&'\3010\C6B4\3011', U&'\300C\AC10\300D', '<운>', U&'\3014\C6B4\3015',
  '( 운 )', U&'(\3000\AC10\3000)', '( 운)', '(감 )', U&'(\200B\C6B4\200B)', U&'(\3164\C6B4)', U&'(\C6B4\00AD)',
  '(운]', U&'\FF3B\C6B4\FF3D', U&'\FE59\AC10\FE5A'
]) as n));
select t.ok('통과하는 모양', (select not bool_or(public.nickname_reserved(n)) from unnest(array[
  '영자', '운영자', '감독', '운', '감', '(운영)', '(감독)', '탑(고수)', '운)', '(감', '탑 운 감'
]) as n));

-- ===== 2. DB 막기 (처음 정하기·바꾸기, 운영자도 같음) =====
set role authenticated;
set request.jwt.claim.sub = :'B';
update public.profiles set nickname = '비' where id = auth.uid();
select t.ok('보통 닉네임은 됨', (select nickname = '비' from profiles where id = auth.uid()));
select t.fails('(운) 넣기', $$update public.profiles set nickname = '비(운)' where id = auth.uid()$$, '쓸 수 없습니다');
select t.fails('(감) 넣기', $$update public.profiles set nickname = '(감)비' where id = auth.uid()$$, '쓸 수 없습니다');
select t.fails('전각 괄호', $$update public.profiles set nickname = U&'\FF08\C6B4\FF09' where id = auth.uid()$$, '쓸 수 없습니다');
select t.fails('대괄호', $$update public.profiles set nickname = '[감]비' where id = auth.uid()$$, '쓸 수 없습니다');
select t.fails('띄어쓰기', $$update public.profiles set nickname = '( 운 )' where id = auth.uid()$$, '쓸 수 없습니다');
select t.ok('막힌 뒤에도 닉네임 그대로', (select nickname = '비' from profiles where id = auth.uid()));
set request.jwt.claim.sub = :'A';
select t.fails('운영자도 닉네임에 (운)은 못 넣음 (표시는 화면이 붙임)', $$update public.profiles set nickname = '영자(운)' where id = auth.uid()$$, '쓸 수 없습니다');
reset role;

-- 처음 정하기(INSERT)도 막는다
insert into auth.users (id, email, raw_app_meta_data) values ('00000000-0000-0000-0000-00000000000c', 'c@x.com', '{"provider":"kakao","providers":["kakao"]}');
select t.fails('처음 정할 때도 막음', $$update public.profiles set nickname = '씨(운)' where id = '00000000-0000-0000-0000-00000000000c'$$, '쓸 수 없습니다');

-- 이미 예약어가 들어 있는 사람: 닉네임을 안 바꾸는 수정은 막지 않는다
alter table public.profiles disable trigger profiles_nickname_reserved;
update public.profiles set nickname = '옛(감)' where id = '00000000-0000-0000-0000-00000000000c';
alter table public.profiles enable trigger profiles_nickname_reserved;
update public.profiles set main_title = null where id = '00000000-0000-0000-0000-00000000000c';
select t.ok('닉네임을 안 바꾸면 다른 칸 수정은 됨', true);
select t.ok('걸리는 기존 닉네임 찾기', (select count(*) = 1 from profiles where public.nickname_reserved(nickname)));

-- ===== 3. 자주 쓰는 아이템은 없어짐, 핵심 템트리 종류 검사는 그대로 =====
select t.ok('frequent_items 표 없음', to_regclass('public.frequent_items') is null);
select t.ok('add/remove 함수 없음', not exists (select 1 from pg_proc where proname in ('add_frequent_item', 'remove_frequent_item')));
select t.ok('아이템 종류 칸은 그대로', exists (select 1 from information_schema.columns where table_name = 'item_prices' and column_name = 'kind'));
select t.ok('핵심 템트리 검사 트리거는 그대로', exists (select 1 from pg_proc where proname = 'check_core_items'));
