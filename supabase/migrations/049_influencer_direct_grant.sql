-- =====================================================================
-- 049: 운영자가 장인을 직접 지정 (2026-11-12, SPEC 6-35)
--
-- 운영자가 신청/확인 절차 없이 정식 회원을 바로 장인으로 지정한다. grant_influencer(회원, 유형, 메모).
--   - 운영자만 (감독관 거부). 운영자 모드가 꺼져 있으면 거부 (require_operator - 046과 같음).
--   - 대상: 정식 회원(구글/카카오)만. 비회원(게스트), 운영자 계정, 닉네임을 아직 안 정한 회원, 이미 장인인 회원,
--     신청이 처리 전인 회원(심사 화면에서 승인하라고 안내), 닉네임 변경 예정인 회원은 거부.
--     같은(비슷한) 닉네임으로 다른 사람이 신청 중이면 거부 (그 신청을 먼저 처리 - 나중에 승인이 막히지 않게).
--   - 입력: 회원, 유형(creator / pro / grandmaster), 메모(필수, 500자 이하). 공식 이메일/라이엇 닉네임/채널 링크는 받지 않는다.
--   - 닉네임은 바꾸지 않는다.
--
-- 설계 - 신청으로 승인된 장인과 똑같이 동작하게:
--   1) 신청 표 influencer_applications에 "처음부터 승인된" 줄을 하나 만든다 (새 칸 direct = true).
--      희망 닉네임 = 지금 닉네임, 신청 전 닉네임 없음, 이메일/라이엇/채널/op.gg 칸은 모두 비움, 만료일/끝난 때 = 지금,
--      심사한 운영자 = 지정한 운영자, 심사 메모 = 지정 메모.
--      표 검사 influencer_applications_fields를 "direct면 개인정보/링크 칸이 모두 비어 있고 처리 전이 아님"으로 넓힌다
--      (direct가 아닌 줄의 검사는 046과 같다).
--   2) 프로필은 승인 때와 같게: profiles.influencer = 유형, influencer_at = 지금 (nickname_state는 원래 비어 있음).
--   그래서 그대로 동작하는 것:
--     - 인증 해제 revoke_influencer: 프로필을 비우고 승인된 줄을 revoked로 (046 그대로) -> 링크 삭제 트리거(047) 그대로
--     - 사람당 승인 1건(부분 unique 인덱스), 다시 신청 막기("이미 인증된 장인입니다."), 내 장인 상태(인증된 장인)
--     - 장인 빌드 라벨/공개 프로필/링크 올리기/닉네임 직접 변경 금지: 모두 profiles.influencer만 본다
--     - 하루 작업 influencer_daily: 처리 전 줄만 만료시키고, 해제된 지 1년 지난 줄만 정리 -> 지정 줄도 같은 규칙
--     - 처리 대기 건수: 처리 전 줄만 센다 -> 지정 줄은 안 셈
--   3) 운영자 신청 목록(admin_influencer_applications)의 "끝난 신청"에 지정 줄도 나오고, 각 줄에 'direct'(true/false)를 더한다.
--   4) 처리 기록: 새 종류 grant_influencer (대상 user = 회원 번호, 메모 "유형 / 지정 메모"). 회원 정보의 처리 이력에 보인다.
--   5) 알림: 기존 influencer_approved를 그대로 보낸다 (문장도 같음). 새 알림 종류 없음 -> Edge Function 재배포 필요 없음.
--   새 설정값 없음. 새 표 없음. pg_cron 변경 없음.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다.
--    지정으로 생긴 신청 줄만 지운다. 이미 지정된 회원의 "장인" 표시는 그대로 남는다
--    (없애려면 되돌리기 전에 회원 정보에서 [인증 해제]). 처리 기록/알림은 남는다 (처리 기록 종류 grant_influencer도 남겨 둔다).
--    신청 목록 함수는 049 모양 그대로 둬도 된다 ('direct' 칸이 없으면 false로 나온다).
--     begin;
--     drop function if exists public.grant_influencer(uuid, text, text);
--     drop function if exists public.grant_influencer_unchecked(uuid, text, text);
--     delete from public.influencer_applications where direct;
--     alter table public.influencer_applications drop constraint influencer_applications_fields;
--     alter table public.influencer_applications add constraint influencer_applications_fields check (
--       case when kind in ('creator', 'pro')
--            then channel_url is not null and channel_key is not null and riot_id is null and riot_key is null and opgg_url is null
--                 and (status <> 'pending' or official_email is not null)
--            else official_email is null and channel_url is null and channel_key is null and opgg_url is not null
--                 and (status <> 'pending' or (riot_id is not null and riot_key is not null))
--       end);
--     alter table public.influencer_applications drop column direct;
--     commit;
--
-- 하위 호환: 있던 함수의 이름/인자는 그대로. 신청 목록 json에 키 'direct' 하나가 늘 뿐이라 지금 화면도 그대로 동작한다.
-- 순서: check_direct_grant.sql(실행 전) -> 이 파일 실행 -> check_direct_grant.sql(실행 후).
-- 048까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.ext_links') is null
     or not exists (select 1 from pg_proc where oid = 'public.remove_link(bigint, text)'::regprocedure and prosrc like '%moderatable_author%') then
    raise exception '048이 아직 실행되지 않았습니다. 046, 047, 048을 먼저 실행해 주세요.';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'influencer_applications' and column_name = 'direct') then
    raise exception '049를 이미 실행했습니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 신청 표: 직접 지정 줄 (direct)
-- ---------------------------------------------------------------------
alter table public.influencer_applications add column direct boolean not null default false;
comment on column public.influencer_applications.direct is
  '운영자가 신청 없이 직접 지정한 장인 (049). 처음부터 approved, 이메일/라이엇/채널/op.gg 칸 없음';

alter table public.influencer_applications drop constraint influencer_applications_fields;
alter table public.influencer_applications add constraint influencer_applications_fields check (
  case when direct
       then status <> 'pending' and channel_url is null and channel_key is null and official_email is null
            and riot_id is null and riot_key is null and opgg_url is null
       when kind in ('creator', 'pro')
       then channel_url is not null and channel_key is not null and riot_id is null and riot_key is null and opgg_url is null
            and (status <> 'pending' or official_email is not null)
       else official_email is null and channel_url is null and channel_key is null and opgg_url is not null
            and (status <> 'pending' or (riot_id is not null and riot_key is not null))
  end);

-- ---------------------------------------------------------------------
-- 2. 처리 기록 종류: grant_influencer (047 목록 + 1)
-- ---------------------------------------------------------------------
alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action = any (array[
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report', 'dismiss_report',
  'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
  'remove_link', 'add_link_domain', 'remove_link_domain',
  'grant_influencer'  -- 049
]));

-- ---------------------------------------------------------------------
-- 3. 직접 지정
-- ---------------------------------------------------------------------
create function public.grant_influencer_unchecked(p_user uuid, p_kind text, p_note text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  u public.profiles;
  note text := nullif(btrim(coalesce(p_note, '')), '');
  aid bigint;
begin
  if p_kind is null or p_kind not in ('creator', 'pro', 'grandmaster') then
    raise exception '유형을 골라 주세요.' using errcode = '22023';
  end if;
  if note is null or char_length(note) > 500 then
    raise exception '지정 메모를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into u from public.profiles where id = p_user for update;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if coalesce(u.is_guest, false) then
    raise exception E'장인은 구글\u00B7카카오로 로그인한 정식 회원만 지정할 수 있습니다. 비회원은 지정할 수 없습니다.' using errcode = '23514';
  end if;
  if u.role = 'admin' then
    raise exception '운영자 계정은 장인으로 지정할 수 없습니다.' using errcode = '23514';
  end if;
  if u.nickname is null then
    raise exception '닉네임을 아직 정하지 않은 회원은 장인으로 지정할 수 없습니다.' using errcode = '23514';
  end if;
  if u.influencer is not null then
    raise exception '이미 인증된 장인입니다.' using errcode = '23514';
  end if;
  if u.nickname_state = 'pending'
     or exists (select 1 from public.influencer_applications a where a.user_id = u.id and a.status = 'pending') then
    raise exception '장인 인증 신청을 심사 중인 회원입니다. 운영자 페이지 [장인 인증] 심사 화면에서 그 신청을 승인해 주세요.' using errcode = '23514';
  end if;
  if u.nickname_state = 'yielding' then
    raise exception '닉네임이 바뀔 예정인 회원입니다(장인과 같은 닉네임). 새 닉네임을 정한 뒤 지정해 주세요.' using errcode = '23514';
  end if;
  -- 같은(비슷한) 닉네임으로 다른 사람이 신청 중이면 거부 (지정 뒤에는 그 신청을 승인할 수 없게 되므로 먼저 처리)
  perform pg_advisory_xact_lock(hashtext('nickname_key:' || u.nickname_key));
  if exists (select 1 from public.profiles o where o.nickname_key = u.nickname_key and o.id <> u.id) then
    raise exception '같은(비슷한) 닉네임으로 장인 인증을 신청 중인 회원이 있습니다. 심사 화면에서 그 신청을 먼저 처리해 주세요.' using errcode = '23505';
  end if;

  insert into public.influencer_applications
    (user_id, kind, nickname, old_nickname, status, expires_at, ended_at, reviewed_by, review_note, direct)
  values (u.id, p_kind, u.nickname, null, 'approved', now(), now(), (select auth.uid()), note, true)
  returning id into aid;
  update public.profiles set influencer = p_kind, influencer_at = now() where id = u.id;
  perform public.notify(u.id, 'influencer_approved', '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.', null, null);
  perform public.log_moderation('grant_influencer', 'user', u.id::text,
    format(E'%s \u00B7 %s', public.influencer_kind_label(p_kind), note), u.nickname);
  return aid;
end;
$$;

create function public.grant_influencer(p_user uuid, p_kind text, p_note text)
returns bigint language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.grant_influencer_unchecked(p_user, p_kind, p_note);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 운영자 신청 목록: 줄마다 'direct' (046과 같고 키 하나만 더함)
--    to_jsonb(x)로 읽어서, 되돌리기로 direct 칸을 지워도 이 함수는 그대로 동작한다 (false)
-- ---------------------------------------------------------------------
create or replace function public.admin_influencer_applications_unchecked(p_status text, p_page integer, p_size integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  st text := coalesce(p_status, 'pending');
  win interval := make_interval(days => coalesce(public.xp_rule('influencer_reject_window_days'), 180));
begin
  if st not in ('pending', 'done') then
    raise exception '목록 종류를 다시 골라 주세요.' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'total', (select count(*) from public.influencer_applications a where (a.status = 'pending') = (st = 'pending')),
    'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'kind', x.kind, 'kind_label', public.influencer_kind_label(x.kind),
               'nickname', x.nickname, 'old_nickname', x.old_nickname,
               'channel_url', x.channel_url, 'official_email', x.official_email, 'riot_id', x.riot_id, 'opgg_url', x.opgg_url,
               'status', x.status, 'created_at', x.created_at, 'expires_at', x.expires_at, 'extended_count', x.extended_count,
               'ended_at', x.ended_at, 'review_note', x.review_note, 'retry_now', x.retry_now,
               'nickname_reverted', x.nickname_reverted, 'revoked_at', x.revoked_at, 'revoke_note', x.revoke_note,
               'direct', coalesce((to_jsonb(x) ->> 'direct')::boolean, false),
               'reviewer', (select r.nickname from public.profiles r where r.id = x.reviewed_by),
               'user', (select jsonb_build_object('id', u.id, 'nickname', u.nickname, 'role', u.role, 'level', u.level,
                                                  'main_title', u.main_title, 'is_guest', u.is_guest, 'created_at', u.created_at,
                                                  'influencer', u.influencer, 'nickname_state', u.nickname_state)
                          from public.profiles u where u.id = x.user_id),
               'overlap', case when x.status = 'pending' then (
                   select jsonb_build_object('id', o.id, 'nickname', o.nickname, 'role', o.role)
                     from public.profiles o join public.profiles me on me.id = x.user_id
                    where o.nickname_key = me.nickname_key and o.id <> me.id limit 1) end,
               'recent_rejections', (select count(*) from public.influencer_applications r
                                      where r.user_id = x.user_id and r.status = 'rejected' and not r.retry_now and r.ended_at > now() - win))
             order by x.ord1, x.ord2 desc nulls last, x.id)
      from (
        select a.*,
               case when st = 'pending' then extract(epoch from a.created_at) end as ord1,
               case when st = 'done' then coalesce(a.revoked_at, a.ended_at) end as ord2
          from public.influencer_applications a
         where (a.status = 'pending') = (st = 'pending')
         order by case when st = 'pending' then a.created_at end, coalesce(a.revoked_at, a.ended_at) desc nulls last, a.id
         limit sz offset (pg - 1) * sz
      ) x
    ), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.grant_influencer_unchecked(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.grant_influencer(uuid, text, text) from public, anon;
grant execute on function public.grant_influencer(uuid, text, text) to authenticated;  -- 운영자인지는 함수 안에서

commit;
