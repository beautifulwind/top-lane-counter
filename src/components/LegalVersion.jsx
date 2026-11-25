import { Fragment, createContext, useContext } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { LEGAL_REVISION_NOTES, resolveLegalVersion } from '../lib/legal';

/**
 * 방침·약관의 판(시행일) 전환 (SPEC 6-88). 판 목록은 lib/legal.js(첫 판 effectiveDate + revisions).
 * 어느 판을 보여 줄지는 resolveLegalVersion: 오늘(한국 날짜)까지 시행된 가장 새 판이 현행, 주소 ?version=날짜로 다른 판을 미리 보거나 이전 판을 본다.
 * 본문은 판마다 따로 복사하지 않고, 개정판에서 더한 부분만 <Since v="날짜">로 감싼다 → 그 판 이후에만 보인다(앞 판은 한 글자도 안 바뀐다).
 */
const VersionContext = createContext({ versions: [], shown: null, shownIdx: -1, current: null, currentIdx: -1 });

/** 지금 화면의 판 정보 { versions, shown, shownIdx, current, currentIdx, requested } (매번 오늘 날짜로 다시 정한다) */
export function useLegalVersion(kind) {
  const [params] = useSearchParams();
  const requested = params.get('version');
  return { ...resolveLegalVersion(requested, Date.now(), kind), requested };
}

export const LegalVersionProvider = VersionContext.Provider;

/** v판(시행일)부터 보이는 부분. 보고 있는 판이 v보다 앞 판이면 그리지 않는다 */
export function Since({ v, children }) {
  const { versions, shownIdx } = useContext(VersionContext);
  const at = versions.indexOf(v);
  return at >= 0 && shownIdx >= at ? children : null;
}

/**
 * 판 안내 상자 (제목 아래):
 *  - 현행 판을 보는데 더 새 판이 있으면: 「○○부터 새 판이 시행됩니다」 + 바뀐 내용 + [시행 예정 판 미리 보기].
 *    시행 예정 판이 여럿이면 모두 알린다(30일 전 알림이 앞 판 시행 때까지 밀리지 않게). 둘째부터 링크 이름에 날짜가 붙는다.
 *  - 시행 예정 판을 미리 보는 중이면: 「이 판은 ○○부터 시행됩니다(미리 보기)」 + [지금 시행 중인 판 보기]
 *  - 지난 판을 보는 중이면: 「이 판은 ○○판입니다」 + [지금 시행 중인 판 보기]
 * kind: 'privacy' | 'terms' (바뀐 내용 문장이 다르다)
 */
export function LegalVersionNote({ kind }) {
  const { versions, shown, shownIdx, current, currentIdx } = useContext(VersionContext);
  if (versions.length < 2 || shown == null) return null;
  const upcoming = versions.slice(currentIdx + 1);
  if (shownIdx === currentIdx && upcoming.length === 0) return null;
  let body;
  if (shownIdx === currentIdx) {
    body = upcoming.map((next, i) => (
      <Fragment key={next}>
        <p><strong>{next}부터 새 판이 시행됩니다.</strong> {LEGAL_REVISION_NOTES[next]?.[kind]}</p>
        <p><Link to={{ search: `?version=${next}` }}>{i === 0 ? '시행 예정 판 미리 보기' : `${next} 시행 예정 판 미리 보기`}</Link></p>
      </Fragment>
    ));
  } else if (shownIdx > currentIdx) {
    body = (
      <>
        <p><strong>이 판은 {shown}부터 시행됩니다. 지금은 미리 보는 화면입니다.</strong> {LEGAL_REVISION_NOTES[shown]?.[kind]}</p>
        <p>지금 시행 중인 판은 {current}판입니다. <Link to={{ search: '' }}>지금 시행 중인 판 보기</Link></p>
      </>
    );
  } else {
    body = (
      <>
        <p><strong>이 판은 지난 판({shown}판)입니다.</strong></p>
        <p>지금은 {current}판이 시행 중입니다. <Link to={{ search: '' }}>지금 시행 중인 판 보기</Link></p>
      </>
    );
  }
  return <div className="legal-version" role="note" aria-label="판 안내">{body}</div>;
}
