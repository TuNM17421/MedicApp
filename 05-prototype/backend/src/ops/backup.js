// Bước 18: daily backup of the clinic database with node:sqlite's online
// backup (safe while the server writes; WAL included). Files are
// BACKUP_DIR/clinic-yyyyMMdd-HHmmss.db in clinic time; only the newest
// BACKUP_KEEP of them are kept. Each copy is checked (PRAGMA quick_check)
// before it gets its final name, so a half-written file is never kept.
//
//   npm run backup          one backup now (cron, or before an update)
//
// The server also runs one every day at BACKUP_HOUR (BACKUP_ENABLED=1).
import { mkdirSync, readdirSync, renameSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync, backup } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

import { localIso } from '../clinic/time.js';

export const BACKUP_FILE = /^clinic-\d{8}-\d{6}\.db$/;
const DAY_MS = 86_400_000;

/** 'clinic-20261016-020000.db' for [ms] in clinic time. */
export function backupName(ms = Date.now()) {
  const t = localIso(ms);
  return `clinic-${t.slice(0, 10).replaceAll('-', '')}-${t.slice(11, 19).replaceAll(':', '')}.db`;
}

/** Backup files in [dir], newest first. */
export function listBackups(dir) {
  let names;
  try {
    names = readdirSync(dir);
  } catch {
    return [];
  }
  return names.filter((n) => BACKUP_FILE.test(n)).sort().reverse();
}

/**
 * Opens [path] read-only and checks it: `{ ok, userVersion, error }`. A
 * clinic database has the practitioner table and passes quick_check.
 */
export function checkDatabaseFile(path) {
  let db;
  try {
    db = new DatabaseSync(path, { readOnly: true });
    const check = db.prepare('PRAGMA quick_check').get().quick_check;
    const userVersion = db.prepare('PRAGMA user_version').get().user_version;
    const clinic = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'practitioner'").get();
    if (check !== 'ok') return { ok: false, userVersion, error: 'quick_check' };
    if (!clinic) return { ok: false, userVersion, error: 'not_clinic_db' };
    return { ok: true, userVersion, error: null };
  } catch (error) {
    return { ok: false, userVersion: null, error: error.code ?? 'unreadable' };
  } finally {
    db?.close();
  }
}

/** Deletes all but the newest [keep] backups in [dir]; returns the names removed. */
export function pruneBackups(dir, keep) {
  const removed = listBackups(dir).slice(keep);
  for (const name of removed) rmSync(join(dir, name), { force: true });
  return removed;
}

/**
 * Copies the open database [db] to [dir]. Returns `{ file, name, bytes,
 * removed }`; throws when the copy fails its check (nothing is kept then).
 */
export async function backupDatabase(db, dir, { keep = 14, now = Date.now() } = {}) {
  mkdirSync(dir, { recursive: true });
  const name = backupName(now);
  const file = join(dir, name);
  const partial = `${file}.partial`;
  const clean = (path) => ['', '-wal', '-shm', '-journal'].forEach((x) => rmSync(path + x, { force: true }));
  clean(partial);
  try {
    await backup(db, partial);
    // One self-contained file: the copy keeps the source's WAL mode otherwise.
    const copy = new DatabaseSync(partial);
    copy.exec('PRAGMA journal_mode = DELETE');
    copy.close();
    const check = checkDatabaseFile(partial);
    if (!check.ok) throw Object.assign(new Error('Bản sao lưu không đọc được.'), { code: check.error });
    renameSync(partial, file);
  } finally {
    clean(partial);
  }
  return { file, name, bytes: statSync(file).size, removed: pruneBackups(dir, keep) };
}

/** Milliseconds from [now] to the next [hour]:00 clinic time (never 0). */
export function msUntilHour(hour, now = Date.now()) {
  const local = localIso(now);
  let next = Date.parse(`${local.slice(0, 10)}T${String(hour).padStart(2, '0')}:00:00+07:00`);
  while (next <= now) next += DAY_MS;
  return next - now;
}

/**
 * Runs [backupDatabase] every day at config.backupHour in the server
 * process. Results go to the log as `backup` events (file name, size, how
 * many old files were removed, or the error code). Returns `{ run, stop }`.
 */
export function scheduleBackups({ db, config, log, now = () => Date.now() }) {
  let timer = null;
  let stopped = false;
  async function run() {
    const started = now();
    try {
      const r = await backupDatabase(db, config.backupDir, { keep: config.backupKeep, now: started });
      log('backup', { result: 'ok', name: r.name, bytes: r.bytes, removed: r.removed.length, ms: now() - started });
      return r;
    } catch (error) {
      log('backup', { result: 'failed', code: error.code ?? error.name });
      return null;
    }
  }
  function arm() {
    if (stopped) return;
    timer = setTimeout(async () => {
      await run();
      arm();
    }, msUntilHour(config.backupHour, now()));
    timer.unref();
  }
  arm();
  log('backup_scheduled', { hour: config.backupHour, keep: config.backupKeep });
  return {
    run,
    stop() {
      stopped = true;
      clearTimeout(timer);
    },
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { existsSync } = await import('node:fs');
  const { loadEnvFile, readConfig } = await import('../config.js');
  loadEnvFile();
  const config = readConfig();
  if (!existsSync(config.clinicDb)) {
    console.error(JSON.stringify({ event: 'backup', result: 'failed', code: 'no_database' }));
    process.exit(1);
  }
  const db = new DatabaseSync(config.clinicDb);
  try {
    const r = await backupDatabase(db, config.backupDir, { keep: config.backupKeep });
    console.log(JSON.stringify({ event: 'backup', result: 'ok', file: r.file, bytes: r.bytes, removed: r.removed }));
  } catch (error) {
    console.error(JSON.stringify({ event: 'backup', result: 'failed', code: error.code ?? error.name }));
    process.exitCode = 1;
  } finally {
    db.close();
  }
}
