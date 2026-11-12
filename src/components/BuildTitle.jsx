import { buildLabel, isInfluencerBuild } from '../lib/wikiBuild';

/**
 * 빌드 이름 (탭·제목): 처음 만든 분이 지금 장인이면 이름 앞에 진홍 "장인 빌드" (046, SPEC 6-32 · 6-33).
 * editors: 다른 사람이 고쳤으면 옆에 작게 "이후 N명이 수정했습니다" (build.editors = 처음 만든 분을 뺀 기여자 수)
 */
export default function BuildTitle({ build, index = 0, editors = false }) {
  if (!isInfluencerBuild(build)) return buildLabel(build, index);
  const n = build.editors ?? 0;
  return (
    <>
      <span className="inf-build-tag">장인 빌드</span>
      {build.name && <>{' '}{build.name}</>}
      {editors && n > 0 && <>{' '}<small className="inf-build-edits">이후 {n}명이 수정했습니다</small></>}
    </>
  );
}
