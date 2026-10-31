export function Loading() {
  return <p className="status">불러오는 중…</p>;
}

export function ErrorBox({ error }) {
  return (
    <p className="status status-error">
      데이터를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.
      <br />
      <small>{String(error?.message ?? error)}</small>
    </p>
  );
}

/** 아직 기능이 연결되지 않은 버튼 (로그인·제안은 이후 단계) */
export function PendingButton({ children }) {
  return (
    <button
      type="button"
      className="btn"
      onClick={() => alert('준비 중인 기능이에요. (로그인·제안 기능은 다음 단계에서 연결됩니다)')}
    >
      {children}
    </button>
  );
}
