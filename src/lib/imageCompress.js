// 사진 올리기 전 브라우저에서 줄이기 (SPEC 6-13, 023). Supabase 무료 요금제는 서버 쪽 이미지 변환이 없어서 여기서 줄인다.
// - 사진(JPG·PNG·WebP): 긴 변 1600px, WebP(안 되는 브라우저는 JPEG)로 다시 저장 → 400KB 안쪽이 될 때까지 화질·크기를 낮춘다.
//   다시 저장하면서 촬영 위치 같은 사진 정보(EXIF)가 빠진다.
// - GIF: 움직임이 사라지므로 줄이지 않고 그대로 (크기만 확인)
export const GIF = 'image/gif';
export const PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
export const ACCEPT = [...PHOTO_TYPES, GIF].join(',');
export const RAW_MAX_BYTES = 20 * 1024 * 1024;
const MAX_SIDE = 1600;
const TARGET_BYTES = 400 * 1024;
const QUALITIES = [0.82, 0.7, 0.58];

export const fmtMb = (kb) => `${Number((kb / 1024).toFixed(1))}MB`;

/** 고른 파일 → 올릴 것 { blob, mime, ext }. 못 쓰면 Error (화면에 그대로 보여 줄 문구) */
export async function prepareImage(file, { photoMaxKb = 600, gifMaxKb = 3072 } = {}) {
  if (file.type === GIF) {
    if (file.size > gifMaxKb * 1024) throw new Error(`GIF는 ${fmtMb(gifMaxKb)}까지 올릴 수 있습니다.`);
    return { blob: file, mime: GIF, ext: 'gif' };
  }
  if (!PHOTO_TYPES.includes(file.type)) throw new Error('사진은 JPG·PNG·WebP·GIF만 올릴 수 있습니다.');
  if (file.size > RAW_MAX_BYTES) throw new Error('20MB보다 큰 사진은 올릴 수 없습니다.');

  const image = await loadImage(file);
  let side = MAX_SIDE;
  let best = null;
  for (let tries = 0; tries < 3; tries += 1) {
    const canvas = drawScaled(image, side);
    for (const q of QUALITIES) {
      best = await encode(canvas, q);
      if (best.size <= TARGET_BYTES) return result(best);
    }
    side = Math.round(side * 0.75);
  }
  if (best.size <= photoMaxKb * 1024) return result(best);
  throw new Error('사진을 충분히 줄이지 못했습니다. 다른 사진을 골라 주세요.');
}

const result = (blob) => ({ blob, mime: blob.type, ext: blob.type === 'image/webp' ? 'webp' : 'jpg' });

async function loadImage(file) {
  try {
    if (typeof createImageBitmap === 'function') return await createImageBitmap(file, { imageOrientation: 'from-image' });
  } catch {
    /* 아래 방법으로 */
  }
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.decoding = 'async';
    img.src = url;
    await img.decode();
    return img;
  } catch {
    throw new Error('사진을 읽지 못했습니다. 다른 사진을 골라 주세요.');
  } finally {
    URL.revokeObjectURL(url);
  }
}

function drawScaled(image, side) {
  const w = image.width;
  const h = image.height;
  const scale = Math.min(1, side / Math.max(w, h));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(w * scale));
  canvas.height = Math.max(1, Math.round(h * scale));
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff'; // 투명한 PNG는 흰 바탕으로 (JPEG로 저장될 때 검게 되지 않게)
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
  return canvas;
}

const toBlob = (canvas, type, q) => new Promise((resolve) => canvas.toBlob(resolve, type, q));

async function encode(canvas, q) {
  const webp = await toBlob(canvas, 'image/webp', q);
  if (webp && webp.type === 'image/webp') return webp;
  const jpeg = await toBlob(canvas, 'image/jpeg', q); // WebP로 저장하지 못하는 브라우저
  if (!jpeg) throw new Error('사진을 줄이지 못했습니다. 다른 사진을 골라 주세요.');
  return jpeg;
}
