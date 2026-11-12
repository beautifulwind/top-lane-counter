-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 049: 운영자가 장인을 직접 지정 (권한/대상/메모, 신청 표 줄, 알림/처리 기록, 승인된 장인과 같은 동작, 인증 해제)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set R   '00000000-0000-0000-0000-000000000012'
\set S   '00000000-0000-0000-0000-000000000013'
\set GU  '00000000-0000-0000-0000-000000000010'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'),
  (:'W', 'w@x.com'), (:'R', 'r@x.com'), (:'S', 's@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '보통' where id = :'V';
update public.profiles set nickname = '이미장인', influencer = 'pro', influencer_at = now() where id = :'W';
update public.profiles set nickname = '신청자' where id = :'R';
update public.profiles set nickname = '에스' where id = :'S';
update public.profiles set nickname = '손님' where id = :'GU';
delete from nickname_changes;
delete from notifications;
delete from moderation_log;

-- ===== 0. 준비: R은 장인 신청 중, S는 V와 같은 닉네임으로 신청 중 =====
set role authenticated;
set request.jwt.claim.sub = :'R';
select apply_influencer('creator', '신청자', 'https://youtube.com/@rrr', 'r@x.com');
set request.jwt.claim.sub = :'S';
select apply_influencer('creator', '보통', 'https://youtube.com/@sss', 's@x.com');
reset role;
delete from notifications;
create temp table base as select (select count(*) from moderation_log) as logs, (select count(*) from notifications) as notes,
  (select count(*) from influencer_applications) as apps, (select count(*) from profiles where influencer is not null) as infl;
grant select on base to authenticated;
select t.ok('처리 기록 종류에 grant_influencer', (select pg_get_constraintdef(oid) like '%grant_influencer%' from pg_constraint
  where conname = 'moderation_log_action_check' and conrelid = 'public.moderation_log'::regclass));
select t.ok(E'알림 종류는 그대로 (grant용 새 종류 없음)', (select pg_get_constraintdef(oid) not like '%influencer_granted%' from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass));

-- ===== 1. 권한 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관 거부', format('select grant_influencer(%L, %L, %L)', :'U', 'creator', 'x'), '운영자만');
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원 거부', format('select grant_influencer(%L, %L, %L)', :'U', 'creator', 'x'), '운영자만');
select t.fails('안쪽 함수는 직접 못 부름', format('select grant_influencer_unchecked(%L, %L, %L)', :'U', 'creator', 'x'), 'permission denied');
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.fails('운영자 모드 꺼짐 거부', format('select grant_influencer(%L, %L, %L)', :'U', 'creator', 'x'), '운영자만');
select set_operator_mode(true);
reset role;
set role anon;
select t.fails('비로그인 거부', format('select grant_influencer(%L, %L, %L)', :'U', 'creator', 'x'), 'permission denied');
reset role;

-- ===== 2. 대상/입력 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('메모 없으면 거부', format('select grant_influencer(%L, %L, %L)', :'U', 'creator', '   '), '지정 메모를 적어 주세요');
select t.fails('메모 null도 거부', format('select grant_influencer(%L, %L, null)', :'U', 'creator'), '지정 메모를 적어 주세요');
select t.fails(E'메모 501자 거부', format('select grant_influencer(%L, %L, %L)', :'U', 'creator', repeat('a', 501)), '500자 이하');
select t.fails('유형 없으면 거부', format('select grant_influencer(%L, null, %L)', :'U', 'x'), '유형을 골라 주세요');
select t.fails('없는 유형 거부', format('select grant_influencer(%L, %L, %L)', :'U', 'streamer', 'x'), '유형을 골라 주세요');
select t.fails('없는 회원', format('select grant_influencer(%L, %L, %L)', '00000000-0000-0000-0000-0000000000ff', 'creator', 'x'), '회원을 찾지 못했습니다');
select t.fails(E'게스트(비회원) 거부', format('select grant_influencer(%L, %L, %L)', :'GU', 'creator', 'x'), E'구글\u00B7카카오로 로그인한 정식 회원만');
select t.fails('이미 장인 거부', format('select grant_influencer(%L, %L, %L)', :'W', 'creator', 'x'), '이미 인증된 장인입니다');
select t.fails('운영자 계정 거부', format('select grant_influencer(%L, %L, %L)', :'OP', 'creator', 'x'), '운영자 계정은 장인으로 지정할 수 없습니다');
select t.fails(E'신청 처리 전 거부 + 심사 화면에서 승인하라는 안내', format('select grant_influencer(%L, %L, %L)', :'R', 'creator', 'x'),
  '심사 화면에서 그 신청을 승인해 주세요');
select t.fails(E'같은 닉네임으로 다른 사람이 신청 중이면 거부', format('select grant_influencer(%L, %L, %L)', :'V', 'creator', 'x'),
  '같은(비슷한) 닉네임으로 장인 인증을 신청 중인 회원이 있습니다');
reset role;
update public.profiles set nickname_state = 'yielding', nickname_reset_at = now() + interval '3 days' where id = :'V';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('닉네임 변경 예정 회원 거부', format('select grant_influencer(%L, %L, %L)', :'V', 'creator', 'x'), '닉네임이 바뀔 예정인 회원입니다');
reset role;
update public.profiles set nickname_state = null, nickname_reset_at = null where id = :'V';
select t.ok('거부된 지정은 아무것도 바꾸지 않음', (select count(*) from moderation_log) = (select logs from base)
  and (select count(*) from notifications) = (select notes from base)
  and (select count(*) from influencer_applications) = (select apps from base)
  and (select count(*) from profiles where influencer is not null) = (select infl from base));

-- ===== 3. 지정 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('지정: 신청 번호를 돌려줌', grant_influencer(:'U', 'grandmaster', '  op.gg 직접 확인  ') > 0);
reset role;
select t.ok('지정: 장인 표시 + 인증일', (select influencer = 'grandmaster' and influencer_at is not null and nickname_state is null from profiles where id = :'U'));
select t.ok('지정: 닉네임은 그대로, 닉네임 변경 기록 없음', (select nickname = '유저' from profiles where id = :'U')
  and not exists (select 1 from nickname_changes where user_id = :'U'));
select t.ok(E'지정: 신청 표에 승인된 직접 지정 줄 (개인정보/링크 칸 없음)', (select count(*) = 1 from influencer_applications
  where user_id = :'U' and direct and status = 'approved' and kind = 'grandmaster' and nickname = '유저' and old_nickname is null
    and channel_url is null and official_email is null and riot_id is null and riot_key is null and opgg_url is null
    and ended_at is not null and reviewed_by = :'OP' and review_note = 'op.gg 직접 확인'));
select t.ok('지정: influencer_approved 알림 (승인과 같은 문장)', (select count(*) = 1 from notifications where user_id = :'U' and kind = 'influencer_approved'
  and message = '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.'));
select t.ok('지정: 다른 사람에게는 알림 없음', not exists (select 1 from notifications where user_id <> :'U'));
select t.ok(E'지정: 처리 기록 grant_influencer (대상 회원, 메모 유형\u00B7지정 메모)', exists (select 1 from moderation_log
  where action = 'grant_influencer' and target_kind = 'user' and target_id = :'U' and target_nickname = '유저' and actor_role = 'admin'
    and note = E'그랜드마스터 이상 \u00B7 op.gg 직접 확인'));
select t.fails('직접 넣은 지정 줄도 표 검사: direct인데 채널이 있으면 거부',
  format($q$insert into influencer_applications (user_id, kind, nickname, status, expires_at, ended_at, channel_url, channel_key, direct)
            values (%L, 'creator', 'x', 'approved', now(), now(), 'https://a.com/b', 'a.com/b', true)$q$, :'V'), 'influencer_applications_fields');
select t.fails('지정 줄은 처리 전일 수 없음',
  format($q$insert into influencer_applications (user_id, kind, nickname, status, expires_at, direct) values (%L, 'creator', 'x', 'pending', now(), true)$q$, :'V'),
  'influencer_applications_fields');

-- ===== 4. 승인된 장인과 같은 동작 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('두 번 지정 거부', format('select grant_influencer(%L, %L, %L)', :'U', 'creator', 'x'), '이미 인증된 장인입니다');
select t.ok(E'운영자 목록 "끝난 신청"에 direct = true로 나옴', (select bool_or((i ->> 'direct')::boolean and i -> 'user' ->> 'id' = :'U')
  from jsonb_array_elements(admin_influencer_applications('done') -> 'items') i));
select t.ok(E'운영자 목록: 처리 전 신청은 direct = false', (select bool_and(not (i ->> 'direct')::boolean)
  from jsonb_array_elements(admin_influencer_applications('pending') -> 'items') i));
select t.ok('처리 대기 건수: 지정은 세지 않음 (처리 전 2건 그대로)', (admin_pending_counts() ->> 'influencers')::int = 2);
set request.jwt.claim.sub = :'U';
select t.fails('지정된 장인: 다시 신청 불가', $$select apply_influencer('creator', '유저', 'https://youtube.com/@uuu', 'u@x.com')$$, '이미 인증된 장인입니다');
select t.fails('지정된 장인: 닉네임 직접 변경 불가', $$update public.profiles set nickname = '유저2' where id = auth.uid()$$, '인증된 장인은 닉네임을 직접 바꿀 수 없습니다');
select t.ok(E'지정된 장인: 내 상태 = 인증된 장인, 마지막 신청은 승인된 지정 줄',
  (select s ->> 'influencer' = 'grandmaster' and s -> 'application' ->> 'status' = 'approved' from my_influencer_status() s));
select set_profile_links(array['https://youtube.com/@uuu', 'https://twitch.tv/uuu']);
select t.ok(E'지정된 장인: 프로필 링크 올리기 가능', (select count(*) = 2 from ext_links where owner_id = :'U'));
reset role;
set role anon;
select t.ok(E'지정된 장인: 공개 프로필에 유형\u00B7링크', (select p ->> 'influencer' = 'grandmaster' and jsonb_array_length(p -> 'links') = 2
  from public_profile(:'U') p));
reset role;
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails(E'다른 회원이 "유저" 닉네임으로 변경 거부', $$update public.profiles set nickname = '유저' where id = auth.uid()$$, '이미 사용 중인 닉네임입니다');
reset role;
select influencer_daily();
select t.ok(E'하루 작업: 지정 줄/장인 표시 그대로', (select influencer = 'grandmaster' from profiles where id = :'U')
  and exists (select 1 from influencer_applications where user_id = :'U' and direct and status = 'approved'));

-- ===== 5. 인증 해제 (기존 규칙 그대로) =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select revoke_influencer(:'U', '기준 미달');
reset role;
select t.ok('해제: 장인 표시 없어짐, 닉네임 그대로', (select influencer is null and influencer_at is null and nickname = '유저' from profiles where id = :'U'));
select t.ok('해제: 지정 줄이 revoked로', exists (select 1 from influencer_applications where user_id = :'U' and direct and status = 'revoked'
  and revoked_at is not null and revoke_note = '기준 미달'));
select t.ok('해제: 링크 삭제 (047 트리거)', not exists (select 1 from ext_links where owner_id = :'U'));
select t.ok('해제: influencer_revoked 알림', exists (select 1 from notifications where user_id = :'U' and kind = 'influencer_revoked'
  and message = '장인 인증이 해제됐습니다. 사유: 기준 미달'));
set role authenticated;
set request.jwt.claim.sub = :'U';
update public.profiles set nickname = '유저둘' where id = auth.uid();
reset role;
select t.ok('해제 뒤: 본인이 닉네임을 바꿀 수 있음', (select nickname = '유저둘' from profiles where id = :'U'));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select grant_influencer(:'U', 'creator', '다시 지정');
reset role;
select t.ok(E'해제 뒤 다시 지정 가능 (지정 줄 2개: 해제 1 + 승인 1)', (select count(*) = 2 from influencer_applications where user_id = :'U' and direct)
  and (select influencer = 'creator' from profiles where id = :'U'));
update influencer_applications set revoked_at = now() - interval '400 days', ended_at = now() - interval '400 days'
 where user_id = :'U' and status = 'revoked';
select influencer_daily();
select t.ok(E'하루 작업: 해제된 지 1년 지난 지정 줄만 정리', (select count(*) = 1 from influencer_applications where user_id = :'U')
  and exists (select 1 from influencer_applications where user_id = :'U' and status = 'approved'));

-- ===== 6. 신청 중이던 회원은 심사 화면에서 승인 (지정과 같은 결과) =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select approve_influencer((select id from influencer_applications where user_id = :'R' and status = 'pending'), '이메일 회신 확인');
reset role;
select t.ok(E'신청 승인 줄은 direct = false', exists (select 1 from influencer_applications where user_id = :'R' and status = 'approved' and not direct));
