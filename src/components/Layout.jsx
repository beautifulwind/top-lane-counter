import { Link, Outlet } from 'react-router-dom';

export const RIOT_NOTICE =
  '이 사이트는 Riot Games가 보증하거나 후원하지 않으며, Riot Games 또는 League of Legends 제작·관리에 공식적으로 관여한 사람의 견해를 반영하지 않습니다. League of Legends 및 Riot Games는 Riot Games, Inc.의 상표 또는 등록 상표입니다.';

export default function Layout() {
  return (
    <div className="app">
      <header className="topbar">
        <Link to="/" className="brand">
          탑 카운터 위키
        </Link>
      </header>
      <main className="content">
        <Outlet />
      </main>
      <footer className="footer">
        <p>{RIOT_NOTICE}</p>
      </footer>
    </div>
  );
}
