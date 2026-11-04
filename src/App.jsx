import { useEffect } from 'react';
import { BrowserRouter, Navigate, Route, Routes, useLocation, useParams } from 'react-router-dom';
import Layout from './components/Layout';
import ErrorBoundary from './components/ErrorBoundary';
import Home from './pages/Home';
import Champion from './pages/Champion';
import Matchup from './pages/Matchup';
import NotFound from './pages/NotFound';
import Login from './pages/Login';
import Welcome from './pages/Welcome';
import Me from './pages/Me';
import MySettings from './pages/MySettings';
import Notifications from './pages/Notifications';
import ProposeCounter from './pages/ProposeCounter';
import ProposeEdit from './pages/ProposeEdit';
import ProposeBuild from './pages/ProposeBuild';
import AdminHome from './pages/admin/AdminHome';
import AdminProposal from './pages/admin/AdminProposal';
import AdminOrder from './pages/admin/AdminOrder';
import AdminHistory from './pages/admin/AdminHistory';
import AdminPreview from './pages/admin/AdminPreview';
import AdminDelete from './pages/admin/AdminDelete';
import AdminBuild from './pages/admin/AdminBuild';
import AdminReports from './pages/admin/AdminReports';
import Board from './pages/Board';
import BoardPost from './pages/BoardPost';
import BoardWrite from './pages/BoardWrite';
import Resubmit from './pages/Resubmit';
import ResubmitBuild from './pages/ResubmitBuild';
import MyProposal from './pages/MyProposal';
import MyBuild from './pages/MyBuild';
import Privacy from './pages/Privacy';
import Terms from './pages/Terms';
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

/** 옛 주소를 새 주소로 바꿔 보낸다 (뒤로 가기에 옛 주소가 남지 않게 replace) */
function OldPath({ to }) {
  const { id } = useParams();
  return <Navigate to={to(id)} replace />;
}

export function AppRoutes() {
  return (
    <AuthProvider>
      <ScrollToTop />
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<Home />} />
          <Route path="champion/:id" element={<Champion />} />
          <Route path="champion/:id/propose" element={<ProposeCounter />} />
          <Route path="champion/:targetId/counter/:counterId" element={<Matchup />} />
          <Route path="champion/:targetId/counter/:counterId/edit" element={<ProposeEdit />} />
          <Route path="champion/:targetId/counter/:counterId/build/new" element={<ProposeBuild />} />
          <Route path="login" element={<Login />} />
          <Route path="welcome" element={<Welcome />} />
          <Route path="privacy" element={<Privacy />} />
          <Route path="terms" element={<Terms />} />
          <Route path="me" element={<Me />} />
          <Route path="me/settings" element={<MySettings />} />
          <Route path="notifications" element={<Notifications />} />
          <Route path="me/proposals/:id" element={<MyProposal />} />
          <Route path="me/proposals/:id/edit" element={<Resubmit />} />
          <Route path="me/builds/:id" element={<MyBuild />} />
          <Route path="me/builds/:id/edit" element={<ResubmitBuild />} />
          {/* 옛 주소 (알림·북마크) → 새 주소 */}
          <Route path="me/resubmit/:id" element={<OldPath to={(id) => `/me/proposals/${id}/edit`} />} />
          <Route path="me/builds/:id/resubmit" element={<OldPath to={(id) => `/me/builds/${id}/edit`} />} />
          <Route path="admin" element={<AdminHome />} />
          <Route path="admin/proposals/:id" element={<AdminProposal />} />
          <Route path="admin/order/:championId" element={<AdminOrder />} />
          <Route path="admin/history/:targetId/:counterId" element={<AdminHistory />} />
          <Route path="admin/preview/:targetId/:counterId" element={<AdminPreview />} />
          <Route path="admin/delete/:targetId/:counterId" element={<AdminDelete />} />
          <Route path="admin/builds/:id" element={<AdminBuild />} />
          <Route path="admin/reports" element={<AdminReports />} />
          <Route path="board" element={<Board />} />
          <Route path="board/new" element={<BoardWrite />} />
          <Route path="board/:id" element={<BoardPost />} />
          <Route path="board/:id/edit" element={<BoardWrite />} />
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
