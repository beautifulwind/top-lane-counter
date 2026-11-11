import { BUILD_NAME_MAX } from '../lib/wikiBuild';
import { DocFields } from './DocForm';
import BuildFields from './BuildFields';

/**
 * 빌드 한 벌 입력 (새 상대법·새 빌드·빌드 수정 공용): 빌드 이름(선택) → 한 줄 요약 → 룬·주문·아이템·선마 → 레벨별 딜교법 → 특이사항.
 * 감싸는 <form className="doc-form">은 각 화면이 그린다. value = wikiBuild.emptyWikiBuild 모양 (빌드 칸과 글 칸이 한 객체), game = getBuildGame() 결과, author = 미리보기 작성자
 */
export default function WikiBuildFields({ game, value, onChange, author }) {
  const name = value.name ?? '';
  return (
    <>
      <label htmlFor="build-name">빌드 이름 (선택)</label>
      <small className="hint" id="build-name-hint">
        예) 착취 탱커, 정복자 딜교형 · 비우면 "빌드 1", "빌드 2"…처럼 번호로 보입니다.
      </small>
      <input
        id="build-name"
        value={name}
        onChange={(e) => onChange({ ...value, name: e.target.value })}
        maxLength={BUILD_NAME_MAX + 5}
        aria-describedby="build-name-hint"
        autoComplete="off"
      />
      <small className="count">{[...name.trim()].length}/{BUILD_NAME_MAX}자</small>

      <DocFields
        value={value}
        onChange={onChange}
        afterSummary={(
          <fieldset className="pick-group build-in-doc">
            <legend>룬·주문·아이템·선마 (필수)</legend>
            <div className="build-form">
              <BuildFields game={game} value={value} onChange={onChange} author={author} />
            </div>
          </fieldset>
        )}
      />
    </>
  );
}
