-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 008: 빌드 등록(내용 검사) → 승인·거절·숨기기·다시 공개(메모 필수, 기록, 알림) / 추천(함수로만, 기록) / 탈퇴 처리
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'op@x.com'),
  ('00000000-0000-0000-0000-00000000000b', 'u@x.com'),
  ('00000000-0000-0000-0000-00000000000c', 'new@x.com'),
  ('00000000-0000-0000-0000-00000000000d', 'u2@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';
update public.profiles set nickname = '유저' where id = '00000000-0000-0000-0000-00000000000b';
update public.profiles set nickname = '유저2' where id = '00000000-0000-0000-0000-00000000000d';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
insert into ids values ('quinn', (select id from counters where counter_champion = 'Quinn'));
select id as quinn from counters where counter_champion = 'Quinn' \gset

\set runes '{"primaryPath":8000,"keystone":8010,"primary":[9111,9104,8299],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5005,5008,5011]}'

-- 화면이 보내는 것과 같은 모양으로 빌드를 넣는 도우미 (바꿀 칸만 넘김)
create function pg_temp.add(
  runes jsonb default :'runes',
  spells text[] default array['SummonerFlash','SummonerTeleport'],
  starting text[] default array['1055','2003'],
  core text[] default array['6631','3047','3053'],
  skill text default 'Q',
  patch text default '16.21.1',
  counter bigint default null
) returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  values (coalesce(counter, (select v from ids where k = 'quinn')), auth.uid(), runes, spells, starting, core, skill, patch);
$$;
grant execute on function pg_temp.add to authenticated, anon;

-- ===== 1. 검사용 데이터(fixtures.sql): 작성자 없는 공개 빌드 2개 =====
select t.ok('009: 예시 빌드 칸은 없음', not exists (select 1 from information_schema.columns where table_name = 'builds' and column_name = 'is_example'));
select t.ok('작성자 없는 빌드 2개 (= 탈퇴한 유저)',
  (select count(*) = 2 and bool_and(author_id is null)
   from builds where counter_id = :quinn));

-- ===== 2. 등록 권한 =====
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인 등록 불가', 'select pg_temp.add()', 'permission denied');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select t.fails('닉네임 없으면 등록 불가', 'select pg_temp.add()', 'row-level security');

-- ===== 3. 내용 검사 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('룬: 빈 값', $$select pg_temp.add(runes => '{}')$$, '특성(룬)을 모두');
select t.fails('룬: 주 경로 2개', $$select pg_temp.add(runes => '{"primaryPath":8000,"keystone":8010,"primary":[9111,9104],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5005,5008,5011]}')$$, '주 경로 룬은 3개');
select t.fails('룬: 보조 1개', $$select pg_temp.add(runes => '{"primaryPath":8000,"keystone":8010,"primary":[9111,9104,8299],"secondaryPath":8400,"secondary":[8444],"shards":[5005,5008,5011]}')$$, '보조 룬은 2개');
select t.fails('룬: 같은 경로', $$select pg_temp.add(runes => '{"primaryPath":8000,"keystone":8010,"primary":[9111,9104,8299],"secondaryPath":8000,"secondary":[8444,8242],"shards":[5005,5008,5011]}')$$, '주 경로와 달라야');
select t.fails('룬: 같은 룬 두 번', $$select pg_temp.add(runes => '{"primaryPath":8000,"keystone":8010,"primary":[9111,9111,8299],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5005,5008,5011]}')$$, '같은 룬을 두 번');
select t.fails('룬: 경로가 소수', $$select pg_temp.add(runes => '{"primaryPath":8000.5,"keystone":8010,"primary":[9111,9104,8299],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5005,5008,5011]}')$$, '형식이 잘못');
select t.fails('룬: 숫자가 아님', $$select pg_temp.add(runes => '{"primaryPath":8000,"keystone":8010,"primary":["a",9104,8299],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5005,5008,5011]}')$$, '형식이 잘못');
select t.fails('파편: 줄에 없는 값', $$select pg_temp.add(runes => '{"primaryPath":8000,"keystone":8010,"primary":[9111,9104,8299],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5011,5008,5011]}')$$, '능력치 파편을 줄마다');
select t.fails('주문: 1개', $$select pg_temp.add(spells => array['SummonerFlash'])$$, '소환사 주문을 2개');
select t.fails('주문: 같은 것 두 번', $$select pg_temp.add(spells => array['SummonerFlash','SummonerFlash'])$$, '같은 소환사 주문');
select t.fails('주문: 이상한 이름', $$select pg_temp.add(spells => array['SummonerFlash','<script>'])$$, '소환사 주문을 2개');
select t.fails('시작 아이템: 0개', $$select pg_temp.add(starting => '{}')$$, '시작 아이템은 1~4개');
select t.fails('시작 아이템: 5개', $$select pg_temp.add(starting => array['1055','2003','2003','2003','2003'])$$, '1~4개');
select t.fails('핵심 템트리: 2개', $$select pg_temp.add(core => array['6631','3047'])$$, '핵심 템트리는 3~6개');
select t.fails('핵심 템트리: 7개', $$select pg_temp.add(core => array['1','2','3','4','5','6','7'])$$, '3~6개');
select t.fails('핵심 템트리: 중복', $$select pg_temp.add(core => array['6631','3047','6631'])$$, '같은 아이템이 두 번');
select t.fails('아이템: 숫자가 아님', $$select pg_temp.add(core => array['6631','3047','abc'])$$, '형식이 잘못');
select t.fails('선마: R', $$select pg_temp.add(skill => 'R')$$, '선마(첫 번째로 마스터할 스킬)');
select t.fails('선마: 두 개', $$select pg_temp.add(skill => 'QE')$$, '선마(첫 번째로 마스터할 스킬)');
select t.fails('선마: 없음', $$select pg_temp.add(skill => null)$$, '선마(첫 번째로 마스터할 스킬)');
select t.ok('018: 예전 스킬 칸은 없음',
  not exists (select 1 from information_schema.columns where table_name = 'builds' and column_name in ('skill_order', 'early_skills')));
select t.fails('018: 시작템 합계 500골드 초과 (도란 검 + 도란 방패 = 900)', $$select pg_temp.add(starting => array['1055','1054'])$$, '합계 500골드까지 고를 수 있습니다. (지금 900골드)');
select t.fails('018: 시작템 합계 초과 (물약 여러 개도 개수만큼)', $$select pg_temp.add(starting => array['1055','2003','2003'])$$, '(지금 550골드)');
select t.fails('018: 가격표에 없는 아이템', $$select pg_temp.add(starting => array['999999'])$$, '가격을 모르는 시작 아이템');
select t.fails('패치: 형식', $$select pg_temp.add(patch => 'latest')$$, '패치 버전 형식');
select t.fails('없는 카운터', 'select pg_temp.add(counter => 999999)', '매치업을 찾지 못했습니다');
select t.fails('상태·승인 칸은 직접 못 넣음',
  format($$insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status)
           values (%s, auth.uid(), %L, array['SummonerFlash','SummonerTeleport'], array['1055'], array['1','2','3'], 'Q', '16.21', 'approved')$$,
         :quinn, :'runes'), 'permission denied');

-- 시작 아이템은 같은 것 여러 개 가능(포션 2개 등), 패치는 앞 두 자리만 써도 됨
select pg_temp.add(starting => array['1036','2003','2003'], patch => '16.21');
select t.ok('등록: 대기 상태, 룬은 숫자로 정리',
  (select count(*) = 1 from builds where author_id = auth.uid() and status = 'pending'
     and runes -> 'primary' = '[9111,9104,8299]'::jsonb and starting_items = array['1036','2003','2003']));
insert into ids select 'b1', id from builds where author_id = auth.uid();
select t.fails('같은 매치업에 대기 빌드 2개 불가', $$select pg_temp.add(core => array['3071','3047','3053'])$$, '이미 승인 대기 중인');
select t.fails('작성자도 직접 수정 불가', 'update builds set patch = ''1.1''', 'permission denied');
select t.fails('작성자도 직접 삭제 불가', 'delete from builds', 'permission denied');

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.ok('남의 대기 빌드는 안 보임', (select count(*) = 0 from builds where id = (select v from ids where k = 'b1')));
select t.fails('일반 유저는 승인 불가', format($$select approve_build(%s, '좋습니다', null, t.bv(%1$s))$$, (select v from ids where k = 'b1')), '운영자만');
select t.fails('일반 유저는 거절 불가', format($$select reject_build(%s, '별로', t.bv(%1$s))$$, (select v from ids where k = 'b1')), '운영자만');
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인은 승인 함수 못 부름', format($$select approve_build(%s, 'x', null, t.bv(%1$s))$$, (select v from ids where k = 'b1')), 'permission denied');
select t.ok('비로그인: 공개 빌드(작성자 없는 2개)만 보임', (select count(*) = 2 from builds));

-- ===== 4. 승인 (메모 필수, 기록, 알림) =====
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('운영자도 직접 수정 불가', 'update builds set status = ''approved''', 'permission denied');
select t.fails('운영자도 직접 삭제 불가', 'delete from builds', 'permission denied');
select t.fails('승인: 메모 공백', format($$select approve_build(%s, '  ', null, t.bv(%1$s))$$, (select v from ids where k = 'b1')), '승인 메모를 적어');
select t.fails('승인: 메모 null', format('select approve_build(%s, null, null, t.bv(%1$s))', (select v from ids where k = 'b1')), '승인 메모를 적어');
select t.fails('승인: 없는 빌드', $$select approve_build(999999, '좋습니다', null, t.bv(999999))$$, '빌드를 찾지 못했습니다');
select t.fails('대기가 아닌 빌드는 숨기기만 (대기 빌드 숨기기 불가)', format($$select hide_build(%s, '이상함')$$, (select v from ids where k = 'b1')), '공개 중인 빌드만');
select approve_build((select v from ids where k = 'b1'), '  깔끔한 빌드입니다 ', null, t.bv((select v from ids where k = 'b1')));
select t.ok('승인: 공개 + 메모(공백 정리) + 처리자',
  (select status = 'approved' and approve_note = '깔끔한 빌드입니다' and reviewed_by = auth.uid() and reviewed_at is not null
   from builds where id = (select v from ids where k = 'b1')));
select t.ok('승인 기록', (select count(*) = 1 from build_status_log where build_id = (select v from ids where k = 'b1') and action = 'approve' and reason = '깔끔한 빌드입니다' and actor = auth.uid()));
select t.fails('두 번 승인 불가', format($$select approve_build(%s, '또', null, t.bv(%1$s))$$, (select v from ids where k = 'b1')), '이미 처리된');
select t.fails('승인한 빌드 거절 불가', format($$select reject_build(%s, '취소', t.bv(%1$s))$$, (select v from ids where k = 'b1')), '이미 처리된');
select t.ok('운영자는 남의 알림을 못 봄', (select count(*) = 0 from notifications));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('작성자: 승인 알림 1개 (빌드 연결, 메모)',
  (select count(*) = 1 from notifications where kind = 'build_approved' and read_at is null
     and build_id = (select v from ids where k = 'b1') and message = '깔끔한 빌드입니다' and proposal_id is null));
select t.ok('알림 확인 → 꺼짐', (select mark_notifications_read(array(select id from notifications where kind = 'build_approved')) = 1));
select t.fails('똑같은 빌드는 다시 못 냄 (패치만 달라도)', $$select pg_temp.add(starting => array['1036','2003','2003'], patch => '16.22')$$, '똑같은 빌드가 이미 공개');
select t.ok('작성자는 처리 기록을 못 봄 (운영자만)', (select count(*) = 0 from build_status_log));

-- ===== 5. 추천/비추천 =====
select t.fails('내 빌드에는 투표 불가', format('select vote_build(%s, 1::smallint)', (select v from ids where k = 'b1')), '내 빌드에는');
select t.fails('표 직접 넣기 불가', format('insert into build_votes (build_id, user_id, value) values (%s, auth.uid(), 1)', (select v from ids where k = 'b1')), 'permission denied');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select t.fails('닉네임 없으면 투표 불가', format('select vote_build(%s, 1::smallint)', (select v from ids where k = 'b1')), '닉네임을 정한 뒤에');
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인 투표 불가', format('select vote_build(%s, 1::smallint)', (select v from ids where k = 'b1')), 'permission denied');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.fails('투표 값: 2', format('select vote_build(%s, 2::smallint)', (select v from ids where k = 'b1')), '투표 값이 잘못');
select t.fails('없는 빌드', 'select vote_build(999999, 1::smallint)', '공개된 빌드에만');
select t.ok('추천 → {up 1, down 0, mine 1}', (select vote_build((select v from ids where k = 'b1'), 1::smallint) = '{"up":1,"down":0,"mine":1}'::jsonb));
select t.ok('같은 표 다시 → 그대로', (select vote_build((select v from ids where k = 'b1'), 1::smallint) = '{"up":1,"down":0,"mine":1}'::jsonb));
select t.ok('비추천으로 바꾸기', (select vote_build((select v from ids where k = 'b1'), (-1)::smallint) = '{"up":0,"down":1,"mine":-1}'::jsonb));
select t.ok('내 표는 읽을 수 있음', (select value = -1 from build_votes where build_id = (select v from ids where k = 'b1')));
select t.ok('취소', (select vote_build((select v from ids where k = 'b1'), null) = '{"up":0,"down":0,"mine":null}'::jsonb));
select t.ok('취소한 표는 없어짐', (select count(*) = 0 from build_votes));
select t.ok('같은 취소 다시 → 그대로', (select vote_build((select v from ids where k = 'b1'), null) = '{"up":0,"down":0,"mine":null}'::jsonb));
select vote_build((select v from ids where k = 'b1'), 1::smallint);
select t.ok('일반 유저는 투표 기록을 못 봄 (운영자만)', (select count(*) = 0 from build_vote_log));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.ok('운영자도 투표 가능 (남의 빌드)', (select vote_build((select v from ids where k = 'b1'), 1::smallint) = '{"up":2,"down":0,"mine":1}'::jsonb));
select t.ok('작성자 없는 빌드(탈퇴한 유저)에도 투표 가능',
  (select (vote_build((select min(id) from builds where author_id is null), (-1)::smallint) ->> 'down')::int = 1));
select t.ok('투표 기록: 바뀐 것만 (유저2: 없음→1→-1→없음→1 = 4줄, 운영자 2줄)',
  (select count(*) = 6 from build_vote_log));
select t.ok('투표 기록 내용 (받은 사람·카운터·이전값·새값)',
  (select array_agg(array[coalesce(old_value, 0), coalesce(new_value, 0)] order by id) = array[[0,1],[1,-1],[-1,0],[0,1]]
      and bool_and(author_id = '00000000-0000-0000-0000-00000000000b' and counter_id = :quinn)
   from build_vote_log where voter_id = '00000000-0000-0000-0000-00000000000d'));

-- ===== 6. 숨기기 / 다시 공개 =====
select t.fails('숨기기: 사유 공백', format($$select hide_build(%s, ' ')$$, (select v from ids where k = 'b1')), '숨기는 사유를 적어');
select t.fails('다시 공개: 숨긴 빌드가 아님', format($$select restore_build(%s, '다시')$$, (select v from ids where k = 'b1')), '숨긴 빌드가 아닙니다');
select hide_build((select v from ids where k = 'b1'), '아이템이 바뀌었습니다');
select t.ok('숨김: 상태·사유·시각, 추천 수는 그대로',
  (select status = 'hidden' and hide_reason = '아이템이 바뀌었습니다' and hidden_at is not null and up_count = 2
   from builds where id = (select v from ids where k = 'b1')));
select t.fails('두 번 숨기기 불가', format($$select hide_build(%s, '또')$$, (select v from ids where k = 'b1')), '이미 숨긴');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.ok('다른 유저에게 숨긴 빌드는 안 보임', (select count(*) = 0 from builds where id = (select v from ids where k = 'b1')));
select t.fails('숨긴 빌드에는 투표 불가', format('select vote_build(%s, (-1)::smallint)', (select v from ids where k = 'b1')), '공개된 빌드에만');
select t.fails('일반 유저는 숨기기 불가', format($$select hide_build(%s, 'x')$$, (select min(id) from builds where author_id is null)), '운영자만');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('작성자에겐 숨긴 빌드와 사유가 보임 + 숨김 알림',
  (select status = 'hidden' and hide_reason = '아이템이 바뀌었습니다' from builds where id = (select v from ids where k = 'b1'))
  and (select count(*) = 1 from notifications where kind = 'build_hidden' and read_at is null and message = '아이템이 바뀌었습니다'));
select pg_temp.add(starting => array['1036','2003','2003']);
insert into ids select 'b2', max(id) from builds where author_id = auth.uid();
select t.ok('숨긴 동안에는 같은 빌드를 다시 낼 수 있음 (승인 때 다시 비교)', (select status = 'pending' from builds where id = (select v from ids where k = 'b2')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('다시 공개: 메모 공백', format($$select restore_build(%s, '')$$, (select v from ids where k = 'b1')), '다시 공개 메모를 적어');
select restore_build((select v from ids where k = 'b1'), '패치 확인했습니다');
select t.ok('다시 공개: 공개 + 숨김 사유 지움 + 추천 유지',
  (select status = 'approved' and hide_reason is null and hidden_at is null and up_count = 2
   from builds where id = (select v from ids where k = 'b1')));
select t.fails('똑같은 빌드가 공개 중이면 승인 불가', format($$select approve_build(%s, '좋습니다', null, t.bv(%1$s))$$, (select v from ids where k = 'b2')), '똑같은 빌드가 이미 공개');

-- ===== 7. 거절 =====
select t.fails('거절: 사유 공백', format($$select reject_build(%s, '', t.bv(%1$s))$$, (select v from ids where k = 'b2')), '거절 사유를 적어');
select reject_build((select v from ids where k = 'b2'), '이미 있는 빌드', t.bv((select v from ids where k = 'b2')));
select t.ok('거절: 상태·사유', (select status = 'rejected' and reject_reason = '이미 있는 빌드' from builds where id = (select v from ids where k = 'b2')));
select t.fails('거절된 빌드에 투표 불가', format('select vote_build(%s, 1::smallint)', (select v from ids where k = 'b2')), '공개된 빌드에만');
select t.ok('처리 기록 4종 (승인·숨김·다시 공개·거절)',
  (select array_agg(action order by id) = array['approve','hide','restore','reject'] from build_status_log));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('작성자 알림: 승인·숨김·다시 공개·거절 (확인 안 한 3개)',
  (select count(*) = 3 from notifications where read_at is null and kind in ('build_hidden', 'build_restored', 'build_rejected')));
select t.ok('작성자는 내 빌드 전부 봄 (공개 1 + 거절 1)', (select count(*) = 2 from builds where author_id = auth.uid()));

-- ===== 8. 숨긴 카운터의 빌드 =====
select pg_temp.add(core => array['3071','3047','3053']);
insert into ids select 'b3', max(id) from builds where author_id = auth.uid();
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select hide_counter(:quinn, '정리');
select t.fails('숨긴 카운터의 빌드는 승인 불가', format($$select approve_build(%s, '좋습니다', null, t.bv(%1$s))$$, (select v from ids where k = 'b3')), '숨긴 카운터의 빌드');
select t.fails('숨긴 카운터의 공개 빌드에는 투표 불가', format('select vote_build(%s, (-1)::smallint)', (select v from ids where k = 'b1')), '공개된 빌드에만');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.fails('숨긴 카운터에는 빌드 등록 불가', 'select pg_temp.add()', '매치업을 찾지 못했습니다');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select reject_build((select v from ids where k = 'b3'), '카운터 숨김', t.bv((select v from ids where k = 'b3')));
select restore_counter(:quinn, '다시 공개');

-- ===== 9. 제안 승인·거절 알림 (카운터 제안) =====
\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build()), ('new_counter', 'Darius', 'Teemo', auth.uid(), :'doc', t.build());
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select id from edit_proposals where counter_champion = 'Garen'), '반영했습니다', null, null, t.pv((select id from edit_proposals where counter_champion = 'Garen')));
select reject_proposal((select id from edit_proposals where counter_champion = 'Teemo'), '근거가 부족합니다', t.pv((select id from edit_proposals where counter_champion = 'Teemo')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.ok('제안 승인 알림 (메모)', (select count(*) = 1 from notifications where kind = 'proposal_approved' and message = '반영했습니다' and build_id is null));
select t.ok('제안 거절 알림 (사유)', (select count(*) = 1 from notifications where kind = 'proposal_rejected' and message = '근거가 부족합니다'));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into edit_proposals (type, counter_id, proposer_id, content)
values ('doc_edit', :quinn, auth.uid(), :'doc');
select approve_proposal((select id from edit_proposals where proposer_id = auth.uid()), '내 수정', null, null, t.pv((select id from edit_proposals where proposer_id = auth.uid())));
reset role;
select t.ok('운영자가 자기 제안을 승인하면 알림 없음', (select count(*) = 0 from notifications where user_id = '00000000-0000-0000-0000-00000000000a'));
select t.ok('알림 종류 검사', (select count(*) = 0 from notifications where kind not in
  ('revision_request','proposal_approved','proposal_rejected','build_approved','build_rejected','build_hidden','build_restored',
   'level_up','level_down','title_earned','title_revoked')));

-- ===== 10. 탈퇴(계정 삭제) =====
-- 유저(b): 공개 빌드 b1(추천 2), 거절 b2·b3 / 유저2(d): b1에 추천
delete from auth.users where id = '00000000-0000-0000-0000-00000000000d';
select t.ok('투표한 사람 탈퇴: 표는 지워지고 수 반영, 투표 기록은 이름만 비움',
  (select up_count = 1 from builds where id = (select v from ids where k = 'b1'))
  and (select count(*) = 4 from build_vote_log where build_id = (select v from ids where k = 'b1') and voter_id is null));
delete from auth.users where id = '00000000-0000-0000-0000-00000000000b';
select t.ok('작성자 탈퇴: 거절·대기 빌드는 지워짐', (select count(*) = 0 from builds where id in (select v from ids where k in ('b2', 'b3'))));
select t.ok('작성자 탈퇴: 공개 빌드는 작성자만 비우고 남음',
  (select author_id is null and status = 'approved' from builds where id = (select v from ids where k = 'b1')));
select t.ok('작성자 탈퇴: 투표 기록의 받은 사람도 비움 (기록은 남음)', (select count(*) = 5 and bool_and(author_id is null) from build_vote_log where build_id = (select v from ids where k = 'b1')));
select t.ok('처리 기록: 남은 빌드 것만 남음 (지워진 거절 빌드 기록은 함께 지워짐)', (select count(*) = 3 from build_status_log where build_id = (select v from ids where k = 'b1')) and (select count(*) = 3 from build_status_log l join builds b on b.id = l.build_id where b.counter_id = :quinn));

-- ===== 11. 카운터 완전 삭제: 빌드는 함께 지워지고 투표 기록은 남음 =====
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select hide_counter(:quinn, '정리');
select delete_counter(:quinn, 'Quinn', '테스트');
reset role;
select t.ok('삭제: 빌드·처리 기록은 함께 지워짐', (select count(*) = 0 from builds where counter_id = :quinn) and (select count(*) = 0 from build_status_log where build_id = (select v from ids where k = 'b1')));
select t.ok('삭제: 투표 기록은 남음 (6단계 계산용)', (select count(*) = 6 from build_vote_log where counter_id = :quinn));
