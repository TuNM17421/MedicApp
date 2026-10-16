// Serves the doctor web build at /doctor/ with SPA fallback. Paths are
// resolved inside the build folder only; anything escaping it is a 404.
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, resolve, sep } from 'node:path';

import { HttpError, notFound } from '../http.js';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
};

export const SECURITY_HEADERS = {
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
};

/**
 * Bước 18: what every response carries. JSON answers may not run or embed
 * anything; the CSP of the web build is below.
 */
export function baseHeaders({ https = false } = {}) {
  return {
    ...SECURITY_HEADERS,
    'cache-control': 'no-store',
    'content-security-policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
    'cross-origin-opener-policy': 'same-origin',
    'cross-origin-resource-policy': 'same-origin',
    'permissions-policy': 'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
    // Only meaningful behind HTTPS (TLS ends at the reverse proxy).
    ...(https ? { 'strict-transport-security': 'max-age=31536000; includeSubDomains' } : {}),
  };
}

/**
 * The doctor web (Flutter, CanvasKit bundled by --no-web-resources-cdn):
 * everything from this origin only. 'wasm-unsafe-eval' lets CanvasKit's
 * WebAssembly compile (no JavaScript eval); Flutter sets inline styles;
 * blob: frames are the print preview of the prescription PDF.
 */
export const DOCTOR_WEB_CSP = [
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self' data:",
  "connect-src 'self'",
  "worker-src 'self' blob:",
  "frame-src 'self' blob:",
  "manifest-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ');

function isFile(path) {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

/** Handles GET/HEAD `/doctor/...` from [root]. */
export function serveDoctorWeb(req, res, pathname, root) {
  const base = resolve(root);
  if (!existsSync(resolve(base, 'index.html'))) {
    throw new HttpError(404, 'doctor_web_missing', 'Chưa có bản build web bác sĩ (flutter build web).');
  }
  let rel;
  try {
    rel = decodeURIComponent(pathname.slice('/doctor/'.length));
  } catch {
    throw notFound();
  }
  if (rel.includes('\0') || rel.includes('\\')) throw notFound();
  let file = resolve(base, rel || 'index.html');
  if (file !== base && !file.startsWith(base + sep)) throw notFound();
  if (file === base) file = resolve(base, 'index.html');
  if (!isFile(file)) {
    // Unknown route of the single-page app: hand it index.html. A missing
    // file with an extension stays a 404 so broken assets are visible.
    if (extname(rel)) throw notFound();
    file = resolve(base, 'index.html');
  }
  const type = TYPES[extname(file).toLowerCase()] ?? 'application/octet-stream';
  res.writeHead(200, {
    'content-type': type,
    'content-length': statSync(file).size,
    'cache-control': 'no-cache',
    'content-security-policy': DOCTOR_WEB_CSP,
    ...SECURITY_HEADERS,
  });
  if (req.method === 'HEAD') return res.end();
  createReadStream(file).pipe(res);
}
