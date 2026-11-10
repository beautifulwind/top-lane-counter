-- =====================================================================
-- 037: 웹 푸시 알림 — 폰 잠금 화면에 알림 (2026-11-10, SPEC 6-24)
--
-- 1. push_subscriptions: 기기 알림 주소(구독 정보). 한 줄 = 한 사람의 한 기기(브라우저)
--    - 본인 것만 읽기·넣기·지우기 (RLS). 고치기 권한은 없다 (바뀌면 지우고 새로 넣는다)
--    - 지우는 때: 알림 끄기·로그아웃(화면이 지움), 계정 탈퇴(프로필과 함께 on delete cascade),
--      만료(푸시 서버가 404·410 → Edge Function이 push_forget로 지움)
--    - 한 사람 최대 10대: 11번째를 넣으면 가장 오래된 것을 지운다
-- 2. push_settings: 알림 종류별 켜기/끄기 (운영진 알림 · 내 제안 결과). 줄이 없으면 둘 다 켜짐. 본인 것만 (RLS)
-- 3. 보내기: notifications에 줄이 생기면(트리거) 보낼 대상인지 DB가 판단하고, 대상이면 pg_net으로
--    Edge Function web-push를 부른다 (알림 번호만 보냄). Edge Function은 push_targets(번호)로 받을 기기를 받아 보낸다.
--    - 운영진 알림: proposal_submitted · build_submitted · inquiry_received (새 제안·새 빌드·새 문의)
--      받는 사람이 지금 운영진(감독관, 또는 운영자 모드가 켜진 운영자)일 때만 — 운영자 모드를 끄면 안 간다
--    - 내 제안 결과: proposal_approved · proposal_rejected · build_approved · build_rejected ·
--      revision_request(재검토 요청) · counter_restored · build_restored(다시 공개)
--    - 감독관에게 안 가는 알림·처리한 본인 제외는 알림 줄을 만들 때(notify·notify_staff) 이미 걸러진다
--      → 푸시는 "생긴 알림 줄"만 따라가므로 같은 규칙을 그대로 따른다
--    - 주소·비밀 값은 Vault에서 읽는다 (push_function_url, push_webhook_secret). 없거나 pg_net이 실패해도
--      알림 저장은 그대로 된다 (푸시만 안 감)
--
-- 하위 호환: 있던 표·함수는 바꾸지 않는다 (notifications에 트리거 하나를 더할 뿐). 지금 배포된 화면과 그대로 동작한다.
-- 순서: 이 파일 실행 → supabase/scripts/check_web_push.sql로 확인 → Edge Function·비밀 값 등록(SPEC 11-11) → 새 코드 push.
-- 036까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 기기 알림 주소
-- ---------------------------------------------------------------------
create table public.push_subscriptions (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  endpoint   text not null unique check (endpoint ~ '^https://' and length(endpoint) <= 1000),
  p256dh     text not null check (length(p256dh) between 1 and 200),
  auth       text not null check (length(auth) between 1 and 100),
  created_at timestamptz not null default now()
);
create index push_subscriptions_user on public.push_subscriptions (user_id, id);
comment on table public.push_subscriptions is
  '웹 푸시 기기 알림 주소 (037). 본인만 읽기·넣기·지우기. 알림 끄기·로그아웃·탈퇴·만료(404/410) 때 지움. 한 사람 최대 10대';

revoke all on public.push_subscriptions from anon, authenticated;
grant select, insert, delete on public.push_subscriptions to authenticated;
alter table public.push_subscriptions enable row level security;
create policy "push_subscriptions: 본인 읽기" on public.push_subscriptions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "push_subscriptions: 본인 넣기" on public.push_subscriptions
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "push_subscriptions: 본인 지우기" on public.push_subscriptions
  for delete to authenticated using (user_id = (select auth.uid()));

-- 한 사람 최대 10대: 넣기 전에 오래된 것부터 지워 9대로 맞춘다
create function public.push_subscriptions_limit()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.push_subscriptions
   where id in (
     select id from public.push_subscriptions where user_id = new.user_id
      order by id desc offset 9
   );
  return new;
end;
$$;
create trigger push_subscriptions_limit
  before insert on public.push_subscriptions
  for each row execute function public.push_subscriptions_limit();

-- ---------------------------------------------------------------------
-- 2. 알림 종류별 켜기/끄기 (줄이 없으면 둘 다 켜짐)
-- ---------------------------------------------------------------------
create table public.push_settings (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  staff_new  boolean not null default true,  -- 운영진 알림: 새 제안·새 빌드·새 문의
  my_results boolean not null default true,  -- 내 제안 결과: 승인·거절·재검토 요청·다시 공개
  updated_at timestamptz not null default now()
);
comment on table public.push_settings is '웹 푸시 알림 종류별 켜기/끄기 (037). 본인만. 줄이 없으면 둘 다 켜짐';

revoke all on public.push_settings from anon, authenticated;
grant select, insert on public.push_settings to authenticated;
grant update (user_id, staff_new, my_results, updated_at) on public.push_settings to authenticated; -- 저장(upsert)용, 행은 RLS가 막는다
alter table public.push_settings enable row level security;
create policy "push_settings: 본인 읽기" on public.push_settings
  for select to authenticated using (user_id = (select auth.uid()));
create policy "push_settings: 본인 넣기" on public.push_settings
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "push_settings: 본인 고치기" on public.push_settings
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------
-- 3. 이 알림을 이 사람에게 푸시로 보낼까 (알림 종류 + 지금 역할·운영자 모드 + 종류별 설정)
-- ---------------------------------------------------------------------
create function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored') then 'my_results'
  end;
$$;
comment on function public.push_group(text) is '푸시로 보내는 알림 종류의 묶음 (037): staff_new(운영진) / my_results(내 제안 결과) / null(푸시 안 함)';

create function public.push_wanted(p_user uuid, p_kind text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case public.push_group(p_kind)
    when 'staff_new' then
      exists (select 1 from public.profiles p
               where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
      and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
    when 'my_results' then
      coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
    else false
  end
  and exists (select 1 from public.push_subscriptions where user_id = p_user);
$$;

-- ---------------------------------------------------------------------
-- 4. 알림 줄이 생기면 Edge Function 부르기 (pg_net, 커밋된 뒤에 나간다 — 처리가 되돌려지면 안 나감)
-- ---------------------------------------------------------------------
create function public.push_on_notification()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  fn_url text;
  secret text;
begin
  if not public.push_wanted(new.user_id, new.kind) then
    return null;
  end if;
  begin
    select decrypted_secret into fn_url from vault.decrypted_secrets where name = 'push_function_url';
    select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_webhook_secret';
    if fn_url is null or secret is null then
      return null;  -- 아직 설정 전: 푸시만 안 감
    end if;
    perform net.http_post(
      url := fn_url,
      body := jsonb_build_object('notification_id', new.id),
      params := '{}'::jsonb,
      headers := jsonb_build_object('content-type', 'application/json', 'x-push-secret', secret),
      timeout_milliseconds := 5000);
  exception when others then
    raise warning '웹 푸시 요청을 넣지 못했습니다: %', sqlerrm;  -- 알림 저장은 그대로
  end;
  return null;
end;
$$;
create trigger notifications_push
  after insert on public.notifications
  for each row execute function public.push_on_notification();

-- ---------------------------------------------------------------------
-- 5. Edge Function(service_role)만 부르는 함수
--    push_targets(알림 번호): 보낼 내용과 받을 기기. 보낼 대상이 아니면(설정을 그 사이 껐거나 등) 기기 없음
--    push_forget(기기 번호들): 만료(404·410)된 기기 주소 지우기
-- ---------------------------------------------------------------------
create function public.push_targets(p_notification_id bigint)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  n public.notifications;
begin
  select * into n from public.notifications where id = p_notification_id;
  if n.id is null or n.created_at < now() - interval '1 hour' then
    return jsonb_build_object('notification', null, 'subscriptions', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'notification', jsonb_build_object('id', n.id, 'kind', n.kind, 'message', n.message,
                                       'proposal_id', n.proposal_id, 'build_id', n.build_id),
    'subscriptions', case when public.push_wanted(n.user_id, n.kind) then coalesce(
      (select jsonb_agg(jsonb_build_object('id', s.id, 'endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth) order by s.id)
         from public.push_subscriptions s where s.user_id = n.user_id), '[]'::jsonb) else '[]'::jsonb end);
end;
$$;

create function public.push_forget(p_ids bigint[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  k integer;
begin
  delete from public.push_subscriptions where id = any (p_ids);
  get diagnostics k = row_count;
  return k;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.push_subscriptions_limit() from public, anon, authenticated;
revoke execute on function public.push_on_notification() from public, anon, authenticated;
revoke execute on function public.push_wanted(uuid, text) from public, anon, authenticated;  -- 남의 설정을 묻지 못하게
revoke execute on function public.push_targets(bigint) from public, anon, authenticated;
revoke execute on function public.push_forget(bigint[]) from public, anon, authenticated;
grant execute on function public.push_targets(bigint) to service_role;
grant execute on function public.push_forget(bigint[]) to service_role;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_web_push.sql
-- Vault 비밀 값 두 개(push_function_url, push_webhook_secret)와 Edge Function web-push 설정은 SPEC 11-11
