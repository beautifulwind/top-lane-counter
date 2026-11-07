// 023: 자유게시판 사진·GIF — 글·댓글에 붙이기(회원만), 빼기, 고치기 때 바꾸기, 보기·크게 보기, 목록 📷, 사진 신고 사유, 운영자 저장 공간
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeGuestLogin, fakeLogin, fakePost, fakeState } from './fakeSupabase';
import { ReportForm } from '../components/BoardParts';

// 브라우저 줄이기(canvas)는 jsdom에 없어서 흉내: 사진은 webp로, 큰 GIF는 문구로 막는다
vi.mock('../lib/imageCompress', async (orig) => {
  const real = await orig();
  return {
    ...real,
    prepareImage: vi.fn(async (file) => {
      if (file.type === 'image/gif') {
        if (file.size > 3 * 1024 * 1024) throw new Error('GIF는 3MB까지 올릴 수 있습니다.');
        return { blob: file, mime: 'image/gif', ext: 'gif' };
      }
      return { blob: new Blob(['x'], { type: 'image/webp' }), mime: 'image/webp', ext: 'webp' };
    }),
  };
});

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  URL.createObjectURL = vi.fn(() => 'blob:preview');
  URL.revokeObjectURL = vi.fn();
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const OTHER = { nickname: '남의글', level: 2, main_title: null };
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const photo = (name = 'a.jpg') => new File(['p'], name, { type: 'image/jpeg' });
const gif = (size = 10) => new File([new Uint8Array(size)], 'g.gif', { type: 'image/gif' });
const pick = (id, files) => fireEvent.change(document.getElementById(id), { target: { files } });
const shot = (path, mime = 'image/webp') => ({ path, mime, size: 1000, position: 0 });

test('글쓰기: 사진·GIF를 붙이고 빼고, 사진만 있어도 올릴 수 있다 → 올린 경로를 순서대로 보낸다', async () => {
  fakeLogin('u-old');
  start('/board/new');
  const add = await screen.findByRole('button', { name: /사진·GIF 추가 \(0\/4\)/ });
  expect(add).toBeDefined();
  fireEvent.change(screen.getByLabelText('제목'), { target: { value: '사진 글' } });
  expect(screen.getByRole('button', { name: '글 올리기' }).disabled).toBe(true); // 본문도 사진도 없으면 못 보냄

  pick('post-media', [photo('1.jpg'), gif(), gif()]);
  const thumbs = await screen.findByRole('list', { name: '붙일 사진' });
  await vi.waitFor(() => expect(within(thumbs).getAllByRole('listitem')).toHaveLength(2));
  expect(screen.getByRole('alert')).toHaveTextContent('GIF는 1개까지 붙일 수 있습니다.');
  expect(screen.getByRole('button', { name: /\(2\/4\)/ })).toBeDefined();

  pick('post-media', [photo('2.jpg')]);
  await vi.waitFor(() => expect(within(thumbs).getAllByRole('listitem')).toHaveLength(3));
  fireEvent.click(screen.getByRole('button', { name: '사진 1 빼기' }));
  expect(within(thumbs).getAllByRole('listitem')).toHaveLength(2);

  fireEvent.click(screen.getByRole('button', { name: '글 올리기' }));
  await screen.findByRole('heading', { level: 1, name: '사진 글' });
  expect(fakeState.uploads.map((u) => u.mime)).toEqual(['image/gif', 'image/webp']);
  expect(fakeState.uploads.every((u) => u.bucket === 'board-media' && u.path.startsWith('u-old/'))).toBe(true);
  const [args] = rpcs('create_post');
  expect(args.p_body).toBe('');
  expect(args.p_media).toEqual(fakeState.uploads.map((u) => u.path));
  // 글 보기: 사진 두 칸, GIF 표시, 누르면 크게 → Esc로 닫힘
  const gallery = await screen.findByRole('list', { name: '첨부 사진' });
  expect(within(gallery).getAllByRole('img')).toHaveLength(2);
  fireEvent.click(within(gallery).getByRole('button', { name: '첨부 사진 2 크게 보기' }));
  const viewer = screen.getByRole('dialog', { name: '첨부 사진 2' });
  expect(within(viewer).getByRole('button', { name: '닫기' })).toBe(document.activeElement);
  fireEvent.keyDown(viewer, { key: 'Escape' });
  expect(screen.queryByRole('dialog')).toBeNull();
});

test('올리기가 막히면(하루 개수·용량) 그 이유를 보여 주고, 큰 GIF는 문구로 막는다', async () => {
  fakeLogin('u-old');
  start('/board/new');
  await screen.findByRole('button', { name: /사진·GIF 추가/ });
  pick('post-media', [gif(4 * 1024 * 1024)]);
  expect(await screen.findByRole('alert')).toHaveTextContent('GIF는 3MB까지 올릴 수 있습니다.');
  expect(screen.queryByRole('list', { name: '붙일 사진' })).toBeNull();

  fakeState.mediaProblem = '사진은 하루 20개까지 올릴 수 있습니다. 내일 다시 올려 주세요.';
  pick('post-media', [photo()]);
  await vi.waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('하루 20개까지'));
  expect(screen.queryByRole('list', { name: '붙일 사진' })).toBeNull();
});

test('글을 올리다 실패하면 다시 눌러도 같은 사진을 또 올리지 않는다', async () => {
  fakeLogin('u-old');
  start('/board/new');
  await screen.findByRole('button', { name: /사진·GIF 추가/ });
  fireEvent.change(screen.getByLabelText('제목'), { target: { value: '제목' } });
  pick('post-media', [photo()]);
  await screen.findByRole('list', { name: '붙일 사진' });
  fakeState.boardError = '글은 30초에 한 번만 쓸 수 있습니다.';
  fireEvent.click(screen.getByRole('button', { name: '글 올리기' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('30초에 한 번');
  fakeState.boardError = null;
  fireEvent.click(screen.getByRole('button', { name: '글 올리기' }));
  await screen.findByRole('heading', { level: 1, name: '제목' });
  expect(fakeState.uploads).toHaveLength(1);
  expect(rpcs('create_post')[1].p_media).toEqual([fakeState.uploads[0].path]);
});

test('비회원은 사진을 붙일 수 없다 (안내만)', async () => {
  fakeGuestLogin('g-1', { nickname: '손님' });
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER }));
  start('/board/new');
  expect(await screen.findByText(/비회원은 사진을 붙일 수 없습니다/)).toBeDefined();
  expect(screen.queryByRole('button', { name: /사진·GIF 추가/ })).toBeNull();
  cleanup();
  start('/board/1');
  await screen.findByRole('button', { name: '댓글 올리기' });
  expect(screen.queryByRole('button', { name: /사진·GIF 추가/ })).toBeNull();
  expect(screen.getByText(/비회원은 사진을 붙일 수 없습니다/)).toBeDefined();
});

test('글 고치기: 사진을 안 건드리면 p_media null(그대로), 빼면 남은 목록', async () => {
  TABLES.posts.push(fakePost(1, {
    author_id: 'u-old', created_at: new Date().toISOString(), media: [shot('u-old/a.webp'), { ...shot('u-old/b.gif', 'image/gif'), position: 1 }],
  }));
  fakeLogin('u-old');
  start('/board/1/edit');
  const thumbs = await screen.findByRole('list', { name: '붙일 사진' });
  expect(within(thumbs).getAllByRole('listitem')).toHaveLength(2);
  fireEvent.click(screen.getByRole('button', { name: '고친 내용 저장' }));
  await screen.findByText('글을 고쳤습니다.');
  expect(rpcs('edit_post')[0].p_media).toBeNull();

  cleanup();
  start('/board/1/edit');
  await screen.findByRole('list', { name: '붙일 사진' });
  fireEvent.click(screen.getByRole('button', { name: '사진 1 빼기' }));
  fireEvent.click(screen.getByRole('button', { name: '고친 내용 저장' }));
  await screen.findByText('글을 고쳤습니다.');
  expect(rpcs('edit_post')[1].p_media).toEqual(['u-old/b.gif']);
  expect(within(screen.getByRole('list', { name: '첨부 사진' })).getAllByRole('img')).toHaveLength(1);
});

test('댓글: 사진 하나만 붙여 올리기, 고칠 때 빼기, 서명 못 받은 사진은 "불러오지 못했습니다"', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER, media: [shot('u-x/c.webp')] }));
  fakeLogin('u-old');
  start('/board/1');
  const add = await screen.findByRole('button', { name: /사진·GIF 추가 \(0\/1\)/ });
  expect(within(screen.getByRole('list', { name: '댓글' })).getByRole('img', { name: '댓글 사진 1' })).toBeDefined();

  pick('new-comment-media', [photo()]);
  await screen.findByRole('list', { name: '붙일 사진' });
  expect(add.disabled).toBe(true); // 1/1
  fireEvent.click(screen.getByRole('button', { name: '댓글 올리기' })); // 글 없이 사진만
  await screen.findByText('2개', { selector: '#comments .count-badge' });
  expect(rpcs('create_comment')[0]).toEqual({ p_post: 1, p_body: '', p_media: [fakeState.uploads[0].path] });

  const mine = within(screen.getByRole('list', { name: '댓글' })).getAllByRole('listitem').find((li) => li.id === 'comment-801');
  expect(within(mine).getAllByRole('img', { name: '댓글 사진 1' })).toHaveLength(1);
  fireEvent.click(within(mine).getByRole('button', { name: '고치기' }));
  fireEvent.click(await within(mine).findByRole('button', { name: '사진 1 빼기' }));
  expect(within(mine).getByRole('button', { name: '고친 내용 저장' }).disabled).toBe(true); // 글도 사진도 없으면 못 저장
  fireEvent.change(within(mine).getByLabelText('댓글 고치기'), { target: { value: '글로 바꿈' } });
  fireEvent.click(within(mine).getByRole('button', { name: '고친 내용 저장' }));
  await vi.waitFor(() => expect(rpcs('edit_comment')).toEqual([{ p_id: 801, p_body: '글로 바꿈', p_media: [] }]));
});

test('사진 주소를 못 받으면 칸에 "사진을 불러오지 못했습니다"', async () => {
  TABLES.posts.push(fakePost(1, { media: [shot('u-old/a.webp')] }));
  const { db } = await import('./fakeSupabase');
  const real = db().storage.from;
  vi.spyOn(db().storage, 'from').mockImplementation((b) => ({
    ...real(b), createSignedUrls: async () => ({ data: null, error: { message: 'boom' } }),
  }));
  start('/board/1');
  expect(await screen.findByText('사진을 불러오지 못했습니다')).toBeDefined();
});

test('목록: 사진 있는 글에 📷', async () => {
  TABLES.posts.push(fakePost(1, { media: [shot('u-old/a.webp')] }), fakePost(2));
  start('/board');
  await screen.findByText('글 2');
  expect(screen.getAllByRole('img', { name: '사진 있음' })).toHaveLength(1);
});

test('신고 사유: 자유게시판은 "음란·잔혹한 사진"이 있고, 사진 없는 곳(문서 댓글)에는 없다', () => {
  const { rerender } = render(<ReportForm id="r" what="댓글" onSubmit={() => {}} onCancel={() => {}} />);
  expect(screen.getByRole('radio', { name: /음란·잔혹한 사진/ })).toBeDefined();
  rerender(<ReportForm id="r" what="댓글" photos={false} onSubmit={() => {}} onCancel={() => {}} />);
  expect(screen.queryByRole('radio', { name: /음란·잔혹한 사진/ })).toBeNull();
  expect(screen.getByRole('radio', { name: /혐오·비하/ })).toBeDefined();
});

test('운영자 /admin: 사진 저장 공간 — 사용량 막대, 800MB 넘으면 경고, 900MB 넘으면 막힘', async () => {
  const MB = 1024 * 1024;
  fakeState.mediaUsage = {
    bytes: 820 * MB, files: 1500, gif_bytes: 300 * MB, gifs: 120, hidden_bytes: 5 * MB, recent_bytes: 40 * MB, recent_files: 90,
    trash: 3, orphans: 2, top: [{ nickname: '사진왕', files: 300, bytes: 150 * MB }], total_mb: 1024, warn_mb: 800, block_mb: 900,
  };
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start('/admin');
  const sec = (await screen.findByRole('heading', { name: '사진 저장 공간' })).closest('section');
  expect(await within(sec).findByText(/820MB/)).toBeDefined();
  expect(within(sec).getByRole('meter', { name: '사진 저장 공간' }).className).toContain('warned');
  expect(within(sec).getByRole('status')).toHaveTextContent('800MB를 넘었습니다');
  expect(within(sec).getByText(/사진왕 — 300개, 150MB/)).toBeDefined();
  expect(within(sec).getByText(/지울 차례 \(매일 정리\): 3개 · 글에 안 붙은 사진: 2개/)).toBeDefined();

  cleanup();
  fakeState.mediaUsage = { ...fakeState.mediaUsage, bytes: 950 * MB };
  start('/admin');
  const sec2 = (await screen.findByRole('heading', { name: '사진 저장 공간' })).closest('section');
  expect(await within(sec2).findByRole('alert')).toHaveTextContent('새 사진 첨부가 막혔습니다');
});

// 끌어다 놓기·Ctrl+V 붙여넣기 — 버튼과 같은 길(개수·GIF 수·크기·압축·올리기 가능 여부)
const files = (list, extra = []) => ({ types: [...extra, 'Files'], files: list, dropEffect: 'none' });
const dragIn = (zone, list) => fireEvent.dragEnter(zone, { dataTransfer: files(list) });
const dropOn = (zone, list) => fireEvent.drop(zone, { dataTransfer: files(list) });
const pasteOn = (el, list, extra) => fireEvent.paste(el, { clipboardData: files(list, extra) });

test('글쓰기: 끌어다 놓으면 "여기에 놓으면 첨부됩니다" → 놓으면 첨부, 사진이 아니면 안내, 붙여넣기도 첨부', async () => {
  fakeLogin('u-old');
  start('/board/new');
  await screen.findByRole('button', { name: /사진·GIF 추가 \(0\/4\)/ });
  const form = screen.getByLabelText('제목').closest('form');
  const body = screen.getByLabelText('본문');

  dragIn(body, [photo()]); // 칸 안 어디든 (본문 위에서도)
  expect(screen.getByText('여기에 놓으면 첨부됩니다')).toBeDefined();
  fireEvent.dragLeave(body, { dataTransfer: files([]) });
  expect(screen.queryByText('여기에 놓으면 첨부됩니다')).toBeNull();

  dragIn(form, [photo()]);
  expect(dropOn(form, [photo('1.jpg'), gif()])).toBe(false); // 브라우저 기본 동작(새 탭으로 열기) 막음
  expect(screen.queryByText('여기에 놓으면 첨부됩니다')).toBeNull();
  const thumbs = await screen.findByRole('list', { name: '붙일 사진' });
  await vi.waitFor(() => expect(within(thumbs).getAllByRole('listitem')).toHaveLength(2));

  dropOn(form, [new File(['%PDF'], 'a.pdf', { type: 'application/pdf' })]);
  expect(await screen.findByRole('alert')).toHaveTextContent('사진·GIF만 올릴 수 있습니다.');
  expect(within(thumbs).getAllByRole('listitem')).toHaveLength(2);

  // 섞여 있으면 사진은 붙이고 안내도 보여 준다. GIF 수 제한도 버튼과 같다
  dropOn(form, [new File(['x'], 'memo.txt', { type: 'text/plain' }), gif()]);
  await vi.waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('사진·GIF만 올릴 수 있습니다. GIF는 1개까지 붙일 수 있습니다.'));
  expect(within(thumbs).getAllByRole('listitem')).toHaveLength(2);

  // Ctrl+V: 캡처·이미지 복사는 첨부, 글자가 같이 있는 복사(엑셀·워드)는 글자 붙여넣기로 둔다
  expect(pasteOn(body, [photo('cap.png')])).toBe(false);
  await vi.waitFor(() => expect(within(thumbs).getAllByRole('listitem')).toHaveLength(3));
  expect(pasteOn(body, [photo('cell.png')], ['text/plain'])).toBe(true);
  expect(pasteOn(body, [photo('4.png')])).toBe(false);
  await vi.waitFor(() => expect(within(thumbs).getAllByRole('listitem')).toHaveLength(4));

  dragIn(form, [photo()]); // 다 찼으면 놓기 전에 알려 주고, 놓으면 개수 안내
  expect(screen.getByText('사진은 4개까지 붙일 수 있습니다')).toBeDefined();
  dropOn(form, [photo()]);
  expect(await screen.findByRole('alert')).toHaveTextContent('사진은 4개까지 붙일 수 있습니다.');
  expect(within(thumbs).getAllByRole('listitem')).toHaveLength(4);
  expect(fakeState.uploads).toHaveLength(0); // 보낼 때 올린다
});

test('끌어다 놓기도 올리기가 막히면(하루 개수) 그 이유를 보여 준다', async () => {
  fakeLogin('u-old');
  start('/board/new');
  await screen.findByRole('button', { name: /사진·GIF 추가/ });
  fakeState.mediaProblem = '사진은 하루 20개까지 올릴 수 있습니다. 내일 다시 올려 주세요.';
  dropOn(screen.getByLabelText('제목').closest('form'), [photo()]);
  await vi.waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('하루 20개까지'));
  expect(screen.queryByRole('list', { name: '붙일 사진' })).toBeNull();
});

test('댓글: 댓글 칸에 붙여넣기·끌어다 놓기로 첨부 (1개까지), 고치기 칸에서도', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-old', created_at: new Date().toISOString() }));
  fakeLogin('u-old');
  start('/board/1');
  await screen.findByRole('button', { name: /사진·GIF 추가 \(0\/1\)/ });
  const box = screen.getByLabelText('댓글 쓰기');
  pasteOn(box, [photo('cap.png')]);
  const newForm = box.closest('form');
  await vi.waitFor(() => expect(within(newForm).getAllByRole('img', { name: /붙일 사진/ })).toHaveLength(1));
  dropOn(newForm, [photo()]);
  expect(await within(newForm).findByRole('alert')).toHaveTextContent('사진은 1개까지 붙일 수 있습니다.');

  const mine = document.getElementById('comment-11');
  fireEvent.click(within(mine).getByRole('button', { name: '고치기' }));
  const editForm = (await within(mine).findByLabelText('댓글 고치기')).closest('form');
  dropOn(editForm, [gif()]);
  await vi.waitFor(() => expect(within(editForm).getAllByRole('img', { name: /붙일 사진/ })).toHaveLength(1));
  expect(within(newForm).getAllByRole('img', { name: /붙일 사진/ })).toHaveLength(1); // 다른 칸에는 안 붙는다
});

test('첨부 칸 밖에 파일을 떨어뜨려도 새 탭으로 열리지 않는다 (글자 끌기는 그대로)', async () => {
  const { blockStrayFileDrops } = await import('../components/Media');
  const stop = blockStrayFileDrops(window);
  try {
    const out = document.createElement('div');
    document.body.appendChild(out);
    expect(fireEvent.dragOver(out, { dataTransfer: files([photo()]) })).toBe(false);
    expect(fireEvent.drop(out, { dataTransfer: files([photo()]) })).toBe(false);
    expect(fireEvent.drop(out, { dataTransfer: { types: ['text/plain'], files: [] } })).toBe(true);
    out.remove();
  } finally {
    stop();
  }
});
