import { pageTitle } from './pageTitle';

test('탭 제목: 화면 제목 - 사이트 이름, 홈은 사이트 이름만, 운영자 화면은 [운영]', () => {
  expect(pageTitle('/', '상대 탑 라이너 찾기')).toBe('탑 카운터 위키');
  expect(pageTitle('/champion/Darius/counter/Quinn', '퀸으로 다리우스 잡는 법')).toBe('퀸으로 다리우스 잡는 법 - 탑 카운터 위키');
  expect(pageTitle('/admin/reports', '신고  (2)\n')).toBe('[운영] 신고 (2) - 탑 카운터 위키');
  expect(pageTitle('/board', '')).toBe('탑 카운터 위키'); // 불러오는 중 (h1 없음)
});
