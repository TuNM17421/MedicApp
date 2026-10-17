// Bước 18: put a backup back as the clinic database.
//
//   npm run restore -- clinic-20261016-020000.db     (a name in BACKUP_DIR)
//   npm run restore -- D:\backups\clinic-20261016-020000.db
//
// Safety: refuses while a server answers on HOST:PORT (stop it first), and
// refuses a file that fails quick_check, is not a clinic database or comes
// from a newer version of the code. Before replacing, the current database
// is copied to BACKUP_DIR/before-restore-<time>.db (never pruned), so a
// wrong restore can be undone the same way. Pending migrations run after.
import { copyFileSync, existsSync, rmSync } from 'node:fs';
import { basename, isAbsolute, join, resolve } from 'node:path';
import { DatabaseSync, backup } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

import { migrations } from '../db/migrations.js';
import { backupName, checkDatabaseFile } from './backup.js';

/** True when something answers /health at [host]:[port] within a second. */
export async function serverRunning(host, port) {
  try {
    await fetch(`http://${host.includes(':') ? `[${host}]` : host}:${port}/health`, { signal: AbortSignal.timeout(1000) });
    return true; // any answer means the port is served
  } catch {
    return false;
  }
}

/**
 * Restores [source] over [target]. Returns `{ safetyCopy, userVersion }`;
 * throws an Error with a Vietnamese message when a check fails.
 */
export async function restoreDatabase(source, target, { backupDir, openDatabase }) {
  if (!existsSync(source)) throw new Error(`Không thấy tệp ${source}.`);
  const check = checkDatabaseFile(source);
  if (!check.ok) throw new Error(`Tệp sao lưu không dùng được (${check.error}).`);
  if (check.userVersion > migrations.length) throw new Error('Tệp sao lưu từ phiên bản mã mới hơn. Cập nhật mã trước.');
  let safetyCopy = null;
  if (existsSync(target)) {
    safetyCopy = join(backupDir, `before-restore-${backupName().slice('clinic-'.length)}`);
    const current = new DatabaseSync(target);
    try {
      await backup(current, safetyCopy);
    } finally {
      current.close();
    }
  }
  for (const suffix of ['-wal', '-shm']) rmSync(target + suffix, { force: true });
  copyFileSync(source, target);
  const db = openDatabase(target); // runs pending migrations
  const userVersion = db.prepare('PRAGMA user_version').get().user_version;
  db.close();
  return { safetyCopy, userVersion };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { mkdirSync } = await import('node:fs');
  const { loadEnvFile, readConfig } = await import('../config.js');
  const { openDatabase } = await import('../db/index.js');
  loadEnvFile();
  const config = readConfig();
  const arg = process.argv[2];
  const fail = (message) => {
    console.error(JSON.stringify({ event: 'restore', result: 'refused', message }));
    process.exit(1);
  };
  if (!arg) fail('Cách dùng: npm run restore -- <tệp sao lưu>');
  const source = isAbsolute(arg) || arg.includes('/') || arg.includes('\\') ? resolve(arg) : join(config.backupDir, basename(arg));
  if (await serverRunning(config.host, config.port)) fail(`Server đang chạy ở ${config.host}:${config.port}. Dừng server rồi chạy lại.`);
  mkdirSync(config.backupDir, { recursive: true });
  try {
    const r = await restoreDatabase(source, config.clinicDb, { backupDir: config.backupDir, openDatabase });
    console.log(JSON.stringify({ event: 'restore', result: 'ok', from: source, to: config.clinicDb, ...r }));
  } catch (error) {
    fail(error.message);
  }
}
