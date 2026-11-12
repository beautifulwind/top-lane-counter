// 말투 검사 (SPEC 3장 "화면 공통 규칙", 2026-11-04): 화면 문구는 "~합니다"체, 부탁만 "~해 주세요".
// 화면 코드(테스트 빼고)와 index.html에 "~해요"체 말끝(…어요·…에요·…돼요·…할까요·…할게요 등)이 다시 들어오면 실패한다.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';

// "~요"로 끝나도 괜찮은 낱말: 부탁("주세요"·"하세요"·"보세요"·"두세요")과 "~요"로 끝나는 명사, 인사("안녕하세요" — 장인 확인 메일 문구, 046),
// 부탁 "확인하세요" (외부 링크 이동 확인 창 "주소를 확인하세요." — 운영자가 정한 문구, 047)
const ALLOWED = new Set(['주세요', '하세요', '보세요', '두세요', '필요', '중요', '안녕하세요', '확인하세요']);

function files(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return name === 'test' ? [] : files(p);
    return /\.(js|jsx)$/.test(name) && !/\.test\.(js|jsx)$/.test(name) ? [p] : [];
  });
}

test('화면 코드에 "~해요"체 말끝이 없다', () => {
  const found = [];
  for (const p of [...files('src'), 'index.html']) {
    for (const [i, line] of readFileSync(p, 'utf8').split('\n').entries()) {
      for (const [w] of line.matchAll(/[가-힣]+요/g)) {
        if (!ALLOWED.has(w)) found.push(`${p}:${i + 1} ${w}`);
      }
    }
  }
  expect(found).toEqual([]);
});

// 용어 정리 (2026-11): 화면에 보이는 "카운터"는 "상대법"으로 바꿨다. 아래 파일·줄만 예외다.
//  - 검색용 이름 "탑 카운터" (legal.js · index.html · manifest.json): 검색 키워드라 그대로 둔다.
//  - 승인 제도 화면(꺼짐): 보이지 않아 바꾸지 않았다. 다시 켤 때 함께 정리한다.
const KEEP_FILES = new Set([
  'src/lib/legal.js', 'src/lib/pageTitle.js', 'src/lib/format.js', 'src/lib/buildContent.js',
  'src/components/ModeratorAdmin.jsx', 'src/pages/Resubmit.jsx', 'src/pages/admin/AdminProposal.jsx',
  'src/api/proposals.js',
]);
const isComment = (l) => /^\s*(\/\/|\/\*|\*|\{\/\*)/.test(l);

test('화면 코드에 "카운터"가 남아 있지 않다 (승인 제도 화면·검색용 이름 제외)', () => {
  const found = [];
  for (const p of files('src')) {
    if (KEEP_FILES.has(p.replaceAll('\\', '/'))) continue;
    for (const [i, line] of readFileSync(p, 'utf8').split('\n').entries()) {
      const code = line.split(/\s\/\/ /)[0];
      if (code.includes('카운터') && !isComment(line)) found.push(`${p}:${i + 1} ${line.trim()}`);
    }
  }
  expect(found.filter((f) => !/new_counter|새 카운터|승인 대기/.test(f))).toEqual([]);
});

test('바꾼 말 뒤 조사가 맞다 ("상대법를·상대법는·상대법가·상대법로·상대법와" 없음)', () => {
  const found = [];
  for (const p of [...files('src'), 'index.html']) {
    for (const [i, line] of readFileSync(p, 'utf8').split('\n').entries()) {
      if (/상대법(를|는|가|로|와)(?![가-힣])|상대법(를|는|가|로|와) /.test(line)) found.push(`${p}:${i + 1}`);
    }
  }
  expect(found).toEqual([]);
});

// 045 게시판 신고 운영진 알림: 알림 문장(DB)·푸시 설정 문구가 "~합니다"체이고 용어가 맞다
test('새 신고 알림 문구 (045): DB 문장은 "~합니다"체, 푸시 설정 문구는 정해진 순서와 용어', () => {
  const sql = readFileSync('supabase/migrations/045_report_received_notify.sql', 'utf8');
  const message = /format\('(새 신고가 들어왔습니다\. \(%s\))'/.exec(sql);
  expect(message?.[1]).toBe('새 신고가 들어왔습니다. (%s)');
  // 코드(주석 아님) 안의 한글 문장에 "~해요"체 말끝이 없다
  const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
  expect([...code.matchAll(/[가-힣]+요/g)].map(([w]) => w).filter((w) => !ALLOWED.has(w))).toEqual([]);
  // 푸시 설정 문구: 운영자 "새 상대법·새 빌드·새 글·새 문의·새 오류 신고·새 신고" / 감독관 "새 문의·새 오류 신고·새 신고"
  const settings = readFileSync('src/components/PushSettings.jsx', 'utf8');
  expect(settings).toContain('운영진 알림: 새 상대법·새 빌드·새 글·새 문의·새 오류 신고·새 신고');
  expect(settings).toContain("'운영진 알림: 새 문의·새 오류 신고·새 신고'");
});
