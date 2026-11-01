import { useEffect } from 'react';
import { BrowserRouter, Route, Routes, useLocation } from 'react-router-dom';
import Layout from './components/Layout';
import ErrorBoundary from './components/ErrorBoundary';
import Home from './pages/Home';
import Champion from './pages/Champion';
import Matchup from './pages/Matchup';
import NotFound from './pages/NotFound';
import Login from './pages/Login';
import Welcome from './pages/Welcome';
import Me from './pages/Me';
import { AuthProvider } from './lib/auth';

function ScrollToTop() {
  const { pathname } = useLocation();
  // 중괄호 필수: scrollTo()는 최신 브라우저에서 Promise를 돌려줄 수 있는데,
  // 이를 그대로 return하면 React가 cleanup으로 호출해 "n is not a function" 오류가 난다.
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);
  return null;
}

export function AppRoutes() {
  return (
    <AuthProvider>
      <ScrollToTop />
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<Home />} />
          <Route path="champion/:id" element={<Champion />} />
          <Route path="champion/:targetId/counter/:counterId" element={<Matchup />} />
          <Route path="login" element={<Login />} />
          <Route path="welcome" element={<Welcome />} />
          <Route path="me" element={<Me />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </AuthProvider>
  );
}

export default function App() {
  return (
    <ErrorBoundary>
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <AppRoutes />
      </BrowserRouter>
    </ErrorBoundary>
  );
}
