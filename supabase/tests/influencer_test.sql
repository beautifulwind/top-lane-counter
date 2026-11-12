-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 046: 장인 인증 (신청·심사·만료·되돌리기·임시 닉네임·사칭 금지·비슷한 닉네임·개인정보 지우기·알림·권한·신규 가입자)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set X   '00000000-0000-0000-0000-000000000011'
\set R   '00000000-0000-0000-0000-000000000012'
\set S   '00000000-0000-0000-0000-000000000013'
\set T   '00000000-0000-0000-0000-000000000014'
\set GU  '00000000-0000-0000-0000-000000000010'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'),
  (:'W', 'w@x.com'), (:'X', 'x@x.com'), (:'R', 'r@x.com'), (:'S', 's@x.com'), (:'T', 't@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
insert into auth.identities (user_id, provider, provider_id) values
  (:'U', 'google', 'SECRET-GOOGLE-ID'), (:'V', 'kakao', 'k-1'), (:'V', 'google', 'g-2');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = 'Faker' where id = :'V';
update public.profiles set nickname = '더블유' where id = :'W';
update public.profiles set nickname = 'Chovy' where id = :'X';
update public.profiles set nickname = '알' where id = :'R';
update public.profiles set nickname = 'Zeus' where id = :'S';
update public.profiles set nickname = '티' where id = :'T';
update public.profiles set nickname = '손님' where id = :'GU';
delete from nickname_changes;
delete from notifications;
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;

-- ===== 1. 사칭 금지: [장인]·(장인)·"장인 "으로 시작 =====
set role authenticated;
set request.jwt.claim.sub = :'T';
select t.fails('닉네임 [장인]…', $$update public.profiles set nickname = '[장인]티' where id = auth.uid()$$, '[장인]·(장인)을 쓸 수 없고');
select t.fails('닉네임 (장인)…', $$update public.profiles set nickname = '티(장인)' where id = auth.uid()$$, '[장인]·(장인)을 쓸 수 없고');
select t.fails('괄호 모양·띄어쓰기 변형 【 장 인 】', $$update public.profiles set nickname = '【 장 인 】티' where id = auth.uid()$$, '[장인]·(장인)을 쓸 수 없고');
select t.fails('"장인 "으로 시작', $$update public.profiles set nickname = '장인 티' where id = auth.uid()$$, '"장인 "으로 시작할 수 없습니다');
select t.fails('"장인_"으로 시작 (구분 기호)', $$update public.profiles set nickname = '장인_티' where id = auth.uid()$$, '"장인 "으로 시작할 수 없습니다');
select t.fails('보이지 않는 글자를 끼운 "장인​ 티"', format('update public.profiles set nickname = %L where id = auth.uid()', E'장인​ 티'), '"장인 "으로 시작할 수 없습니다');
select t.fails('(운)은 그대로 막힘', $$update public.profiles set nickname = '(운)티' where id = auth.uid()$$, '(운)·(감)을 쓸 수 없습니다');
reset role;
select t.ok('"장인정신"·"티장인"은 쓸 수 있음 (판정만)',
  not public.nickname_mimics_influencer('장인정신') and not public.nickname_mimics_influencer('티장인') and not public.nickname_reserved('장인정신'));
select t.ok('칭호 이름에 "장인" 없음', not exists (
  select 1 from (values ('top_addict'), ('tool_hater'), ('solid_heavy'), ('butcher_owner'), ('general'), ('offmeta')) v(k)
   where public.title_name(k) like '%장인%'));

-- ===== 2. 비슷한 닉네임 (nickname_key) =====
select t.ok('열쇠: 대소문자·I/l/1·0/o·띄어쓰기·키릴 글자가 같다',
  public.nickname_key('Faker') = public.nickname_key('FAKER') and public.nickname_key('Faker') = public.nickname_key('Fa ker')
  and public.nickname_key('FakerI') = public.nickname_key('Faker1') and public.nickname_key('F0ker') = public.nickname_key('Foker')
  and public.nickname_key('Fаker') = public.nickname_key('Faker')  -- 두 번째 글자 키릴 а
  and public.nickname_key('Ｆａｋｅｒ') = public.nickname_key('Faker'));
select t.ok('열쇠: 다른 닉네임은 다르다', public.nickname_key('Faker') <> public.nickname_key('Faker2') and public.nickname_key('유저') <> public.nickname_key('유저2'));
set role authenticated;
set request.jwt.claim.sub = :'T';
select t.fails('비슷한 닉네임 Fa ker 막힘 (23505)', $$update public.profiles set nickname = 'Fa ker' where id = auth.uid()$$, '이미 사용 중인 닉네임');
select t.fails('키릴 а를 섞은 Fаker 막힘', $$update public.profiles set nickname = 'Fаker' where id = auth.uid()$$, '이미 사용 중인 닉네임');
reset role;
select t.ok('보통 닉네임끼리는 인덱스도 막음 (profiles_nickname_key_unique)',
  exists (select 1 from pg_indexes where indexname = 'profiles_nickname_key_unique') and not exists (select 1 from pg_indexes where indexname = 'profiles_nickname_unique'));

-- ===== 3. 신청할 수 없는 사람 =====
set role authenticated;
set request.jwt.claim.sub = :'GU';
select t.fails('비회원은 신청 불가', $$select apply_influencer('creator', '손님', 'https://youtube.com/@guest', 'g@x.com')$$, '구글·카카오로 로그인한 회원만');
set request.jwt.claim.sub = :'OP';
select t.fails('운영자는 신청 불가', $$select apply_influencer('creator', '영자', 'https://youtube.com/@op', 'o@x.com')$$, '운영자 계정은 장인 인증을 신청할 수 없습니다');
set request.jwt.claim.sub = :'U';
select t.fails('(a) 공식 이메일 필수', $$select apply_influencer('creator', 'Faker', 'https://youtube.com/@faker', null)$$, '공식 이메일을 적어 주세요');
select t.fails('(a) 채널 링크 필수', $$select apply_influencer('pro', 'Faker', 'youtube.com', 'faker@t1.gg')$$, '채널·방송 링크를');
select t.fails('(b) 라이엇 닉네임#태그 필수', $$select apply_influencer('grandmaster', 'Faker', null, null, 'nohash', 'https://op.gg/x')$$, '라이엇 닉네임#태그를');
select t.fails('(b) op.gg 링크만', $$select apply_influencer('grandmaster', 'Faker', null, null, 'Hide on bush#KR1', 'https://evil.com/op.gg')$$, 'op.gg 링크를');
select t.fails('유형 필수', $$select apply_influencer('streamer', 'Faker', 'https://youtube.com/@f', 'f@x.com')$$, '유형을 골라 주세요');
select t.fails('희망 닉네임에도 사칭 금지', $$select apply_influencer('creator', '[장인]Faker', 'https://youtube.com/@f', 'f@x.com')$$, '[장인]·(장인)을 쓸 수 없고');
reset role;
select t.ok('실패한 신청은 남지 않음', (select count(*) from influencer_applications) = 0 and (select nickname from profiles where id = :'U') = '유저');

-- ===== 4. (a) 신청: 다른 회원(V)이 쓰는 Faker로 — 둘이 잠깐 같은 닉네임, 신청자는 "인증 대기" =====
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids values ('a_u', apply_influencer('creator', 'Faker', 'https://www.YouTube.com/@faker/', 'Faker@T1.gg'));
reset role;
select t.ok('신청자 닉네임 = 희망 닉네임, 상태 pending', (select nickname = 'Faker' and nickname_state = 'pending' and influencer is null from profiles where id = :'U'));
select t.ok('원래 쓰던 V는 그대로', (select nickname = 'Faker' and nickname_state is null from profiles where id = :'V'));
select t.ok('신청 줄: 공식 이메일(소문자)·채널 열쇠·이전 닉네임·14일 만료',
  (select official_email = 'faker@t1.gg' and channel_key = 'youtube.com/@faker' and old_nickname = '유저' and status = 'pending'
          and expires_at between now() + interval '13 days 23 hours' and now() + interval '14 days 1 hour'
     from influencer_applications where id = pg_temp.id('a_u')));
select t.ok('닉네임 변경 기록 kind apply', exists (select 1 from nickname_changes where user_id = :'U' and kind = 'apply' and new_nickname = 'Faker'));
select t.ok('신청자 알림 influencer_received ((a) 문장)', exists (select 1 from notifications where user_id = :'U' and kind = 'influencer_received'
  and message = '신청이 접수됐습니다. 적어 주신 공식 이메일로 확인 메일을 보냅니다. 14일 안에 "본인입니다"라고 회신해 주세요.'));
select t.ok('운영자 알림 influencer_applied (닉네임·유형만)', exists (select 1 from notifications where user_id = :'OP' and kind = 'influencer_applied'
  and message = '장인 인증 신청이 들어왔습니다. (Faker · 크리에이터)'));
select t.ok('감독관·다른 회원에게는 신청 알림 없음', not exists (select 1 from notifications where kind = 'influencer_applied' and user_id <> :'OP'));

set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('심사 중에는 닉네임 직접 못 바꿈', $$update public.profiles set nickname = '유저삼' where id = auth.uid()$$, '심사하는 동안에는 닉네임을 바꿀 수 없습니다');
select t.fails('처리 전 신청은 하나만', $$select apply_influencer('pro', 'Faker', 'https://twitch.tv/faker', 'f2@x.com')$$, '이미 심사 중인 신청이 있습니다');
select t.ok('본인은 자기 신청(공식 이메일 포함)을 읽음', (select official_email from influencer_applications where id = pg_temp.id('a_u')) = 'faker@t1.gg');
select t.ok('내 상태: 인증 대기 + 신청', (my_influencer_status() ->> 'nickname_state') = 'pending' and (my_influencer_status() -> 'application' ->> 'status') = 'pending');
set request.jwt.claim.sub = :'V';
select t.ok('다른 회원은 남의 신청을 못 읽음', (select count(*) from influencer_applications) = 0);
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관도 신청을 못 읽음', (select count(*) from influencer_applications) = 0);
select t.fails('감독관은 목록 함수도 불가', $$select admin_influencer_applications()$$, '운영자만 할 수 있습니다');
select t.ok('감독관 처리 대기 건수 influencers = 0', (admin_pending_counts() ->> 'influencers')::int = 0);
set request.jwt.claim.sub = :'X';
select t.fails('같은 채널(대소문자·www·끝 / 무시) 겹침', $$select apply_influencer('creator', '촙', 'http://youtube.com/@FAKER?si=1', 'x@x.com')$$, '이미 신청됐거나 인증된 채널입니다');
select t.fails('인증 대기 중인 닉네임으로는 신청 불가', $$select apply_influencer('creator', 'faker', 'https://youtube.com/@other', 'x@x.com')$$, '이미 장인 인증을 신청 중인 닉네임입니다');
set request.jwt.claim.sub = :'T';
select t.fails('인증 대기 중인 닉네임은 보통 회원도 못 가져감', $$update public.profiles set nickname = 'FAKER' where id = auth.uid()$$, '이미 사용 중인 닉네임');
set request.jwt.claim.sub = :'OP';
select t.ok('운영자 목록: 공식 이메일·겹친 회원(V)', (select (i ->> 'official_email') = 'faker@t1.gg' and (i -> 'overlap' ->> 'id')::uuid = :'V'
  from jsonb_array_elements(admin_influencer_applications() -> 'items') i where (i ->> 'id')::bigint = pg_temp.id('a_u')));
select t.ok('운영자 처리 대기 건수 influencers = 1', (admin_pending_counts() ->> 'influencers')::int = 1);
reset role;

-- ===== 5. (b) 신청: 라이엇 닉네임#태그 겹침 (대소문자·공백 정규화) =====
set role authenticated;
set request.jwt.claim.sub = :'W';
insert into ids values ('b_w', apply_influencer('grandmaster', 'chovy', null, null, 'Hide on bush #KR1', 'https://www.op.gg/summoners/kr/Hide%20on%20bush-KR1'));
reset role;
select t.ok('(b) 신청: 라이엇 ID 원문 + 해시, 채널·이메일 없음',
  (select riot_id = 'Hide on bush#KR1' and riot_key = public.influencer_riot_key('hideonbush#kr1') and channel_url is null and official_email is null
     from influencer_applications where id = pg_temp.id('b_w')));
select t.ok('(b) 신청자 알림: 운영자 계정 자리표시 {운영자 닉네임}', exists (select 1 from notifications where user_id = :'W' and kind = 'influencer_received'
  and message = '신청이 접수됐습니다. 14일 안에 운영자 계정 {운영자 닉네임}으로 친구 요청을 보내 주세요. 요청이 도착하면 이 닉네임의 주인이 맞는지 확인합니다. 수락은 하지 않습니다.'));
select t.ok('운영자 알림 (그랜드마스터 이상)', exists (select 1 from notifications where user_id = :'OP' and message = '장인 인증 신청이 들어왔습니다. (chovy · 그랜드마스터 이상)'));
select t.ok('운영자 알림에 이메일·라이엇 ID 없음', not exists (select 1 from notifications where kind = 'influencer_applied' and (message ilike '%t1.gg%' or message ilike '%hide on%')));
set role authenticated;
set request.jwt.claim.sub = :'T';
select t.fails('같은 라이엇 닉네임#태그 겹침', $$select apply_influencer('grandmaster', '티이', null, null, ' hide ON BUSH#kr1 ', 'https://op.gg/x')$$, '이미 신청됐거나 인증된 라이엇 닉네임입니다');
reset role;

-- ===== 6. 승인 권한 · 승인 (겹친 V는 "닉네임 변경 예정") =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관은 승인 불가', format('select approve_influencer(%s, %L)', pg_temp.id('a_u'), '이메일 회신 확인'), '운영자만 할 수 있습니다');
set request.jwt.claim.sub = :'OP';
select t.fails('승인 메모 필수', format('select approve_influencer(%s, %L)', pg_temp.id('a_u'), '  '), '승인 메모를 적어 주세요');
select set_operator_mode(false);
select t.fails('운영자 모드를 끄면 승인 불가', format('select approve_influencer(%s, %L)', pg_temp.id('a_u'), '이메일 회신 확인'), '운영자만 할 수 있습니다');
select t.ok('모드를 끄면 신청 알림이 목록에서 가려짐', not exists (select 1 from notifications where kind = 'influencer_applied'));
select mark_all_notifications_read(9223372036854775807);
select set_operator_mode(true);
select t.ok('모드를 끈 동안 [모두 읽음]은 신청 알림을 건드리지 않음', (select bool_and(read_at is null) from notifications where kind = 'influencer_applied'));
select approve_influencer(pg_temp.id('a_u'), '이메일 회신 확인');
select t.fails('이미 처리된 신청 (TL409)', format('select approve_influencer(%s, %L)', pg_temp.id('a_u'), '또'), '이미 처리된 신청입니다');
reset role;
select t.ok('승인: 신청자 장인(creator)·보통 닉네임', (select influencer = 'creator' and influencer_at is not null and nickname_state is null and nickname = 'Faker' from profiles where id = :'U'));
select t.ok('승인: V는 닉네임 변경 예정 (3일 뒤)', (select nickname_state = 'yielding' and nickname_reset_at between now() + interval '2 days 23 hours' and now() + interval '3 days 1 hour' from profiles where id = :'V'));
select t.ok('승인되면 공식 이메일 지움, 채널은 남김', (select official_email is null and channel_url is not null and status = 'approved' and review_note = '이메일 회신 확인' from influencer_applications where id = pg_temp.id('a_u')));
select t.ok('알림: 신청자 influencer_approved / V nickname_reset_soon',
  exists (select 1 from notifications where user_id = :'U' and kind = 'influencer_approved' and message = '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.')
  and exists (select 1 from notifications where user_id = :'V' and kind = 'nickname_reset_soon'
                 and message = '운영 원칙에 따라 3일 뒤 닉네임이 임시 닉네임으로 바뀝니다. 그 전에 새 닉네임을 정해 주세요.'));
select t.ok('처리 기록 approve_influencer (메모, 대상 닉네임)', exists (select 1 from moderation_log where action = 'approve_influencer' and target_kind = 'influencer_application'
  and target_id = pg_temp.id('a_u')::text and note = '이메일 회신 확인' and target_nickname = 'Faker'));
select t.ok('사람 json: 기여자 목록에 장인 유형·닉네임 상태 칸', exists (
  select 1 from jsonb_array_elements(public.build_contributors((select id from builds where status = 'approved' order by id limit 1))) e
   where e ? 'influencer' and e ? 'nickname_state'));
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('장인은 닉네임을 직접 못 바꿈', $$update public.profiles set nickname = '페이커' where id = auth.uid()$$, '인증된 장인은 닉네임을 직접 바꿀 수 없습니다');
select t.fails('장인은 다시 신청 불가', $$select apply_influencer('pro', 'Faker', 'https://twitch.tv/faker', 'f@x.com')$$, '이미 인증된 장인입니다');
set request.jwt.claim.sub = :'T';
select t.fails('장인 닉네임은 아무도 못 가져감', $$update public.profiles set nickname = 'faker' where id = auth.uid()$$, '이미 사용 중인 닉네임');
select t.fails('장인이 쓰는 닉네임으로 신청 불가', $$select apply_influencer('creator', 'FAKER', 'https://youtube.com/@t', 't@x.com')$$, '이미 인증된 장인이 쓰는 닉네임입니다');
reset role;

-- ===== 7. 하루 작업: 유예가 끝난 V → 임시 닉네임, 그 뒤 바로 새 닉네임 =====
update profiles set nickname_reset_at = now() - interval '1 minute' where id = :'V';
update nickname_changes set changed_at = now() where user_id = :'V';
insert into nickname_changes (user_id, old_nickname, new_nickname, kind) values (:'V', '브이', 'Faker', 'user');  -- 방금 직접 바꾼 기록이 있어도
select t.ok('하루 작업 결과 (임시 닉네임 1)', (influencer_daily() ->> 'nickname_reset')::int = 1);
select t.ok('V는 임시 닉네임 탑신병자#xxxxxx, 상태 비움', (select nickname ~ '^탑신병자#[0-9a-f]{6}$' and nickname_state is null and nickname_reset_at is null from profiles where id = :'V'));
select t.ok('V 알림 nickname_reset', exists (select 1 from notifications where user_id = :'V' and kind = 'nickname_reset'
  and message = '운영 원칙에 따라 닉네임이 임시 닉네임으로 바뀌었습니다. 새 닉네임을 정해 주세요.'));
select t.ok('변경 기록 kind reset', exists (select 1 from nickname_changes where user_id = :'V' and kind = 'reset'));
set role authenticated;
set request.jwt.claim.sub = :'V';
update public.profiles set nickname = '브이새' where id = auth.uid();
reset role;
select t.ok('임시 닉네임 뒤에는 30일 제한 없이 바로 바꿈', (select nickname from profiles where id = :'V') = '브이새');
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails('그다음 직접 바꾸기는 다시 30일 제한', $$update public.profiles set nickname = '브이넷' where id = auth.uid()$$, '30일에 한 번');
reset role;

-- ===== 8. (b) 승인 → 겹친 X(Chovy)는 유예 중에도 바로 직접 바꿀 수 있음 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select approve_influencer(pg_temp.id('b_w'), '친구 요청 확인');
reset role;
select t.ok('(b) 승인: 라이엇 ID 원문 지움, 해시만 남음', (select riot_id is null and riot_key is not null from influencer_applications where id = pg_temp.id('b_w')));
select t.ok('X는 닉네임 변경 예정', (select nickname_state from profiles where id = :'X') = 'yielding');
insert into nickname_changes (user_id, old_nickname, new_nickname, kind) values (:'X', '촙', 'Chovy', 'user');
set role authenticated;
set request.jwt.claim.sub = :'X';
update public.profiles set nickname = '엑스새' where id = auth.uid();
reset role;
select t.ok('변경 예정인 사람은 30일 제한 없이 바꾸고 상태가 풀림', (select nickname = '엑스새' and nickname_state is null and nickname_reset_at is null from profiles where id = :'X'));
set role authenticated;
set request.jwt.claim.sub = :'T';
select t.fails('승인된 라이엇 닉네임#태그는 계속 막힘', $$select apply_influencer('grandmaster', '티이', null, null, 'hide on bush#KR1', 'https://op.gg/x')$$, '이미 신청됐거나 인증된 라이엇 닉네임입니다');
reset role;

-- ===== 9. 반려 (겹침 → 이전 닉네임으로 되돌림, 7일 제한, 채널은 바로 풀림, 메모는 신청자에게만) =====
set role authenticated;
set request.jwt.claim.sub = :'R';
insert into ids values ('a_r', apply_influencer('creator', 'zeus', 'https://youtube.com/@zeus', 'zeus@x.com'));
set request.jwt.claim.sub = :'OP';
select reject_influencer(pg_temp.id('a_r'), 'SECRET-NOTE-1 회신 없음');
reset role;
select t.ok('반려: 겹쳤으므로 이전 닉네임 "알"로 되돌림', (select nickname = '알' and nickname_state is null from profiles where id = :'R'));
select t.ok('반려 줄: 이메일 지움·되돌린 닉네임·처리자', (select status = 'rejected' and official_email is null and nickname_reverted = '알' and reviewed_by = :'OP'
  from influencer_applications where id = pg_temp.id('a_r')));
select t.ok('S(Zeus)는 그대로', (select nickname = 'Zeus' and nickname_state is null from profiles where id = :'S'));
select t.ok('반려 알림 (사유 · 7일 · 되돌린 닉네임)', exists (select 1 from notifications where user_id = :'R' and kind = 'influencer_rejected'
  and message = '장인 인증이 반려됐습니다. 사유: SECRET-NOTE-1 회신 없음 · 7일 뒤 다시 신청할 수 있습니다. 닉네임은 신청 전 닉네임 「알」(으)로 되돌렸습니다.'));
select t.ok('처리 기록 reject_influencer', exists (select 1 from moderation_log where action = 'reject_influencer' and target_id = pg_temp.id('a_r')::text));
set role authenticated;
set request.jwt.claim.sub = :'R';
select t.fails('반려 뒤 7일은 다시 신청 불가', $$select apply_influencer('creator', '알', 'https://youtube.com/@zeus', 'zeus@x.com')$$, '부터 다시 신청할 수 있습니다');
select t.ok('되돌린 닉네임 뒤에는 바로 바꿀 수 있음 (kind revert)', (select kind from nickname_changes where user_id = auth.uid() order by id desc limit 1) = 'revert');
set request.jwt.claim.sub = :'T';
insert into ids values ('a_t', apply_influencer('creator', '티', 'https://youtube.com/@zeus', 'real-zeus@x.com'));
reset role;
select t.ok('반려된 채널은 다른 사람이 바로 신청 가능 (선점 방해 막기)', pg_temp.id('a_t') is not null);
select t.ok('신청 줄 메모·이메일이 신청자 말고 다른 사람 알림에 없음', not exists (
  select 1 from notifications where user_id <> :'R' and (message like '%SECRET-NOTE-1%' or message like '%zeus@x.com%' or message like '%t1.gg%')));
select t.ok('지금 닉네임과 같은 희망 닉네임: 이름은 그대로, 인증 대기', (select nickname = '티' and nickname_state = 'pending' from profiles where id = :'T'));

-- ===== 10. 반려 옵션: 겹치지 않았으면 닉네임 그대로 / [닉네임도 되돌리기] / [바로 다시 신청 허용] =====
set role authenticated;
set request.jwt.claim.sub = :'S';
insert into ids values ('a_s', apply_influencer('pro', 'ZeusPro', 'https://twitch.tv/zeus', 'z@x.com'));
set request.jwt.claim.sub = :'OP';
select reject_influencer(pg_temp.id('a_s'), '팀 페이지 이메일과 다름');
reset role;
select t.ok('겹치지 않았던 반려는 닉네임 그대로 (인증 대기만 풀림)', (select nickname = 'ZeusPro' and nickname_state is null from profiles where id = :'S'));
update influencer_applications set ended_at = now() - interval '8 days' where id = pg_temp.id('a_s');
set role authenticated;
set request.jwt.claim.sub = :'S';
insert into ids values ('a_s2', apply_influencer('pro', 'Zeus2', 'https://twitch.tv/zeus', 'z@x.com'));
set request.jwt.claim.sub = :'OP';
select reject_influencer(pg_temp.id('a_s2'), '오타', true, true);
reset role;
select t.ok('[닉네임도 되돌리기]: 신청 전 닉네임으로', (select nickname from profiles where id = :'S') = 'ZeusPro');
select t.ok('[바로 다시 신청 허용] 알림 문장', exists (select 1 from notifications where user_id = :'S' and kind = 'influencer_rejected'
  and message like '장인 인증이 반려됐습니다. 사유: 오타 · 바로 다시 신청할 수 있습니다.%'));
select t.ok('[바로 다시 신청 허용]이면 다시 신청 가능 (앞 반려는 8일 전)', public.influencer_next_apply_at(:'S') is null);

-- 이전 닉네임을 이미 다른 사람이 쓰면 임시 닉네임
set role authenticated;
set request.jwt.claim.sub = :'S';
insert into ids values ('a_s3', apply_influencer('pro', 'Zeus3', 'https://twitch.tv/zeus', 'z@x.com'));
reset role;
update profiles set nickname = 'zeuspro' where id = :'MOD';  -- 이전 닉네임(ZeusPro)을 누가 가져감 (검사용으로 직접)
set role authenticated;
set request.jwt.claim.sub = :'OP';
select reject_influencer(pg_temp.id('a_s3'), '되돌림 확인', true, false);
reset role;
select t.ok('이전 닉네임이 쓰이고 있으면 임시 닉네임', (select nickname ~ '^탑신병자#' from profiles where id = :'S'));
select t.ok('그 알림에 임시 닉네임 안내', exists (select 1 from notifications where user_id = :'S' and message like '%임시 닉네임 「탑신병자#%」(으)로 바뀌었습니다. 새 닉네임을 정해 주세요.'));

-- 180일 동안 반려 3번 → 마지막 반려부터 180일 ([바로 다시 신청 허용]·만료는 안 셈)
update influencer_applications set ended_at = now() - interval '100 days' where id = pg_temp.id('a_s');
select t.ok('세는 반려 2번(+허용 1번)이면 7일 제한만', public.influencer_next_apply_at(:'S') between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour');
insert into influencer_applications (user_id, kind, nickname, channel_url, channel_key, status, expires_at, ended_at, review_note)
values (:'S', 'pro', 'z', 'https://twitch.tv/z9', 'twitch.tv/z9', 'rejected', now(), now() - interval '50 days', '세 번째');
select t.ok('세는 반려 3번이면 마지막 반려부터 180일', public.influencer_next_apply_at(:'S') between now() + interval '179 days 23 hours' and now() + interval '180 days 1 hour');

-- ===== 11. 만료 · 만료 전 알림 (한 번만) · 만료일 늘리기 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관은 만료일 늘리기 불가', format('select extend_influencer_application(%s)', pg_temp.id('a_t')), '운영자만 할 수 있습니다');
set request.jwt.claim.sub = :'OP';
select t.ok('만료일 7일 늘리기', (select e between now() + interval '20 days 23 hours' and now() + interval '21 days 1 hour'
  from (select extend_influencer_application(pg_temp.id('a_t')) as e) x));  -- between은 왼쪽을 두 번 계산하므로 한 번만 부름
reset role;
select t.ok('늘린 횟수·처리 기록', (select extended_count from influencer_applications where id = pg_temp.id('a_t')) = 1
  and exists (select 1 from moderation_log where action = 'extend_influencer' and target_id = pg_temp.id('a_t')::text));
update influencer_applications set expires_at = now() + interval '2 days 12 hours' where id = pg_temp.id('a_t');
select influencer_daily();
select influencer_daily();
select t.ok('만료 전 알림은 한 번만 ((a) 문장)', (select count(*) from notifications where user_id = :'T' and kind = 'influencer_expiring') = 1
  and exists (select 1 from notifications where user_id = :'T' and kind = 'influencer_expiring'
                 and message = '신청이 3일 뒤 만료됩니다. 확인 메일에 아직 회신하지 않았다면 만료되기 전에 회신해 주세요.'));
update influencer_applications set created_at = now() - interval '21 days', expires_at = now() - interval '1 minute' where id = pg_temp.id('a_t');
select t.ok('하루 작업: 만료 1', (influencer_daily() ->> 'expired')::int = 1);
select t.ok('만료: 상태·이메일 지움·인증 대기 풀림 (겹침 없어 닉네임 그대로)',
  (select status = 'expired' and official_email is null and ended_at is not null from influencer_applications where id = pg_temp.id('a_t'))
  and (select nickname = '티' and nickname_state is null from profiles where id = :'T'));
select t.ok('만료 알림 (늘린 기간 포함 일수)', exists (select 1 from notifications where user_id = :'T' and kind = 'influencer_expired'
  and message = '21일 안에 확인이 끝나지 않아 신청이 만료됐습니다. 다시 신청할 수 있습니다.'));
select t.ok('만료는 반려에 세지 않음 → 바로 다시 신청 가능', public.influencer_next_apply_at(:'T') is null);
-- (b) 만료 전 알림 문장
set role authenticated;
set request.jwt.claim.sub = :'T';
insert into ids values ('b_t', apply_influencer('grandmaster', '티', null, null, 'Tee#KR2', 'https://op.gg/summoners/kr/Tee-KR2'));
reset role;
update influencer_applications set expires_at = now() + interval '1 day' where id = pg_temp.id('b_t');
select influencer_daily();
select t.ok('(b) 만료 전 알림에 운영자 계정 자리표시', exists (select 1 from notifications where user_id = :'T' and kind = 'influencer_expiring'
  and message = '신청이 1일 뒤 만료됩니다. 아직 친구 요청을 보내지 않았다면 {운영자 닉네임}으로 보내 주세요.'));

-- ===== 12. 취소 · 탈퇴 (개인정보 지움) =====
set role authenticated;
set request.jwt.claim.sub = :'T';
select cancel_influencer_application(pg_temp.id('b_t'));
reset role;
select t.ok('취소: 라이엇 ID·해시 지움, 상태 cancelled', (select status = 'cancelled' and riot_id is null and riot_key is null from influencer_applications where id = pg_temp.id('b_t')));
set role authenticated;
set request.jwt.claim.sub = :'T';
insert into ids values ('b_t2', apply_influencer('grandmaster', '티', null, null, 'Tee#KR2', 'https://op.gg/summoners/kr/Tee-KR2'));
set request.jwt.claim.sub = :'V';
select t.fails('남의 신청은 취소 불가', format('select cancel_influencer_application(%s)', pg_temp.id('b_t2')), '신청을 찾지 못했습니다');
reset role;
delete from auth.users where id = :'T';
select t.ok('탈퇴: 신청 줄은 남고 사람·라이엇 ID·해시를 지움, 상태 withdrawn',
  (select user_id is null and status = 'withdrawn' and riot_id is null and riot_key is null and ended_at is not null from influencer_applications where id = pg_temp.id('b_t2')));

-- ===== 13. 인증 해제 · 운영자가 닉네임 바꾸기 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관은 인증 해제 불가', format('select revoke_influencer(%L, %L)', :'U', '사유'), '운영자만 할 수 있습니다');
select t.fails('감독관은 닉네임 바꾸기 불가', format('select admin_set_nickname(%L, %L, %L)', :'U', '페이커', '요청'), '운영자만 할 수 있습니다');
set request.jwt.claim.sub = :'OP';
select t.fails('운영자 닉네임 바꾸기도 비슷한 닉네임 막음', format('select admin_set_nickname(%L, %L, %L)', :'U', 'CH0VY', '요청'), '이미 사용 중인 닉네임');
select admin_set_nickname(:'U', '페이커', '본인 요청 (문의 12)');
reset role;
select t.ok('운영자가 장인 닉네임을 바꿈 (kind admin, 처리 기록 rename_member)', (select nickname from profiles where id = :'U') = '페이커'
  and exists (select 1 from nickname_changes where user_id = :'U' and kind = 'admin')
  and exists (select 1 from moderation_log where action = 'rename_member' and target_id = :'U'::text));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select revoke_influencer(:'U', '사칭 확인');
reset role;
select t.ok('해제: 장인 표시 없어짐, 신청 줄 revoked', (select influencer is null and influencer_at is null from profiles where id = :'U')
  and (select status = 'revoked' and revoke_note = '사칭 확인' from influencer_applications where id = pg_temp.id('a_u')));
select t.ok('해제 알림', exists (select 1 from notifications where user_id = :'U' and kind = 'influencer_revoked' and message = '장인 인증이 해제됐습니다. 사유: 사칭 확인'));
select t.ok('해제된 채널은 다시 신청 가능 (겹침 판정에서 빠짐)', not exists (select 1 from influencer_applications where channel_key = 'youtube.com/@faker' and status in ('pending', 'approved')));

-- ===== 14. 1년 정리 =====
update influencer_applications set ended_at = now() - interval '366 days' where id = pg_temp.id('a_r');
update influencer_applications set revoked_at = now() - interval '366 days' where id = pg_temp.id('a_u');
select t.ok('하루 작업: 끝난 지 1년 지난 신청 2건 정리', (influencer_daily() ->> 'purged')::int = 2);
select t.ok('승인 중인 신청은 남음', exists (select 1 from influencer_applications where id = pg_temp.id('b_w') and status = 'approved'));

-- ===== 15. 알림 종류 · 푸시 묶음 =====
select t.ok('푸시 묶음: 운영자 신청 알림 staff_new, 신청자·회원 알림 my_results',
  public.push_group('influencer_applied') = 'staff_new'
  and (select bool_and(public.push_group(k) = 'my_results') from unnest(array['influencer_received', 'influencer_expiring', 'influencer_approved',
       'influencer_rejected', 'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed']) k)
  and public.push_group('report_received') = 'staff_new' and public.push_group('error_report_handled') is null);
insert into notifications (user_id, kind, message) values (:'U', 'link_removed', '프로필에 올린 링크가 운영 원칙에 따라 삭제됐습니다.');
select t.ok('link_removed 종류를 넣을 수 있음 (047에서 씀)', exists (select 1 from notifications where kind = 'link_removed'));

-- ===== 16. 신규 가입자 (운영자 전용, 정식 회원만, 24시간 경계) =====
update profiles set created_at = now() - interval '23 hours 59 minutes' where id = :'U';
update profiles set created_at = now() - interval '24 hours 1 minute' where id = :'V';
update profiles set created_at = now() - interval '1 hour' where id = :'GU';
update profiles set created_at = now() - interval '30 days' where id not in (:'U', :'V', :'GU');
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관은 신규 가입자 불가', $$select admin_new_members()$$, '운영자만 할 수 있습니다');
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원도 불가', $$select admin_new_members()$$, '운영자만 할 수 있습니다');
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.fails('운영자 모드를 끄면 불가', $$select admin_new_members()$$, '운영자만 할 수 있습니다');
select set_operator_mode(true);
select admin_new_members()::text as nm \gset
select t.ok('24시간 안: U(23시간 59분)만, V(24시간 1분)·비회원 제외',
  (select array_agg(m ->> 'id') from jsonb_array_elements(:'nm'::jsonb -> 'members') m) = array[:'U'::text]
  and (:'nm'::jsonb ->> 'total')::int = 1 and (:'nm'::jsonb ->> 'hours')::int = 24);
select t.ok('칸은 id·닉네임·가입일·가입 방식·역할뿐, 가입 방식은 이름만',
  (select bool_and(k in ('id', 'nickname', 'created_at', 'providers', 'role')) from jsonb_array_elements(:'nm'::jsonb -> 'members') r, jsonb_object_keys(r) k)
  and (:'nm'::jsonb -> 'members' -> 0 -> 'providers') = '["google"]'::jsonb);
select t.ok('이메일·로그인 ID 글자가 없음', :'nm' !~ '(u@x\.com|SECRET-GOOGLE-ID|k-1|g-2)');
select t.ok('48시간이면 V도 (구글·카카오 둘 다)', (select (m -> 'providers') = '["google", "kakao"]'::jsonb
  from jsonb_array_elements(admin_new_members(48) -> 'members') m where (m ->> 'id')::uuid = :'V'));
select t.ok('쪽 나누기 (크기 1, 2쪽)', jsonb_array_length(admin_new_members(48, 2, 1) -> 'members') = 1 and (admin_new_members(48, 2, 1) ->> 'total')::int = 2);
reset role;
select t.ok('보여 주는 기간일 뿐 지우지 않음', (select count(*) from profiles where id = :'V') = 1);

-- ===== 17. 장인 빌드 라벨용 기여자 수 · 권한 =====
insert into ids select 'b1', id from builds where status = 'approved' order by id limit 1;
insert into build_editors (build_id, user_id) values (pg_temp.id('b1'), :'X'), (pg_temp.id('b1'), :'W');
set role anon;
select t.ok('기여자 수(시초 제외): 누구나 읽음', (build_editor_counts((select counter_id from builds where id = pg_temp.id('b1'))) ->> pg_temp.id('b1')::text)::int = 2);
reset role;
select t.ok('비로그인은 신청·운영자 함수 실행 권한 없음', not has_function_privilege('anon', 'public.apply_influencer(text, text, text, text, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.admin_new_members(integer, integer, integer)', 'execute'));
select t.ok('안쪽 함수는 아무도 못 부름', not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('influencer_daily', 'influencer_close', 'system_set_nickname', 'approve_influencer_unchecked', 'reject_influencer_unchecked',
                       'admin_new_members_unchecked', 'admin_influencer_applications_unchecked', 'revoke_influencer_unchecked',
                       'admin_set_nickname_unchecked', 'extend_influencer_application_unchecked', 'influencer_temp_nickname')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
select t.ok('신청 표: 로그인 사용자는 읽기만 (쓰기 권한 없음)', not has_table_privilege('authenticated', 'public.influencer_applications', 'insert')
  and not has_table_privilege('authenticated', 'public.influencer_applications', 'update') and has_table_privilege('authenticated', 'public.influencer_applications', 'select'));
select t.ok('프로필의 장인 칸은 직접 못 고침', not has_column_privilege('authenticated', 'public.profiles', 'influencer', 'update')
  and not has_column_privilege('authenticated', 'public.profiles', 'nickname_state', 'update'));
