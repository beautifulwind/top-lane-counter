// 브라우저 탭 제목 (SPEC 3장): "화면 제목 - 탑 카운터 위키", 홈은 사이트 이름만, 운영자 화면은 앞에 "[운영]".
// 화면 제목 = 본문의 첫 h1 글자 (h1에 data-page-title이 있으면 그 값). 페이지마다 따로 적지 않아도
// 데이터를 불러와 제목이 바뀌면 탭 제목도 따라 바뀐다 (Layout이 본문을 지켜본다).
import { useEffect } from 'react';
import { SITE_NAME } from './legal';

export function pageTitle(pathname, heading) {
  const h = (heading ?? '').replace(/\s+/g, ' ').trim();
  if (pathname === '/' || !h) return SITE_NAME;
  return `${pathname.startsWith('/admin') ? '[운영] ' : ''}${h} - ${SITE_NAME}`;
}

/** mainRef 안의 첫 h1을 지켜보며 document.title을 맞춘다 */
export function usePageTitle(mainRef, pathname) {
  useEffect(() => {
    const main = mainRef.current;
    if (!main) return undefined;
    const update = () => {
      const h1 = main.querySelector('h1');
      const next = pageTitle(pathname, h1?.dataset.pageTitle ?? h1?.textContent);
      if (document.title !== next) document.title = next;
    };
    update();
    const watcher = new MutationObserver(update);
    watcher.observe(main, { childList: true, subtree: true, characterData: true });
    return () => watcher.disconnect();
  }, [mainRef, pathname]);
}
