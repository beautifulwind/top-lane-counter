import { pageTitle } from './pageTitle';

test('탭 제목: 화면 제목 - 사이트 이름, 홈은 사이트 이름만, 운영자 화면은 [운영]', () => {
  expect(pageTitle('/', '챔피언 선택')).toBe('탑신병자 - 롤 탑 카운터');
  expect(pageTitle('/champion/Darius/counter/Quinn', '퀸으로 다리우스 이기는 법')).toBe('퀸으로 다리우스 이기는 법 - 탑신병자');
  expect(pageTitle('/admin/reports', '신고  (2)\n')).toBe('[운영] 신고 (2) - 탑신병자');
  expect(pageTitle('/board', '')).toBe('탑신병자 - 롤 탑 카운터'); // 불러오는 중 (h1 없음)
});
