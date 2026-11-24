import { useRef } from 'react';
import { SearchIcon, XCircleIcon } from './Icons';

/**
 * 알약형 검색 입력 (1.3 패치 1-B2 보완, SPEC 6-95) — /influencers 닉네임 검색과 메인 「챔피언·빌드 검색」이 같이 쓴다.
 * 높이 46px · 완전히 둥근 모서리 · 왼쪽 주황 돋보기 · 오른쪽 둥근 [지우기](글자가 있을 때만, 겹쳐 놓아서 보이고 사라져도 자리가 안 흔들림).
 * [지우기]: 입력을 비우고(onChange('')) onClear를 부른 뒤 입력창으로 초점을 돌려준다.
 * 입력 글자는 16px(모바일 확대 방지), type=search, enterkeyhint=search. 나머지 속성(id·maxLength·role·aria-*·onKeyDown 등)은 입력창에 그대로 넘긴다.
 * 검색 로직(대기·조합 입력 등)은 쓰는 쪽이 그대로 가진다 — 이 컴포넌트는 모양과 지우기만 맡는다.
 */
export default function SearchField({ value, onChange, onClear, label, placeholder, inputRef, className = '', ...inputProps }) {
  const own = useRef(null);
  const ref = inputRef ?? own;
  const clear = () => {
    onChange('');
    onClear?.();
    ref.current?.focus();
  };
  return (
    <div className={`pill-search ${className}`.trim()}>
      <SearchIcon size={19} className="pill-search-icon" />
      <input
        ref={ref} type="search" value={value} placeholder={placeholder} aria-label={label} autoComplete="off" enterKeyHint="search"
        {...inputProps} onChange={(e) => onChange(e.target.value)}
      />
      {value !== '' && (
        <button type="button" className="pill-search-clear" aria-label="지우기" onClick={clear}>
          <XCircleIcon size={12} />
        </button>
      )}
    </div>
  );
}
