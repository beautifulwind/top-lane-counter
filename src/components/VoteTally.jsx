import { ThumbIcon } from './Icons';

/** 빌드 추천·비추천 개수 (마이페이지·운영자 목록 줄): 엄지 아이콘 + 숫자. 읽을 때는 "추천 N · 비추천 M" */
export default function VoteTally({ up, down }) {
  return (
    <span className="vote-tally" aria-label={`추천 ${up} · 비추천 ${down}`}>
      <span className="up"><ThumbIcon size={14} /> {up}</span>
      <span className="down"><ThumbIcon down size={14} /> {down}</span>
    </span>
  );
}
