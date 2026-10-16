// Shared HTTP helpers: one error format, one body limit, no stack traces.

export const MAX_BODY = 16 * 1024;

export class HttpError extends Error {
  constructor(status, code, message, fields = null) {
    super(message);
    this.status = status;
    this.code = code;
    // Names of invalid or missing fields (no values), for 400/422 answers.
    this.fields = fields;
  }
}

/** Parses a JSON body of at most [max] bytes (default 16 KiB). */
export async function readJson(req, max = MAX_BODY) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > max) throw new HttpError(413, 'too_large', 'Yêu cầu quá lớn.');
    chunks.push(chunk);
  }
  if (!size) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'bad_json', 'Dữ liệu gửi lên không hợp lệ.');
  }
}

export function sendJson(res, status, body, headers = {}) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers });
  res.end(JSON.stringify(body));
}

export const notFound = () => new HttpError(404, 'not_found', 'Không tìm thấy.');
