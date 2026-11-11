import { Suspense, lazy, useEffect } from 'react';
import { BrowserRouter, Navigate, Route, Routes, useLocation, useParams, useSearchParams } from 'react-router-dom';
import Layout from './components/Layout';
import ErrorBoundary from './components/ErrorBoundary';
import Home from './pages/Home';
import Champion from './pages/Champion';
import Matchup from './pages/Matchup';
import { APPROVAL_ENABLED, APPROVAL_OFF_NOTICE } from './lib/features';
import NotFound from './pages/NotFound';
import Login from './pages/Login';
import Welcome from './pages/Welcome';
import Me from './pages/Me';
import MySettings from './pages/MySettings';
import Notifications from './pages/Notifications';
import Inquiries from './pages/Inquiries';
import Board from './pages/Board';
import BoardPost from './pages/BoardPost';
import BoardWrite from './pages/BoardWrite';
import MyProposal from './pages/MyProposal';
import MyBuild from './pages/MyBuild';
import { AuthProvider } from './lib/auth';
import { Loading } from './components/Status';
import { CHUNK_RELOAD_KEY } from './lib/reloadGuard';

const RELOAD_KEY = CHUNK_RELOAD_KEY;

/**
 * 자주 안 쓰는 화면(운영자·감독관 /admin, 제안·빌드 작성, 방침·약관)은 처음 들어갈 때만 불러온다
 * — 첫 화면(홈·챔피언·매치업·로그인·마이페이지·자유게시판)의 자바스크립트가 작아진다. 불러오는 동안은 "불러오는 중…".
 */
function lazyPage(load) {
  // 새 버전을 배포한 뒤에는 옛 화면 조각 파일이 사라져 불러오기가 실패할 수 있다 → 한 번만 새로고침해서 새 버전을 받는다
  const Page = lazy(() => load().then(
    (module) => {
      try { sessionStorage.removeItem(RELOAD_KEY); } catch { /* 저장소를 못 써도 화면은 그대로 */ }
      return module;
    },
    (error) => {
      try {
        if (!sessionStorage.getItem(RELOAD_KEY)) {
          sessionStorage.setItem(RELOAD_KEY, '1');
          window.location.reload();
          return new Promise(() => {}); // 새로고침되는 동안 "불러오는 중…"
        }
      } catch { /* 저장소를 못 쓰면 아래에서 그냥 오류 */ }
      throw error; // 이미 한 번 새로고침했으면 오류 화면(ErrorBoundary)
    },
  ));
  return function LazyPage(props) {
    return (
      <Suspense fallback={<Loading />}>
        <Page {...props} />
      </Suspense>
    );
  };
}
const MatchupNew = lazyPage(() => import('./pages/MatchupNew'));
const ProposeEdit = lazyPage(() => import('./pages/ProposeEdit'));
const BuildNew = lazyPage(() => import('./pages/BuildNew'));
const BuildEdit = lazyPage(() => import('./pages/BuildEdit'));

/**
 * 승인 제도를 끈 동안(lib/features.js) 승인용 화면(문서 수정 제안, 제안·빌드 고쳐서 다시 보내기) 주소로 오면
 * 그 내용을 보는 화면으로 보내고 안내를 띄운다 (예전 알림·북마크 링크). 화면 코드는 지우지 않는다.
 */
function ApprovalOff({ to }) {
  const params = useParams();
  return <Navigate to={to(params)} replace state={{ done: APPROVAL_OFF_NOTICE, sent: APPROVAL_OFF_NOTICE }} />;
}

/** 예전 주소 (승인 제도 때 새 카운터 제안) /champion/:id/propose?counter=X[&from=제안 id] → 새 상대법 등록 /matchup/new?target=:id&mine=X[&from=] */
function ProposeRedirect() {
  const { id } = useParams();
  const [params] = useSearchParams();
  const next = new URLSearchParams({ target: id });
  if (params.get('counter')) next.set('mine', params.get('counter'));
  if (params.get('from')) next.set('from', params.get('from'));
  return <Navigate to={`/matchup/new?${next}`} replace />;
}
const AdminHome = lazyPage(() => import('./pages/admin/AdminHome'));
const AdminProposal = lazyPage(() => import('./pages/admin/AdminProposal'));
const AdminOrder = lazyPage(() => import('./pages/admin/AdminOrder'));
const AdminHistory = lazyPage(() => import('./pages/admin/AdminHistory'));
const AdminPreview = lazyPage(() => import('./pages/admin/AdminPreview'));
const AdminDelete = lazyPage(() => import('./pages/admin/AdminDelete'));
const AdminBuild = lazyPage(() => import('./pages/admin/AdminBuild'));
const AdminBuildHistory = lazyPage(() => import('./pages/admin/AdminBuildHistory'));
const AdminReports = lazyPage(() => import('./pages/admin/AdminReports'));
const AdminInquiries = lazyPage(() => import('./pages/admin/AdminInquiries'));
const AdminMembers = lazyPage(() => import('./pages/admin/AdminMembers'));
const AdminMember = lazyPage(() => import('./pages/admin/AdminMember'));
const Resubmit = lazyPage(() => import('./pages/Resubmit'));
const ResubmitBuild = lazyPage(() => import('./pages/ResubmitBuild'));
const Privacy = lazyPage(() => import('./pages/Privacy'));
const Terms = lazyPage(() => import('./pages/Terms'));

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
          <Route path="champion/:id/propose" element={<ProposeRedirect />} />
          <Route path="matchup/new" element={<MatchupNew />} />
          <Route path="champion/:targetId/counter/:counterId" element={<Matchup />} />
          <Route path="champion/:targetId/counter/:counterId/edit" element={APPROVAL_ENABLED ? <ProposeEdit /> : <ApprovalOff to={(p) => `/champion/${p.targetId}/counter/${p.counterId}`} />} />
          <Route path="champion/:targetId/counter/:counterId/build/new" element={<BuildNew />} />
          <Route path="champion/:targetId/counter/:counterId/build/:buildId/edit" element={<BuildEdit />} />
          <Route path="login" element={<Login />} />
          <Route path="welcome" element={<Welcome />} />
          <Route path="privacy" element={<Privacy />} />
          <Route path="terms" element={<Terms />} />
          <Route path="me" element={<Me />} />
          <Route path="me/settings" element={<MySettings />} />
          <Route path="notifications" element={<Notifications />} />
          <Route path="inquiries" element={<Inquiries />} />
          <Route path="me/proposals/:id" element={<MyProposal />} />
          <Route path="me/proposals/:id/edit" element={APPROVAL_ENABLED ? <Resubmit /> : <ApprovalOff to={(p) => `/me/proposals/${p.id}`} />} />
          <Route path="me/builds/:id" element={<MyBuild />} />
          <Route path="me/builds/:id/edit" element={APPROVAL_ENABLED ? <ResubmitBuild /> : <ApprovalOff to={(p) => `/me/builds/${p.id}`} />} />
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
          <Route path="admin/builds/:id/history" element={<AdminBuildHistory />} />
          <Route path="admin/reports" element={<AdminReports />} />
          <Route path="admin/inquiries" element={<AdminInquiries />} />
          {/* 042: 회원 관리 한 화면 (예전 /admin의 "회원"·"감독관 관리" 칸). 감독관 관리 자리는 감독관만 거른 회원 관리로 */}
          <Route path="admin/members" element={<AdminMembers />} />
          <Route path="admin/members/:id" element={<AdminMember />} />
          <Route path="admin/moderators" element={<Navigate to="/admin/members?role=moderator" replace />} />
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
