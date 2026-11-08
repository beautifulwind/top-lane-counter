-- =====================================================================
-- 032: 문의하기 (2026-11-08, SPEC 6-19)
-- 1. 표 inquiries: 로그인한 사람(비회원·닉네임 전 포함)이 운영진에게 보내는 문의 + 답변 1개.
--    분류 bug(오류 신고) / idea(건의) / account(계정·탈퇴) / other(기타). 제목 없음.
-- 2. 읽기(RLS): 본인 것 / 운영자는 전부 / 감독관은 account 빼고. 직접 쓰기는 아무도 못 함 (함수로만).
-- 3. 함수: create_inquiry(하루 3건·글자 수), answer_inquiry(운영진, 감독관은 account 불가, 보낸 사람에게 알림),
--    set_inquiry_category(운영자만 분류 옮기기), delete_my_inquiry(본인), purge_old_inquiries(pg_cron만).
-- 4. 하루 개수는 따로 센다(inquiry_quota): 보낸 문의를 지워도 그날 3건이 되살아나지 않게.
-- 5. 보관: 마지막 활동(접수 또는 답변) 뒤 inquiry_keep_days(180)일이 지나면 지운다. 탈퇴하면 함께 지운다.
-- 6. 처리 기록: moderation_log에 answer_inquiry·move_inquiry (문의 내용은 남기지 않고 번호만).
-- 숫자(하루 개수·글자 수·보관 기간)는 xp_rules 한 곳. 알림 종류 inquiry_answered 추가.
--
-- 하위 호환: 있던 것은 하나도 바꾸지 않고 더하기만 한다(제약 두 개와 알림 종류 목록만 넓힘).
-- 지금 배포된 화면과 그대로 동작한다. 순서: 이 파일 실행 → 확인 → 새 코드 push.
-- 031까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. pg_cron 일정은 파일 맨 아래 SQL을 따로 한 번.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 설정값
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('inquiry_daily_max', 3, '문의하기: 한 사람이 하루(한국 시간)에 보낼 수 있는 문의 수'),
  ('inquiry_min', 5, '문의하기: 내용 최소 글자 수 (앞뒤 공백 제외)'),
  ('inquiry_max', 1000, '문의하기: 내용 최대 글자 수'),
  ('inquiry_answer_max', 2000, '문의하기: 답변 최대 글자 수'),
  ('inquiry_keep_days', 180, '문의하기: 보관 기간(일) — 마지막 활동(접수 또는 답변) 뒤 이만큼 지나면 매일 지운다 (purge_old_inquiries, pg_cron)')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. 표
-- ---------------------------------------------------------------------
create table public.inquiries (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,  -- 탈퇴·비회원 정리 때 함께 지움
  category    text not null check (category in ('bug', 'idea', 'account', 'other')),
  body        text not null,
  created_at  timestamptz not null default now(),
  answer      text,
  answered_at timestamptz
);
create index inquiries_user_recent on public.inquiries (user_id, id desc);
create index inquiries_waiting on public.inquiries (id desc) where answer is null;
comment on table public.inquiries is
  '문의하기 (032). 읽기: 본인 / 운영자 전부 / 감독관은 account(계정·탈퇴) 빼고. 쓰기는 함수로만. 마지막 활동 뒤 inquiry_keep_days(180)일에 지움, 탈퇴하면 함께 지움';

-- 하루 보낸 개수 (문의를 지워도 되살아나지 않게 따로 센다). 아무도 직접 못 읽고 못 씀
create table public.inquiry_quota (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  day     date not null,
  sent    integer not null default 0
);
comment on table public.inquiry_quota is '문의 하루 개수 세기 (032). 접근은 create_inquiry만';

revoke all on public.inquiries, public.inquiry_quota from anon, authenticated;
grant select on public.inquiries to authenticated;
alter table public.inquiries enable row level security;
alter table public.inquiry_quota enable row level security;  -- 정책 없음 = 함수로만

create policy "inquiries: 본인·운영진 읽기" on public.inquiries for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_admin()
    or (public.is_moderator() and category <> 'account')
  );

-- ---------------------------------------------------------------------
-- 3. 알림 종류, 처리 기록 종류
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in ('revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected', 'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked', 'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked', 'inquiry_answered'));

alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action in (
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry'));
alter table public.moderation_log drop constraint moderation_log_target_kind_check;
alter table public.moderation_log add constraint moderation_log_target_kind_check check (
  target_kind in ('post', 'comment', 'doc_comment', 'proposal', 'user', 'inquiry'));

-- ---------------------------------------------------------------------
-- 4. 함수
-- ---------------------------------------------------------------------
create function public.inquiry_category_label(p_category text)
returns text language sql immutable set search_path = ''
as $$
  select case p_category when 'bug' then '오류 신고' when 'idea' then '건의' when 'account' then '계정·탈퇴' else '기타' end;
$$;

-- 문의 보내기: 로그인한 사람 누구나(비회원·닉네임 전 포함). 하루 개수는 한국 시간 기준, 프로필 줄을 잠가 동시에 눌러도 넘지 못한다
create function public.create_inquiry(p_category text, p_body text)
returns bigint language plpgsql security definer set search_path = ''
as $$
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
  if p_category is null or p_category not in ('bug', 'idea', 'account', 'other') then
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
$$;

-- 답변: 운영진만. 감독관은 계정·탈퇴 분류 불가, 본인 문의 불가, 이미 답변이 있으면 TL409(이미 다른 분이 처리했습니다)
create function public.answer_inquiry(p_id bigint, p_answer text)
returns void language plpgsql security definer set search_path = ''
as $$
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
  if i.category = 'account' and public.is_moderator() then  -- require_staff를 지났으니 운영자가 아니면 감독관
    raise exception '"계정·탈퇴" 문의는 운영자만 답변할 수 있습니다.' using errcode = '42501';
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
$$;

-- 분류 옮기기: 운영자만 (예: 계정 문제가 "기타"로 와서 감독관에게 보일 때 "계정·탈퇴"로)
create function public.set_inquiry_category(p_id bigint, p_category text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  i public.inquiries%rowtype;
begin
  perform public.require_operator();
  if p_category is null or p_category not in ('bug', 'idea', 'account', 'other') then
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
$$;

-- 내 문의 지우기 (본인만, 언제든)
create function public.delete_my_inquiry(p_id bigint)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  delete from public.inquiries where id = p_id and user_id = me;
  if not found then
    raise exception '문의를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
end;
$$;

-- 보관 기간이 지난 문의 지우기 (마지막 활동 = 답변 시각, 없으면 접수 시각). 사람은 못 부르고 pg_cron만
create function public.purge_old_inquiries()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  delete from public.inquiries
   where coalesce(answered_at, created_at) < now() - make_interval(days => public.xp_rule('inquiry_keep_days'));
  get diagnostics n = row_count;
  delete from public.inquiry_quota where day < ((now() at time zone 'Asia/Seoul')::date - 2);
  return n;
end;
$$;

revoke execute on function public.inquiry_category_label(text) from public, anon, authenticated;
revoke execute on function public.purge_old_inquiries() from public, anon, authenticated;
revoke execute on function public.create_inquiry(text, text) from public, anon;
revoke execute on function public.answer_inquiry(bigint, text) from public, anon;
revoke execute on function public.set_inquiry_category(bigint, text) from public, anon;
revoke execute on function public.delete_my_inquiry(bigint) from public, anon;
grant execute on function public.create_inquiry(text, text) to authenticated;
grant execute on function public.answer_inquiry(bigint, text) to authenticated;
grant execute on function public.set_inquiry_category(bigint, text) to authenticated;
grant execute on function public.delete_my_inquiry(bigint) to authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_inquiries.sql

-- ---------------------------------------------------------------------
-- pg_cron 일정 등록 (위를 실행한 뒤 따로 한 번): 매일 한국 시간 새벽 4시 10분 (UTC 19시 10분)
-- (같은 이름으로 다시 실행하면 일정이 바뀐다)
--
-- select cron.schedule('purge-old-inquiries', '10 19 * * *', $$select public.purge_old_inquiries()$$);
--
-- 확인: select jobname, schedule, command, active from cron.job where jobname = 'purge-old-inquiries';
-- 끄기: select cron.unschedule('purge-old-inquiries');
-- ---------------------------------------------------------------------
