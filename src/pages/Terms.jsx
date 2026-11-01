import { Link } from 'react-router-dom';
import { LEGAL, SITE_NAME } from '../lib/legal';
import LegalFill from '../components/LegalFill';
import { RIOT_NOTICE } from '../components/Layout';

/** 이용약관 (/terms) — 로그인·닉네임 설정 없이도 열린다. */
export default function Terms() {
  const email = <LegalFill value={LEGAL.contactEmail} label="운영자 이메일" email />;
  return (
    <article className="legal">
      <h1 className="doc-title">이용약관</h1>
      <p className="doc-sub">시행일: <LegalFill value={LEGAL.effectiveDate} label="시행일" /></p>

      <section>
        <h2>제1조 (목적)</h2>
        <p>이 약관은 {SITE_NAME}(이하 &ldquo;사이트&rdquo;)를 이용하는 조건과 절차, 이용자와 운영자의 권리·의무를 정합니다.</p>
      </section>

      <section>
        <h2>제2조 (서비스 내용)</h2>
        <ul>
          <li>사이트는 리그 오브 레전드 탑 라인의 챔피언별 카운터와 매치업 공략을 모은 무료 위키입니다.</li>
          <li>위키 보기는 로그인 없이 누구나 할 수 있습니다.</li>
          <li>로그인한 이용자는 새 카운터와 문서 수정을 제안할 수 있고, 제안은 운영자가 승인하면 반영됩니다.</li>
        </ul>
      </section>

      <section>
        <h2>제3조 (회원 가입)</h2>
        <ul>
          <li>회원 가입은 구글 또는 카카오 로그인으로 하며, 로그인하면 이 약관과 <Link to="/privacy">개인정보처리방침</Link>에 동의한 것으로 봅니다.</li>
          <li>만 14세 이상만 가입할 수 있습니다.</li>
          <li>한 사람이 여러 계정을 만들어 제안·평가를 부풀리는 등 부정하게 쓰지 않아야 합니다. 구글·카카오 로그인은 한 계정에 함께 연결할 수 있습니다.</li>
        </ul>
      </section>

      <section>
        <h2>제4조 (닉네임)</h2>
        <ul>
          <li>닉네임은 다른 이용자에게 보이는 공개 정보입니다.</li>
          <li>다른 사람·단체를 사칭하거나, 욕설·혐오 표현·개인정보가 들어간 닉네임은 쓸 수 없습니다.</li>
          <li>이런 닉네임은 운영자가 바꾸도록 요청하거나 이용을 제한할 수 있습니다.</li>
        </ul>
      </section>

      <section>
        <h2>제5조 (기여 내용의 권리)</h2>
        <ul>
          <li>이용자가 작성한 제안 내용의 저작권은 작성한 이용자에게 있습니다.</li>
          <li>
            다만 이용자는 제안을 보내면서, 사이트가 그 내용을 위키 문서로 게시·수정·편집·보관하고 다른 이용자의 수정과
            합칠 수 있도록 무상으로 이용을 허락한 것으로 봅니다. 이 허락은 탈퇴한 뒤에도 이미 반영된 문서에 대해서는
            유지됩니다(작성자 표시는 지움).
          </li>
          <li>다른 사람의 글·영상·자료를 출처나 허락 없이 그대로 옮겨 오면 안 됩니다.</li>
        </ul>
      </section>

      <section>
        <h2>제6조 (금지 행위)</h2>
        <ul>
          <li>사실이 아닌 내용, 같은 내용 반복 제출(도배), 공략과 관계없는 내용 제출</li>
          <li>욕설, 비하, 혐오 표현, 다른 사람의 개인정보 노출</li>
          <li>다른 사람의 저작권 등 권리 침해</li>
          <li>사이트 시스템을 비정상적으로 이용하거나 운영을 방해하는 행위</li>
          <li>그 밖에 법령을 위반하는 행위</li>
        </ul>
      </section>

      <section>
        <h2>제7조 (운영자의 조치)</h2>
        <ul>
          <li>제안의 승인·거절, 반영된 내용의 수정·되돌리기, 카운터 숨기기·삭제는 운영자가 정합니다. 처리할 때는 사유나 메모를 남기고, 제안자는 [내 활동]에서 확인할 수 있습니다.</li>
          <li>제6조를 어기면 운영자는 해당 내용을 숨기거나 삭제하고, 이용을 제한할 수 있습니다.</li>
        </ul>
      </section>

      <section>
        <h2>제8조 (서비스 변경과 중단)</h2>
        <p>사이트는 무료로 운영되며, 운영 사정에 따라 기능을 바꾸거나 서비스를 중단할 수 있습니다. 중요한 변경이나 중단은 미리 사이트에 알립니다.</p>
      </section>

      <section>
        <h2>제9조 (탈퇴)</h2>
        <p>
          이용자는 언제든지 탈퇴할 수 있습니다. 지금은 가입한 이메일로 운영자 이메일({email})에 요청하며, 자세한 절차와
          탈퇴 후 처리는 <Link to="/privacy">개인정보처리방침</Link>을 따릅니다.
        </p>
      </section>

      <section>
        <h2>제10조 (책임의 한계)</h2>
        <ul>
          <li>위키의 공략은 이용자들이 작성한 참고 자료이며, 게임 패치 등으로 실제와 다를 수 있습니다. 사이트는 그 정확성이나 게임 결과를 보장하지 않습니다.</li>
          <li>사이트는 무료 서비스로서, 천재지변·외부 서비스(로그인, 서버 등) 장애처럼 사이트의 고의나 중대한 과실이 없는 사유로 생긴 손해에 대해서는 책임을 지지 않습니다.</li>
        </ul>
      </section>

      <section>
        <h2>제11조 (Riot Games 관련 고지)</h2>
        <p>{RIOT_NOTICE}</p>
      </section>

      <section>
        <h2>제12조 (약관의 변경)</h2>
        <p>약관을 바꾸면 시행 7일 전부터 이 페이지에 알립니다. 이용자에게 불리한 변경은 시행 30일 전부터 알립니다.</p>
      </section>

      <section>
        <h2>제13조 (준거법과 관할)</h2>
        <p>이 약관은 대한민국 법을 따르며, 분쟁이 생기면 민사소송법에 따른 관할 법원에서 해결합니다.</p>
      </section>

      <section>
        <h2>문의</h2>
        <p>운영자 이메일: {email}</p>
        <p>시행일: <LegalFill value={LEGAL.effectiveDate} label="시행일" /></p>
      </section>
    </article>
  );
}
