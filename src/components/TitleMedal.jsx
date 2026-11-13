import { useState } from 'react';
import { TITLES } from '../lib/titles';
import { MedalIcon } from './Icons';

/**
 * 칭호 훈장 그림 (053 도감). item = my_title_book의 한 줄 { key, kind, icon, color } (알림은 키만 있어도 됨).
 * - icon(파일 이름)이 있으면 public/titles/<파일 이름> 그림, 없거나 못 불러오면 공통 훈장(MedalIcon)에 color를 입힌다.
 * - 기존 6개 활동 칭호는 color가 비어 있어 CSS 색(tokens.css --title-<키>) 그대로.
 * - secret = 비밀 칭호를 아직 못 얻음 (물음표 훈장, 그림 파일도 숨김)
 * 칸 크기 box = [가로, 세로] px. 그림 파일은 이 칸 안에 비율대로 들어가고, 공통 훈장은 세로를 칸 높이에 맞춘다.
 */
export const BUILTIN_TITLE = (item) => (item?.kind === 'activity' || item?.kind == null) && item?.key in TITLES;

/** 칭호색 클래스(기존 6개)와 도감 color 값을 CSS 변수로 (--t, --t-soft, --t-line) */
export const titleColorClass = (item) => (BUILTIN_TITLE(item) ? item.key : '');
export const titleColorStyle = (item) => {
  const c = item?.color;
  if (!c) return undefined;
  return { '--t': c, '--t-soft': `color-mix(in srgb, ${c} 20%, var(--bg))`, '--t-line': `color-mix(in srgb, ${c} 60%, transparent)` };
};

export default function TitleMedal({ item, box = [52, 40], secret = false }) {
  const [broken, setBroken] = useState(false);
  const [w, h] = box;
  if (item?.icon && !secret && !broken) {
    return (
      <img
        className="medal-icon medal-img" src={`/titles/${encodeURIComponent(item.icon)}`} alt="" width={w} height={h}
        loading="lazy" draggable="false" onError={() => setBroken(true)}
      />
    );
  }
  return <MedalIcon titleKey={item?.key} size={h * (48 / 54)} secret={secret} />;
}
