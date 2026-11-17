// 챔피언 별명·줄임말 (홈 검색창, SPEC 6-61). { Data Dragon 챔피언 id: [별명, …] }
// 이름 앞부분(예: "말파" → 말파이트, "다리" → 다리우스)은 검색이 이미 부분 일치로 찾으므로 여기엔 넣지 않는다.
// 이름에 들어 있지 않은 줄임말·표기 변형·영문 이름만 적는다. 확실한 것만 넣고, 고치기는 이 파일만 열면 된다.
export const CHAMP_ALIASES = {
  TwistedFate: ['트페'],
  MissFortune: ['미포'],
  MasterYi: ['마이'],
  Blitzcrank: ['블크'],
  AurelionSol: ['아우솔'],
  MonkeyKing: ['손오공', 'wukong'], // 영문 이름은 Wukong인데 id는 MonkeyKing
  Thresh: ['스레쉬'], // 공식 표기는 "쓰레쉬"
  Ashe: ['애시'], // 공식 표기는 "애쉬"
  Graves: ['그브'],
  Volibear: ['볼베'],
};
