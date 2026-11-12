-- =====================================================================
-- 047: 장인 인증 - 3단계 DB: 장인 외부 링크 + 공개 프로필 /u/:id (2026-11-12, SPEC 6-34)
--   화면 문구는 "장인", 코드/DB 이름은 influencer 그대로. 화면(링크 편집/이동 확인 창/신고/공개 프로필)은 다음 차례.
--
-- 1. 허용 사이트 표 link_domains (도메인 + 이름). 처음 9개: youtube.com, youtu.be, chzzk.naver.com, sooplive.co.kr, afreecatv.com,
--    instagram.com, twitch.tv, x.com, twitter.com. 그 도메인 자체와 하위 도메인(www., m. 등)만 받는다. 누구나 읽음(편집 화면 안내용).
--    운영자가 admin_add_link_domain(도메인, 이름) / admin_remove_link_domain(도메인, 사유)로 더하고 뺀다(처리 기록 add_link_domain/remove_link_domain).
--    도메인을 빼면 그 사이트의 링크는 지우지 않고 "숨김"(어디에도 안 보임). 다시 더하면 다시 보인다. 새로 올리거나 고칠 때는 거부.
-- 2. 링크 표 ext_links: 프로필 링크(build_id 없음, 최대 influencer_profile_links_max = 5개) + 빌드 링크(빌드마다 1개).
--    - 인증된 장인(profiles.influencer)만 올린다. 빌드 링크는 그 빌드를 처음 만든 장인(builds.author_id)만 설정/수정/삭제.
--    - 빌드 내용(wiki_snapshot/빌드 수정 기록/되돌리기/기여자)과 섞이지 않는다: builds 표를 건드리지 않는 별도 표라
--      다른 사람이 빌드를 고치거나 운영자가 되돌려도 링크는 그대로이고, 링크를 바꿔도 빌드 버전이 오르지 않는다.
--    - 주소 검사(ext_link_parse): https://만, 300자 이하, 주소에 쓰는 글자(영문/숫자/. _ ~ : / ? # @ & + , ; = % -)만,
--      띄어쓰기/한글/보이지 않는 글자/따옴표/꺾쇠/백슬래시 거부, %는 16진수 두 자리만(제어 문자 %00~%1F, %7F 거부),
--      사이트 부분에 계정 정보(@)/포트(:) 거부, 사이트 이름은 영문 소문자/숫자/하이픈 + 점(IP 주소/xn-- 거부),
--      다른 주소로 넘기는 주소 거부(사이트 이름이 l./lm./link./links./out./go./redirect./r.로 시작, 경로가 /redirect, /attribution_link,
--      /away, /out, /l 로 시작, 주소 안에 또 다른 주소(:// 또는 %3A%2F%2F)). 단축 주소 사이트(bit.ly 등)는 허용 표에 없어 막힌다.
--      youtu.be는 유튜브 영상으로만 가는 유튜브 공식 주소라 허용 표에 있다.
--    - 공개 조건(ext_link_visible): 주인이 지금 장인 + 사이트가 허용 표에 있음 + (빌드 링크면) 빌드/상대법이 공개 중이고 주인이 그 빌드 작성자.
--    - 표를 직접 읽을 수 있는 사람은 주인과 운영자(모드 켜짐)뿐. 다른 사람은 함수로 공개된 것만 받는다(public_profile, build_links).
-- 3. 공개 프로필 public_profile(id 글자): 인증된 장인만 돌려준다. 장인이 아니거나, 없는 id이거나, id 모양이 틀리면 모두 똑같이 null
--    (화면은 null이면 같은 "없는 페이지"). 돌려주는 값은 id/닉네임/장인 유형/공개 링크/최근 공개 빌드 10개(+ 공개 빌드 수)뿐.
--    이메일/라이엇 닉네임/신청 정보/레벨/경험치/역할/가입일은 넣지 않는다.
-- 4. 신고와 삭제:
--    - 링크 신고 report_link(링크, 이유, 내용): 정식 회원만(비회원/닉네임 없음 거부), 공개된 링크만, 내 링크 거부, 한 사람이 한 링크에 한 번.
--      신고 표는 게시판 신고(reports)와 따로 link_reports (지금 배포된 신고 화면이 모르는 신고 줄을 받지 않게 - 하위 호환).
--      이유: spam(광고/도박) / obscene(음란/잔혹) / malicious(악성/피싱) / not_own(본인 채널이 아님/사칭) / other(내용 필수).
--    - 새 신고 -> 운영자에게만 알림 report_received "새 신고가 들어왔습니다. (외부 링크)"(그 링크에 처리 전 신고가 처음 생길 때만, 신고자 본인 제외,
--      운영자 모드를 끄면 가림 - 045와 같은 종류라 규칙/푸시 staff_new 그대로). 감독관은 받지 않고 처리도 못 한다(설계안: 링크는 운영자만).
--    - 운영자 전용: admin_link_reports(쪽, 크기) 처리 전 신고 목록, dismiss_link_reports(링크, 메모) 기각(처리 기록 dismiss_reports),
--      remove_link(링크, 사유 필수) 삭제(처리 기록 remove_link, 메모에 지운 주소) + 올린 장인에게 link_removed 알림
--      "프로필에 올린 링크가 운영 원칙에 따라 삭제됐습니다. 사유: ..." / 빌드 링크면 "빌드에 올린 링크가 ..."(build_id 함께).
--      링크를 지우면 그 링크의 신고 줄도 함께 지워진다(처리 기록에 주소/사유가 남는다).
-- 5. 인증이 끝날 때 링크 처리 (트리거 ext_links_on_influencer_end):
--    - 인증 해제(revoke_influencer 등 profiles.influencer가 비워지는 모든 길): 그 장인의 링크(프로필/빌드)를 "바로 지운다"(숨기지 않음).
--      다시 인증되면 새로 올린다. 개인정보처리방침 "외부 링크는 회원이 지우거나 인증이 해제되면 바로 지웁니다"와 같다.
--    - 탈퇴: 프로필이 지워지며 링크/그 링크의 신고가 함께 지워진다(on delete cascade). 내가 한 링크 신고도 함께 지워진다.
--    - 닉네임 초기화/운영자 닉네임 바꾸기(admin_set_nickname)/닉네임 변경 예정: 링크는 회원 번호에 붙어 있어 그대로(인증이 유지되므로).
--    - 빌드가 지워지면 그 빌드 링크도 지워진다(cascade). 빌드/상대법이 숨겨지면 링크는 남고 안 보인다.
-- 6. 설정값 influencer_profile_links_max = 5 (xp_rules, 설정값 1개 늘어남). 새 알림 종류 없음(link_removed는 046, report_received는 045).
--
-- 만들지 않는 것: 처리 대기 건수(admin_pending_counts)의 링크 신고 키(화면 단계에서 필요하면 admin_link_reports의 total을 쓴다), pg_cron 일정(필요 없음).
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 047이 만든 것만 지우고 046 상태로 돌아간다.
--    (올린 링크/링크 신고/링크 처리 기록은 함께 지워진다. 이미 보낸 link_removed/report_received 알림은 046 종류라 그대로 남는다.)
--     begin;
--     drop trigger if exists ext_links_on_influencer_end on public.profiles;
--     drop trigger if exists link_reports_notify_staff on public.link_reports;
--     drop function if exists public.ext_links_on_influencer_end();
--     drop function if exists public.notify_staff_new_link_report();
--     drop function if exists public.set_profile_links(text[]);
--     drop function if exists public.set_build_link(bigint, text);
--     drop function if exists public.my_links();
--     drop function if exists public.public_profile(text);
--     drop function if exists public.build_links(bigint);
--     drop function if exists public.report_link(bigint, text, text);
--     drop function if exists public.admin_link_reports(integer, integer);
--     drop function if exists public.admin_link_reports_unchecked(integer, integer);
--     drop function if exists public.dismiss_link_reports(bigint, text);
--     drop function if exists public.dismiss_link_reports_unchecked(bigint, text);
--     drop function if exists public.remove_link(bigint, text);
--     drop function if exists public.remove_link_unchecked(bigint, text);
--     drop function if exists public.admin_add_link_domain(text, text);
--     drop function if exists public.admin_add_link_domain_unchecked(text, text);
--     drop function if exists public.admin_remove_link_domain(text, text);
--     drop function if exists public.admin_remove_link_domain_unchecked(text, text);
--     drop function if exists public.ext_link_visible(bigint);
--     drop function if exists public.ext_link_parse(text);
--     drop function if exists public.ext_link_json(bigint);
--     drop table if exists public.link_reports;
--     drop table if exists public.ext_links;
--     drop table if exists public.link_domains;
--     delete from public.moderation_log
--      where action in ('remove_link', 'add_link_domain', 'remove_link_domain') or target_kind in ('link', 'link_domain');
--     alter table public.moderation_log drop constraint moderation_log_action_check;
--     alter table public.moderation_log add constraint moderation_log_action_check check (action = any (array[
--       'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
--       'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report', 'dismiss_report',
--       'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member']));
--     alter table public.moderation_log drop constraint moderation_log_target_kind_check;
--     alter table public.moderation_log add constraint moderation_log_target_kind_check check (target_kind = any (array[
--       'post', 'comment', 'doc_comment', 'proposal', 'user', 'inquiry', 'build', 'wiki_report', 'influencer_application']));
--     delete from public.xp_rules where key = 'influencer_profile_links_max';
--     commit;
--   되돌린 뒤 다시 047을 실행해도 된다(처음부터 다시 만든다).
--
-- 하위 호환: 있던 표/함수의 이름/인자/반환은 그대로. 새 표 3개/새 함수/트리거만 더하고, 처리 기록 종류 제약만 같은 모양으로 다시 만든다.
--   지금 배포된 화면과 그대로 동작한다(링크를 올리는 화면이 아직 없으니 링크/링크 신고도 생기지 않는다). Edge Function 재배포 필요 없음.
-- 순서: check_external_links.sql(실행 전) -> 이 파일 실행 -> check_external_links.sql(실행 후).
-- 046까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.influencer_applications') is null then
    raise exception '046이 아직 실행되지 않았습니다. 046_influencer.sql을 먼저 실행해 주세요.';
  end if;
  if to_regclass('public.ext_links') is not null then
    raise exception '047을 이미 실행했습니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 0. 설정값
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('influencer_profile_links_max', 5, '장인 외부 링크: 프로필에 올릴 수 있는 링크 수 (빌드 링크는 빌드마다 1개, 047)')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 1. 허용 사이트 표
-- ---------------------------------------------------------------------
create table public.link_domains (
  domain      text primary key
              check (char_length(domain) <= 100
                     and domain ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$'
                     and domain !~ '(^|\.)xn--'),
  label       text not null check (char_length(btrim(label)) between 1 and 40),
  created_at  timestamptz not null default now()
);
comment on table public.link_domains is
  '장인 외부 링크 허용 사이트 (047). 도메인 자체와 하위 도메인만 받는다. 누구나 읽음, 쓰기는 운영자 함수(admin_add_link_domain/admin_remove_link_domain)로만';
insert into public.link_domains (domain, label) values
  ('youtube.com', '유튜브'),
  ('youtu.be', '유튜브 (짧은 주소)'),
  ('chzzk.naver.com', '치지직'),
  ('sooplive.co.kr', '숲'),
  ('afreecatv.com', '아프리카TV (숲 예전 주소)'),
  ('instagram.com', '인스타그램'),
  ('twitch.tv', '트위치'),
  ('x.com', 'X'),
  ('twitter.com', 'X (트위터 예전 주소)');
alter table public.link_domains enable row level security;
revoke all on public.link_domains from anon, authenticated;
grant select on public.link_domains to anon, authenticated;
create policy "link_domains: 누구나 읽기" on public.link_domains for select using (true);

-- ---------------------------------------------------------------------
-- 2. 링크 표
-- ---------------------------------------------------------------------
create table public.ext_links (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  build_id    bigint references public.builds (id) on delete cascade,  -- null = 프로필 링크
  url         text not null check (char_length(url) between 12 and 300 and url like 'https://%'),
  host        text not null,
  sort        smallint not null default 0 check (sort between 0 and 99),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index ext_links_one_per_build on public.ext_links (build_id) where build_id is not null;
create unique index ext_links_profile_url on public.ext_links (owner_id, url) where build_id is null;
create index ext_links_owner on public.ext_links (owner_id, sort);
comment on table public.ext_links is
  '장인 외부 링크 (047). build_id가 없으면 프로필 링크(최대 influencer_profile_links_max), 있으면 그 빌드 링크(1개, 빌드를 처음 만든 장인만). '
  '빌드 내용(wiki_snapshot)과 별개. 직접 읽기는 주인/운영자만, 공개는 public_profile/build_links 함수로. 쓰기는 함수로만';
alter table public.ext_links enable row level security;
revoke all on public.ext_links from anon, authenticated;
grant select on public.ext_links to authenticated;
create policy "ext_links: 주인과 운영자 읽기" on public.ext_links
  for select to authenticated using (owner_id = (select auth.uid()) or public.is_admin());

-- ---------------------------------------------------------------------
-- 3. 링크 신고 표 (게시판 신고 reports와 따로 - 지금 신고 화면이 모르는 줄을 받지 않게)
-- ---------------------------------------------------------------------
create table public.link_reports (
  id            bigint generated always as identity primary key,
  link_id       bigint not null references public.ext_links (id) on delete cascade,
  reporter_id   uuid not null references public.profiles (id) on delete cascade,
  reason        text not null check (reason in ('spam', 'obscene', 'malicious', 'not_own', 'other')),
  detail        text check (detail is null or char_length(detail) <= 500),
  status        text not null default 'open' check (status in ('open', 'dismissed')),
  handled_by    uuid references public.profiles (id) on delete set null,
  handled_at    timestamptz,
  handled_note  text,
  created_at    timestamptz not null default now(),
  check (reason <> 'other' or coalesce(btrim(detail), '') <> '')
);
create unique index link_reports_once on public.link_reports (reporter_id, link_id);
create index link_reports_open on public.link_reports (created_at) where status = 'open';
create index link_reports_link on public.link_reports (link_id);
comment on table public.link_reports is
  '장인 외부 링크 신고 (047). 정식 회원만 신고, 운영자만 읽고 처리(감독관 제외). 링크를 지우면 신고 줄도 함께 지워진다(처리 기록에 남음)';
alter table public.link_reports enable row level security;
revoke all on public.link_reports from anon, authenticated;
grant select on public.link_reports to authenticated;
create policy "link_reports: 운영자 읽기" on public.link_reports for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- 4. 처리 기록 종류 (046 목록 + 047)
-- ---------------------------------------------------------------------
alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action = any (array[
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report', 'dismiss_report',
  'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
  'remove_link', 'add_link_domain', 'remove_link_domain'  -- 047
]));
alter table public.moderation_log drop constraint moderation_log_target_kind_check;
alter table public.moderation_log add constraint moderation_log_target_kind_check check (target_kind = any (array[
  'post', 'comment', 'doc_comment', 'proposal', 'user', 'inquiry', 'build', 'wiki_report',
  'influencer_application',
  'link', 'link_domain'  -- 047
]));

-- ---------------------------------------------------------------------
-- 5. 주소 검사 / 공개 조건 / json 모양
-- ---------------------------------------------------------------------
-- 돌려주는 값: array[정리한 주소, 사이트 이름(host)]. 안 되는 주소는 이유와 함께 거부 (22023 모양 / 23514 규칙)
create function public.ext_link_parse(p_url text)
returns text[] language plpgsql stable security definer set search_path = ''
as $$
declare
  u text := btrim(coalesce(p_url, ''));
  rest text;
  authority text;
  tail text;
  h text;
begin
  if u = '' then
    raise exception '링크 주소를 적어 주세요.' using errcode = '22023';
  end if;
  if char_length(u) > 300 then
    raise exception '링크 주소는 300자 이하로 적어 주세요.' using errcode = '22023';
  end if;
  if u !~* '^https://' then
    raise exception 'https://로 시작하는 주소만 올릴 수 있습니다.' using errcode = '22023';
  end if;
  -- 주소에 쓰는 글자만 (띄어쓰기/한글/보이지 않는 글자/따옴표/꺾쇠/괄호/백슬래시 등은 거부)
  if u !~ '^[A-Za-z0-9._~:/?#@&+,;=%-]+$' then
    raise exception '주소에 쓸 수 없는 글자가 들어 있습니다. 브라우저 주소창의 주소를 그대로 복사해 주세요.' using errcode = '22023';
  end if;
  -- %는 16진수 두 자리만, 제어 문자(%00~%1F, %7F)는 거부
  if strpos(pg_catalog.regexp_replace(u, '%[0-9A-Fa-f]{2}', '', 'g'), '%') > 0 or u ~* '%(0[0-9a-f]|1[0-9a-f]|7f)' then
    raise exception '주소에 쓸 수 없는 글자가 들어 있습니다. 브라우저 주소창의 주소를 그대로 복사해 주세요.' using errcode = '22023';
  end if;
  rest := substr(u, 9);
  authority := substring(rest from '^[^/?#]*');
  tail := substr(rest, char_length(authority) + 1);
  if strpos(authority, '@') > 0 then
    raise exception '주소에 계정 정보(@ 앞부분)를 넣을 수 없습니다.' using errcode = '22023';
  end if;
  if strpos(authority, ':') > 0 then
    raise exception '포트 번호가 붙은 주소는 올릴 수 없습니다.' using errcode = '22023';
  end if;
  h := lower(authority);
  if h !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$' or h ~ '(^|\.)xn--' then
    raise exception '주소의 사이트 이름이 올바르지 않습니다.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.link_domains d where h = d.domain or right(h, char_length(d.domain) + 1) = '.' || d.domain) then
    raise exception '허용된 사이트의 주소만 올릴 수 있습니다. (%)',
      (select string_agg(d.domain, ', ' order by d.domain) from public.link_domains d) using errcode = '23514';
  end if;
  -- 다른 주소로 넘겨주는 주소 (단축/우회): 넘기기 전용 하위 사이트, 넘기기 경로, 주소 안의 또 다른 주소
  if h ~ '^(l|lm|link|links|out|go|redirect|r)\.'
     or lower(tail) ~ '^/(redirect|attribution_link|away|out|l)([/?#]|$)'
     or lower(tail) ~ '(://|%3a%2f%2f|%3a/%2f|:%2f%2f|%3a//)' then
    raise exception '다른 주소로 넘겨주는 주소(단축/우회 주소)는 올릴 수 없습니다. 채널이나 영상의 원래 주소를 올려 주세요.' using errcode = '23514';
  end if;
  return array['https://' || h || tail, h];
end;
$$;

-- 이 링크가 지금 누구에게나 보이는가
create function public.ext_link_visible(p_link bigint)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
      from public.ext_links l
      join public.profiles o on o.id = l.owner_id and o.influencer is not null
     where l.id = p_link
       and exists (select 1 from public.link_domains d where l.host = d.domain or right(l.host, char_length(d.domain) + 1) = '.' || d.domain)
       and (l.build_id is null or exists (
             select 1 from public.builds b join public.counters c on c.id = b.counter_id
              where b.id = l.build_id and b.author_id = l.owner_id and b.status = 'approved' and c.status = 'approved')));
$$;

-- 화면에 주는 링크 한 줄
create function public.ext_link_json(p_link bigint)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('id', l.id, 'url', l.url, 'host', l.host, 'build_id', l.build_id, 'sort', l.sort)
    from public.ext_links l where l.id = p_link;
$$;

-- ---------------------------------------------------------------------
-- 6. 장인 본인: 링크 올리기/고치기/지우기
-- ---------------------------------------------------------------------
-- 프로필 링크 전체를 이 목록(순서대로)으로 맞춘다. 빈 목록이면 모두 지운다. 그대로 둔 주소는 같은 줄(신고 기록 유지), 새 주소만 새 줄.
create function public.set_profile_links(p_urls text[])
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
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
$$;

-- 빌드 링크 1개를 정한다(빈 주소면 지운다). 그 빌드를 처음 만든 장인만. 빌드 내용/버전/수정 기록은 건드리지 않는다.
-- 주소가 바뀌면 새 링크로 본다(예전 주소의 신고는 함께 지워진다 - 그 주소는 더 이상 보이지 않으므로).
create function public.set_build_link(p_build bigint, p_url text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
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
$$;

-- 내 링크 (편집 화면용): 프로필 링크, 빌드 링크, 한도, 허용 사이트. visible = 지금 다른 사람에게 보이는가(사이트가 빠졌거나 빌드가 숨겨지면 false)
create function public.my_links()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'influencer', (select p.influencer from public.profiles p where p.id = (select auth.uid())),
    'max', coalesce(public.xp_rule('influencer_profile_links_max'), 5),
    'profile', coalesce((select jsonb_agg(public.ext_link_json(l.id) || jsonb_build_object('visible', public.ext_link_visible(l.id)) order by l.sort)
                           from public.ext_links l where l.owner_id = (select auth.uid()) and l.build_id is null), '[]'::jsonb),
    'builds', coalesce((select jsonb_agg(public.ext_link_json(l.id) || jsonb_build_object('visible', public.ext_link_visible(l.id),
                                 'counter_id', b.counter_id, 'seq', b.seq, 'name', b.name,
                                 'target_champion', c.target_champion, 'counter_champion', c.counter_champion) order by l.created_at desc)
                          from public.ext_links l join public.builds b on b.id = l.build_id join public.counters c on c.id = b.counter_id
                         where l.owner_id = (select auth.uid())), '[]'::jsonb),
    'domains', coalesce((select jsonb_agg(jsonb_build_object('domain', d.domain, 'label', d.label) order by d.domain)
                           from public.link_domains d), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------
-- 7. 누구나: 공개 프로필 / 상대법의 빌드 링크
-- ---------------------------------------------------------------------
-- 인증된 장인만. 장인이 아님/없는 id/id 모양이 틀림은 모두 똑같이 null (화면은 같은 "없는 페이지").
create function public.public_profile(p_user text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  uid uuid;
  p public.profiles%rowtype;
begin
  if p_user is null or p_user !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  uid := p_user::uuid;
  select * into p from public.profiles where id = uid and influencer is not null and nickname is not null;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', p.id,
    'nickname', p.nickname,
    'influencer', p.influencer,
    'links', coalesce((select jsonb_agg(public.ext_link_json(l.id) order by l.sort)
                         from public.ext_links l where l.owner_id = p.id and l.build_id is null and public.ext_link_visible(l.id)), '[]'::jsonb),
    'build_count', (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                     where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'),
    'builds', coalesce((select jsonb_agg(x.j order by x.created_at desc, x.id desc) from (
                select b.id, b.created_at, jsonb_build_object(
                         'id', b.id, 'counter_id', b.counter_id, 'seq', b.seq, 'name', b.name, 'patch', b.patch,
                         'target_champion', c.target_champion, 'counter_champion', c.counter_champion,
                         'created_at', b.created_at,
                         'link', (select public.ext_link_json(l.id) from public.ext_links l
                                   where l.build_id = b.id and public.ext_link_visible(l.id))) as j
                  from public.builds b join public.counters c on c.id = b.counter_id
                 where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'
                 order by b.created_at desc, b.id desc
                 limit 10) x), '[]'::jsonb));
end;
$$;

-- 상대법의 공개 빌드 링크 {"빌드 id": {id, url, host, build_id, sort}} - 빌드 카드용 (누구나)
create function public.build_links(p_counter bigint)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_object_agg(l.build_id::text, public.ext_link_json(l.id)), '{}'::jsonb)
    from public.ext_links l join public.builds b on b.id = l.build_id
   where b.counter_id = p_counter and public.ext_link_visible(l.id);
$$;

-- ---------------------------------------------------------------------
-- 8. 링크 신고 (정식 회원) -> 운영자 알림
-- ---------------------------------------------------------------------
create function public.report_link(p_link bigint, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
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
$$;

-- 새 링크 신고 -> 운영자에게만 report_received (그 링크에 처리 전 신고가 처음 생길 때만, 신고자 본인 제외)
create function public.notify_staff_new_link_report()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.status <> 'open' then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtext('report_received:link:' || new.link_id));
  if exists (select 1 from public.link_reports r where r.status = 'open' and r.id <> new.id and r.link_id = new.link_id) then
    return null;
  end if;
  insert into public.notifications (user_id, kind, message)
  select u.id, 'report_received', '새 신고가 들어왔습니다. (외부 링크)'
    from public.profiles u
   where u.role = 'admin' and u.id is distinct from new.reporter_id;
  return null;
end;
$$;
create trigger link_reports_notify_staff
  after insert on public.link_reports
  for each row execute function public.notify_staff_new_link_report();

-- ---------------------------------------------------------------------
-- 9. 운영자 전용: 신고 목록 / 기각 / 링크 삭제 / 허용 사이트
-- ---------------------------------------------------------------------
-- 처리 전 신고가 있는 링크 (오래된 신고 먼저). { total, page, size, links: [{ link, owner, visible, build, reports: [...] }] }
create function public.admin_link_reports_unchecked(p_page integer, p_size integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  sz integer := least(greatest(coalesce(p_size, 20), 1), 100);
  pg integer := greatest(coalesce(p_page, 1), 1);
begin
  return jsonb_build_object(
    'total', (select count(distinct r.link_id) from public.link_reports r where r.status = 'open'),
    'page', pg, 'size', sz,
    'links', coalesce((select jsonb_agg(x.j order by x.first_at, x.link_id) from (
      select g.link_id, g.first_at, public.ext_link_json(l.id) || jsonb_build_object(
               'visible', public.ext_link_visible(l.id),
               'owner', jsonb_build_object('id', o.id, 'nickname', o.nickname, 'influencer', o.influencer, 'nickname_state', o.nickname_state),
               'build', case when l.build_id is null then null else (
                          select jsonb_build_object('id', b.id, 'counter_id', b.counter_id, 'seq', b.seq, 'name', b.name, 'status', b.status,
                                                    'target_champion', c.target_champion, 'counter_champion', c.counter_champion)
                            from public.builds b join public.counters c on c.id = b.counter_id where b.id = l.build_id) end,
               'reports', (select jsonb_agg(jsonb_build_object(
                                    'id', r.id, 'reason', r.reason, 'detail', r.detail, 'created_at', r.created_at,
                                    'reporter', jsonb_build_object('id', u.id, 'nickname', u.nickname, 'influencer', u.influencer,
                                                                   'nickname_state', u.nickname_state, 'role', u.role))
                                  order by r.created_at)
                             from public.link_reports r left join public.profiles u on u.id = r.reporter_id
                            where r.link_id = l.id and r.status = 'open')) as j
        from (select r.link_id, min(r.created_at) as first_at from public.link_reports r where r.status = 'open'
               group by r.link_id order by min(r.created_at), r.link_id limit sz offset (pg - 1) * sz) g
        join public.ext_links l on l.id = g.link_id
        join public.profiles o on o.id = l.owner_id) x), '[]'::jsonb));
end;
$$;

create function public.admin_link_reports(p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_link_reports_unchecked(p_page, p_size);
end;
$$;

-- 신고 기각 (링크는 그대로). 돌려주는 값: 기각한 신고 수
create function public.dismiss_link_reports_unchecked(p_link bigint, p_note text)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  note text := nullif(btrim(coalesce(p_note, '')), '');
  n integer;
  l public.ext_links%rowtype;
begin
  if char_length(note) > 500 then
    raise exception '메모는 500자 이하로 적어 주세요.' using errcode = '22023';
  end if;
  select * into l from public.ext_links where id = p_link;
  if not found then
    raise exception '링크를 찾지 못했습니다. 이미 지워졌을 수 있습니다.' using errcode = 'P0002';
  end if;
  update public.link_reports set status = 'dismissed', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
   where link_id = p_link and status = 'open';
  get diagnostics n = row_count;
  if n = 0 then
    raise exception '처리할 신고가 없습니다.' using errcode = 'P0002';
  end if;
  perform public.log_moderation('dismiss_reports', 'link', p_link::text,
    concat_ws(E' \u00B7 ', l.url, note), (select nickname from public.profiles where id = l.owner_id));
  return n;
end;
$$;

create function public.dismiss_link_reports(p_link bigint, p_note text default null)
returns integer language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.dismiss_link_reports_unchecked(p_link, p_note);
end;
$$;

-- 링크 삭제 (사유 필수) + 올린 장인에게 link_removed 알림. 신고 줄은 함께 지워진다(처리 기록에 주소/사유가 남는다)
create function public.remove_link_unchecked(p_link bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text := nullif(btrim(coalesce(p_note, '')), '');
  l public.ext_links%rowtype;
  nick text;
  n_reports integer;
begin
  if note is null or char_length(note) > 500 then
    raise exception '삭제 사유를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into l from public.ext_links where id = p_link for update;
  if not found then
    raise exception '링크를 찾지 못했습니다. 이미 지워졌을 수 있습니다.' using errcode = 'P0002';
  end if;
  select nickname into nick from public.profiles where id = l.owner_id;
  select count(*) into n_reports from public.link_reports where link_id = l.id and status = 'open';
  delete from public.ext_links where id = l.id;
  perform public.notify(l.owner_id, 'link_removed',
    format('%s 올린 링크가 운영 원칙에 따라 삭제됐습니다. 사유: %s', case when l.build_id is null then '프로필에' else '빌드에' end, note),
    null, l.build_id);
  perform public.log_moderation('remove_link', 'link', l.id::text,
    concat_ws(E' \u00B7 ', l.url, case when l.build_id is not null then format('빌드 %s', l.build_id) end,
              case when n_reports > 0 then format('처리 전 신고 %s건', n_reports) end, note), nick);
end;
$$;

create function public.remove_link(p_link bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.remove_link_unchecked(p_link, p_note);
end;
$$;

-- 허용 사이트 더하기 (도메인은 소문자, https:// / www. / 끝의 / 는 떼어 낸다)
create function public.admin_add_link_domain_unchecked(p_domain text, p_label text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  dom text := lower(btrim(coalesce(p_domain, '')));
  lab text := nullif(btrim(coalesce(p_label, '')), '');
begin
  dom := pg_catalog.regexp_replace(dom, '^https?://', '');
  dom := pg_catalog.regexp_replace(dom, '/+$', '');
  dom := pg_catalog.regexp_replace(dom, '^www\.', '');
  if lab is null or char_length(lab) > 40 then
    raise exception '사이트 이름을 적어 주세요. (40자 이하)' using errcode = '22023';
  end if;
  if char_length(dom) > 100 or dom !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$' or dom ~ '(^|\.)xn--' then
    raise exception '도메인 모양이 올바르지 않습니다. (예: youtube.com)' using errcode = '22023';
  end if;
  insert into public.link_domains (domain, label) values (dom, lab);
  perform public.log_moderation('add_link_domain', 'link_domain', dom, lab, null);
  return dom;
exception when unique_violation then
  raise exception '이미 허용된 사이트입니다.' using errcode = '23505';
end;
$$;

create function public.admin_add_link_domain(p_domain text, p_label text)
returns text language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_add_link_domain_unchecked(p_domain, p_label);
end;
$$;

-- 허용 사이트 빼기 (사유 필수). 그 사이트의 링크는 지우지 않고 숨김(다시 더하면 다시 보임). 돌려주는 값: 숨겨지는 링크 수
create function public.admin_remove_link_domain_unchecked(p_domain text, p_note text)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  dom text := lower(btrim(coalesce(p_domain, '')));
  note text := nullif(btrim(coalesce(p_note, '')), '');
  before_n integer;
  after_n integer;
begin
  if note is null or char_length(note) > 500 then
    raise exception '빼는 사유를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  if not exists (select 1 from public.link_domains where domain = dom) then
    raise exception '허용 목록에 없는 사이트입니다.' using errcode = 'P0002';
  end if;
  select count(*) into before_n from public.ext_links l where public.ext_link_visible(l.id);
  delete from public.link_domains where domain = dom;
  select count(*) into after_n from public.ext_links l where public.ext_link_visible(l.id);
  perform public.log_moderation('remove_link_domain', 'link_domain', dom,
    concat_ws(E' \u00B7 ', note, case when before_n > after_n then format('숨겨진 링크 %s개', before_n - after_n) end), null);
  return before_n - after_n;
end;
$$;

create function public.admin_remove_link_domain(p_domain text, p_note text)
returns integer language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_remove_link_domain_unchecked(p_domain, p_note);
end;
$$;

-- ---------------------------------------------------------------------
-- 10. 인증이 끝나면 링크를 지운다 (해제 등 profiles.influencer가 비워지는 모든 길. 탈퇴는 cascade)
-- ---------------------------------------------------------------------
create function public.ext_links_on_influencer_end()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.ext_links where owner_id = new.id;
  return null;
end;
$$;
create trigger ext_links_on_influencer_end
  after update of influencer on public.profiles
  for each row when (old.influencer is not null and new.influencer is null)
  execute function public.ext_links_on_influencer_end();

-- ---------------------------------------------------------------------
-- 11. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.ext_link_parse(text) from public, anon, authenticated;
revoke execute on function public.ext_link_visible(bigint) from public, anon, authenticated;
revoke execute on function public.ext_link_json(bigint) from public, anon, authenticated;
revoke execute on function public.notify_staff_new_link_report() from public, anon, authenticated;
revoke execute on function public.ext_links_on_influencer_end() from public, anon, authenticated;
revoke execute on function public.admin_link_reports_unchecked(integer, integer) from public, anon, authenticated;
revoke execute on function public.dismiss_link_reports_unchecked(bigint, text) from public, anon, authenticated;
revoke execute on function public.remove_link_unchecked(bigint, text) from public, anon, authenticated;
revoke execute on function public.admin_add_link_domain_unchecked(text, text) from public, anon, authenticated;
revoke execute on function public.admin_remove_link_domain_unchecked(text, text) from public, anon, authenticated;

revoke execute on function public.set_profile_links(text[]) from public, anon;
revoke execute on function public.set_build_link(bigint, text) from public, anon;
revoke execute on function public.my_links() from public, anon;
revoke execute on function public.report_link(bigint, text, text) from public, anon;
revoke execute on function public.admin_link_reports(integer, integer) from public, anon;
revoke execute on function public.dismiss_link_reports(bigint, text) from public, anon;
revoke execute on function public.remove_link(bigint, text) from public, anon;
revoke execute on function public.admin_add_link_domain(text, text) from public, anon;
revoke execute on function public.admin_remove_link_domain(text, text) from public, anon;
revoke execute on function public.public_profile(text) from public;
revoke execute on function public.build_links(bigint) from public;
grant execute on function public.set_profile_links(text[]) to authenticated;  -- 장인인지는 함수 안에서
grant execute on function public.set_build_link(bigint, text) to authenticated;
grant execute on function public.my_links() to authenticated;
grant execute on function public.report_link(bigint, text, text) to authenticated;  -- 정식 회원인지는 함수 안에서
grant execute on function public.admin_link_reports(integer, integer) to authenticated;  -- 운영자인지는 함수 안에서
grant execute on function public.dismiss_link_reports(bigint, text) to authenticated;
grant execute on function public.remove_link(bigint, text) to authenticated;
grant execute on function public.admin_add_link_domain(text, text) to authenticated;
grant execute on function public.admin_remove_link_domain(text, text) to authenticated;
grant execute on function public.public_profile(text) to anon, authenticated;
grant execute on function public.build_links(bigint) to anon, authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_external_links.sql
