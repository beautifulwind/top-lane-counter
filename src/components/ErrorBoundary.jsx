import { Component } from 'react';

/**
 * 화면을 그리다 오류가 나도 빈 화면 대신 안내 문구를 보여준다.
 * Layout에서 페이지 경로를 key로 주어, 다른 페이지로 이동하면 자동으로 초기화된다.
 */
export default class ErrorBoundary extends Component {
  state = { error: null };

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('[화면 오류]', error, info?.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <div className="status status-error" role="alert">
        <p>화면을 표시하는 중에 문제가 생겼습니다.</p>
        <small>{String(error.message ?? error)}</small>
        <div className="actions center">
          <button type="button" className="btn" onClick={() => this.setState({ error: null })}>
            다시 시도
          </button>
          <button type="button" className="btn" onClick={() => window.location.reload()}>
            새로고침
          </button>
        </div>
      </div>
    );
  }
}
