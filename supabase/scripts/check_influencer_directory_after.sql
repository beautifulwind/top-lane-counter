-- =====================================================================
-- 070(공개 장인 목록 influencer_directory) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다). 운영 DB에서 언제 다시 실행해도 된다.
-- 070을 실행한 "직후" SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~15번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요. (웹 1-B1은 그다음)
--   - 16~19번: 실행 전 check_influencer_directory_before.sql의 3~7번에 적어 둔 값과 같아야 한다 (070은 함수 하나만 더한다).
--   - 100번부터: 장인 한 명씩 influencer_directory 결과(팔로워 많은 순). 팔로워·빌드 수는 실행 전 표의 100번부터와 같아야 한다.
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
--   - 이 조회는 influencer_directory를 부르기만 한다(읽기 함수 - 데이터를 바꾸지 않음).
-- =====================================================================
with
-- 전체 장인 (팔로워 많은 순 / 최신순) - 장인이 50명을 넘으면 앞 50명만 본다(크기 상한)
f as (select public.influencer_directory(null, 'followers', 1, 50) as j),
r as (select public.influencer_directory(null, 'recent', 1, 50) as j),
fi as (select e, o from f, jsonb_array_elements(f.j -> 'items') with ordinality as x(e, o)),
ri as (select e, o from r, jsonb_array_elements(r.j -> 'items') with ordinality as x(e, o)),
-- 정렬 열쇠 (작을수록 앞): 팔로워 많은 순 = (-팔로워, 활동 없음, -활동 시각, 닉네임, id) / 최신순 = (활동 없음, -활동 시각, -팔로워, 닉네임, id)
fk as (select o, (e ->> 'follower_count')::int as fc, (e ->> 'last_activity_at')::timestamptz as la, e ->> 'nickname' as nick, (e ->> 'id')::uuid as id from fi),
rk as (select o, (e ->> 'follower_count')::int as fc, (e ->> 'last_activity_at')::timestamptz as la, e ->> 'nickname' as nick, (e ->> 'id')::uuid as id from ri),
-- 실제 공개 빌드 기준 (숨긴·대기·거절 빌드, 숨긴 상대법의 빌드는 빠진다)
pub as (
  select x.author_id, count(*) as n, max(x.updated_at) as last_at
    from public.builds x join public.counters c on c.id = x.counter_id
   where x.status = 'approved' and c.status = 'approved' and x.author_id is not null
   group by x.author_id
),
-- 공개가 아닌 빌드 (숨김·대기 등 또는 숨긴 상대법)
hid as (
  select x.author_id, count(*) as n, max(x.updated_at) as last_at
    from public.builds x join public.counters c on c.id = x.counter_id
   where not (x.status = 'approved' and c.status = 'approved') and x.author_id is not null
   group by x.author_id
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '새 함수 influencer_directory (인자 / 같은 이름 함수 수)' as what,
    coalesce(to_regprocedure('public.influencer_directory(text, text, integer, integer)')::text, '없음')
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'influencer_directory') as now_value,
    'influencer_directory(text,text,integer,integer) / 1' as ok_value, null as memo
  union all select 2, '읽기 함수·보안 (volatile 종류 / security definer / search_path / 반환형)',
    (select provolatile::text || ' / ' || prosecdef::text || ' / ' || coalesce(array_to_string(proconfig, ','), '없음') || ' / ' || prorettype::regtype::text
       from pg_proc where oid = to_regprocedure('public.influencer_directory(text, text, integer, integer)')),
    's / true / search_path="" / jsonb', 's = stable(읽기 함수)'
  union all select 3, '실행 권한 (비로그인 anon / 로그인 authenticated / public 기본 권한)',
    (select has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text
            || ' / ' || exists (select 1 from unnest(proacl) a where a::text like '=%')::text
       from pg_proc where oid = to_regprocedure('public.influencer_directory(text, text, integer, integer)')),
    'true / true / false', 'public은 회수, 두 역할에만 부여'
  union all select 4, '함수 본문 지문 (줄바꿈 CR을 뺀 값)',
    (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.influencer_directory(text, text, integer, integer)')),
    '7955c630a2b304baf7628375ca3f3940', '파일 그대로 실행했으면 같음 (CRLF로 붙여 넣어도 같음)'
  union all select 5, '068 빠뜨림 방지 검사 대상인가 (volatile 쓰기 함수 목록에 있음 / 허용 목록에 있음)',
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'influencer_directory' and p.provolatile = 'v')::text
      || ' / ' || case when to_regclass('public.restriction_exemptions') is null then '표 없음' else
           (xpath('/row/c/text()', query_to_xml('select (count(*) > 0)::text as c from public.restriction_exemptions where name like ''influencer_directory%''', false, true, '')))[1]::text end,
    'false / false', '읽기 함수라 검사 대상이 아니고 허용 목록에도 넣지 않는다'
  union all select 6, '장인 수 (함수 total / 실제 장인(닉네임 있음) 수)',
    (select (j ->> 'total') from f) || ' / ' || (select count(*) from public.profiles where influencer is not null and nickname is not null),
    '두 값이 같음', '실행 전 3번의 둘째 값과도 같아야 함'
  union all select 7, '돌려주는 칸 (맨 위 / 장인 한 명)',
    (select string_agg(k, ',' order by k) from f, jsonb_object_keys(f.j) k)
      || ' / ' || coalesce((select string_agg(k, ',' order by k) from (select e from fi order by o limit 1) z, jsonb_object_keys(z.e) k), '(장인 없음)'),
    'items,page,size,sort,total / build_count,follower_count,id,influencer,last_activity_at,nickname,photo_path', '이메일·역할 등 다른 칸 없음'
  union all select 8, '장인별 팔로워 수·빌드 수가 search_influencers와 다른 사람 (닉네임 목록)',
    coalesce((select string_agg(fi.e ->> 'nickname', ', ' order by fi.o) from fi
       where not exists (select 1 from jsonb_array_elements(public.search_influencers(left(fi.e ->> 'nickname', 20)) -> 'items') s
                          where s ->> 'id' = fi.e ->> 'id' and s ->> 'follower_count' = fi.e ->> 'follower_count' and s ->> 'build_count' = fi.e ->> 'build_count')), '없음'),
    '없음', null
  union all select 9, '빌드 수·최근 활동이 "공개 빌드" 기준과 다른 사람 (닉네임 목록)',
    coalesce((select string_agg(fi.e ->> 'nickname', ', ' order by fi.o) from fi left join pub on pub.author_id = (fi.e ->> 'id')::uuid
       where (fi.e ->> 'build_count')::int <> coalesce(pub.n, 0)
          or (fi.e ->> 'last_activity_at')::timestamptz is distinct from pub.last_at), '없음'),
    '없음', '최근 활동 = 공개 빌드의 가장 최근 updated_at, 공개 빌드가 없으면 null'
  union all select 10, '숨긴·대기 빌드가 있는 장인 수 / 그중 숨긴 빌드가 드러난 사람 (개수에 포함됐거나, 숨긴 빌드 시각이 최근 활동으로 나온 사람)',
    (select count(*) from fi join hid on hid.author_id = (fi.e ->> 'id')::uuid)
      || ' / ' || coalesce((select string_agg(fi.e ->> 'nickname', ', ') from fi join hid on hid.author_id = (fi.e ->> 'id')::uuid
                    left join pub on pub.author_id = hid.author_id
                   where (fi.e ->> 'build_count')::int > coalesce(pub.n, 0)
                      or ((fi.e ->> 'last_activity_at')::timestamptz = hid.last_at and hid.last_at is distinct from pub.last_at)), '없음'),
    '(숫자) / 없음', '앞 숫자는 0이어도 정상(숨긴 빌드가 있는 장인이 없으면 이 검사는 해당 없음)'
  union all select 11, '정렬 "팔로워 많은 순": 순서가 어긋난 곳 수 / 순서 (닉네임)',
    (select count(*) from fk a join fk b on b.o = a.o + 1
      where (-a.fc, (a.la is null)::int, -coalesce(extract(epoch from a.la), 0), a.nick, a.id)
          > (-b.fc, (b.la is null)::int, -coalesce(extract(epoch from b.la), 0), b.nick, b.id))
      || ' / ' || coalesce((select string_agg(nick, ', ' order by o) from fk), '(장인 없음)'),
    '0 / (순서 확인)', '팔로워 내림 → 최근 활동 내림(없음은 뒤) → 닉네임 → id'
  union all select 12, '정렬 "최신순": 순서가 어긋난 곳 수 / 순서 (닉네임)',
    (select count(*) from rk a join rk b on b.o = a.o + 1
      where ((a.la is null)::int, -coalesce(extract(epoch from a.la), 0), -a.fc, a.nick, a.id)
          > ((b.la is null)::int, -coalesce(extract(epoch from b.la), 0), -b.fc, b.nick, b.id))
      || ' / ' || coalesce((select string_agg(nick, ', ' order by o) from rk), '(장인 없음)'),
    '0 / (순서 확인)', '최근 활동 내림(없음은 뒤) → 팔로워 내림 → 닉네임 → id'
  union all select 13, '쪽 나누기 (크기 5): 1쪽·2쪽 겹친 사람 수 / 1쪽+2쪽 = 크기 10의 1쪽 (두 정렬)',
    (select count(*) from jsonb_array_elements(public.influencer_directory(null, 'followers', 1, 5) -> 'items') a
       join jsonb_array_elements(public.influencer_directory(null, 'followers', 2, 5) -> 'items') b on a ->> 'id' = b ->> 'id')
      || ' / ' || (
        (public.influencer_directory(null, 'followers', 1, 5) -> 'items') || (public.influencer_directory(null, 'followers', 2, 5) -> 'items')
          = public.influencer_directory(null, 'followers', 1, 10) -> 'items'
        and (public.influencer_directory(null, 'recent', 1, 5) -> 'items') || (public.influencer_directory(null, 'recent', 2, 5) -> 'items')
          = public.influencer_directory(null, 'recent', 1, 10) -> 'items')::text,
    '0 / true', '장인이 5명 이하면 2쪽은 비어 있고 그래도 true'
  union all select 14, '크기 보정 (기본 / 999 / 0 / 쪽 0) → size·page',
    (public.influencer_directory() ->> 'size') || ' / ' || (public.influencer_directory(null, null, 1, 999) ->> 'size')
      || ' / ' || (public.influencer_directory(null, null, 1, 0) ->> 'size') || ' / page ' || (public.influencer_directory(null, null, 0, 10) ->> 'page'),
    '10 / 50 / 1 / page 1', '크기는 1~50, 쪽은 1부터'
  union all select 15, '정렬·검색 보정 (모르는 정렬 → / %·_ 검색 total / 공백 검색 total = 전체)',
    (public.influencer_directory(null, 'xyz') ->> 'sort') || ' / ' || (public.influencer_directory('%') ->> 'total') || '·' || (public.influencer_directory('_') ->> 'total')
      || ' / ' || ((public.influencer_directory('   ') ->> 'total') = (select j ->> 'total' from f))::text,
    'followers / 0·0 / true', '%·_는 글자 그대로 (닉네임에 %·_가 들어간 장인이 있으면 0이 아닐 수 있음)'
  union all select 16, '적어 둘 값 비교: 장인 수 (장인 전체 / 그중 닉네임 있음 / 장인인데 닉네임 없음)',
    (select count(*) || ' / ' || count(*) filter (where nickname is not null) || ' / ' || count(*) filter (where nickname is null)
       from public.profiles where influencer is not null),
    '실행 전 3번과 같음', null
  union all select 17, '적어 둘 값 비교: 일반 사용자가 부를 수 있는 쓰기 함수 수 (volatile, 트리거 아님)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
        and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))::text,
    '실행 전 4번과 같음', '070은 쓰기 함수를 더하지 않는다'
  union all select 18, '적어 둘 값 비교: 기존 장인 관련 공개 함수 4개 지문 / 실행 권한',
    (select count(*) || ' / ' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), ''), '|' order by p.proname, oidvectortypes(p.proargtypes)))
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('search_influencers', 'influencer_builds', 'influencer_follower_count', 'nickname_key'))
      || ' ;; ' || (select string_agg(p.proname || ':' || has_function_privilege('anon', p.oid, 'execute')::text || '·' || has_function_privilege('authenticated', p.oid, 'execute')::text, ', ' order by p.proname)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('search_influencers', 'influencer_builds', 'influencer_follower_count', 'nickname_key')),
    '실행 전 5번 ;; 6번과 같음', '옛 앱이 쓰는 함수 그대로'
  union all select 19, '적어 둘 값 비교: 프로필 / 빌드 / 팔로우 (각 줄 수 · 내용 지문 앞 12자리)',
    (select count(*) || '·' || left(md5(coalesce(string_agg((to_jsonb(p) - 'last_seen_at')::text, '|' order by p.id), '')), 12) from public.profiles p)
      || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(b::text, '|' order by b.id), '')), 12) from public.builds b)
      || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(f::text, '|' order by f.follower_id::text, f.influencer_id::text), '')), 12) from public.influencer_follows f),
    '실행 전 7번과 같음', '070은 데이터를 바꾸지 않는다'
  -- 100번부터: 장인 한 명씩 (influencer_directory 팔로워 많은 순 그대로)
  union all
  select 100 + fi.o::int, '장인: ' || (fi.e ->> 'nickname') || ' (' || (fi.e ->> 'influencer') || ')',
    '팔로워 ' || (fi.e ->> 'follower_count') || ' · 빌드 ' || (fi.e ->> 'build_count')
      || ' · 최근 활동 ' || coalesce(to_char((fi.e ->> 'last_activity_at')::timestamptz at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI'), '없음')
      || case when fi.e ->> 'photo_path' is not null then ' · 사진 있음' else '' end,
    '팔로워·빌드는 실행 전 표와 같음', null
    from fi
) x
order by ord;
