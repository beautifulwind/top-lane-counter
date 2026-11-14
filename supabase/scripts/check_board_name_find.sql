-- =====================================================================
-- "자유게시판"이 어디에 남아 있는지 찾는 조회 (읽기만 - 아무것도 바꾸지 않는다). 057 전/후 언제든 실행해도 된다.
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- 전체 표를 훑지 않고, 시스템이 문구를 넣어 두는 곳만 본다:
--   설정 메모(xp_rules.note) / 도감 칭호 글(title_catalog 이름·소개·얻는 방법) / 알림 문장(notifications.message)
--   / 경험치 내역 이유(xp_events.reason) / 처리 기록 메모(moderation_log.note) / 표·칸 설명(comment on) / 함수 본문
-- 이용자가 직접 쓴 글(글·댓글·문서 댓글·문의·제안·신고 내용)은 일부러 보지 않는다. 거기 있는 "자유게시판"은 이용자의 글자라 고치면 안 된다.
-- 줄 수가 0이 아닌 곳이 어디인지 보는 용도다. 057은 이 중 xp_rules.note의 11줄만 바꾼다.
--   - 알림·경험치 내역·처리 기록은 이미 쌓인 기록이라 057이 바꾸지 않는다(024에서는 "노가리방"을 바꿨었다). 고칠지는 결과를 보고 정한다.
-- =====================================================================
select 표_칸 as "표.칸", 줄_수 as "줄 수", 예시 as "예시 (앞 70자)"
from (
  select 1 as ord, 'xp_rules.note' as 표_칸, count(*)::text as 줄_수, coalesce(min(left(note, 70)), '') as 예시
    from public.xp_rules where note like '%자유게시판%'
  union all select 2, 'title_catalog.name / description / how_to', count(*)::text,
      coalesce(min(left(coalesce(name, '') || ' | ' || coalesce(description, '') || ' | ' || how_to, 70)), '')
    from public.title_catalog
    where name like '%자유게시판%' or description like '%자유게시판%' or how_to like '%자유게시판%'
  union all select 3, 'notifications.message', count(*)::text, coalesce(min(left(message, 70)), '')
    from public.notifications where message like '%자유게시판%'
  union all select 4, 'xp_events.reason', count(*)::text, coalesce(min(left(reason, 70)), '')
    from public.xp_events where reason like '%자유게시판%'
  union all select 5, 'moderation_log.note', count(*)::text, coalesce(min(left(note, 70)), '')
    from public.moderation_log where note like '%자유게시판%'
  union all
  select 6, 'comment on ' || x.kind || ': ' || x.name, '1', left(x.txt, 70)
    from (
      select 'table' as kind, c.relname::text as name, d.description as txt
        from pg_description d join pg_class c on c.oid = d.objoid and d.classoid = 'pg_class'::regclass
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and d.objsubid = 0
      union all
      select 'column', c.relname::text || '.' || a.attname::text, d.description
        from pg_description d join pg_class c on c.oid = d.objoid and d.classoid = 'pg_class'::regclass
        join pg_namespace n on n.oid = c.relnamespace
        join pg_attribute a on a.attrelid = c.oid and a.attnum = d.objsubid
       where n.nspname = 'public' and d.objsubid > 0
      union all
      select 'function', p.oid::regprocedure::text, d.description
        from pg_description d join pg_proc p on p.oid = d.objoid and d.classoid = 'pg_proc'::regclass
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
    ) x
   where x.txt like '%자유게시판%'
  union all
  select 7, 'function body: ' || p.oid::regprocedure::text, '1', ''
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc like '%자유게시판%'
  union all select 99, '(끝) 위에 줄이 없으면 이 줄만 나온다', '0', ''
) found
order by ord, 표_칸;
