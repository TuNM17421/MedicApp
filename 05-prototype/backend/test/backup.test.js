import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { existsSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { after, before, test } from 'node:test';

import { seedClinic } from '../src/clinic/seed.js';
import { openDatabase } from '../src/db/index.js';
import { migrations } from '../src/db/migrations.js';
import {
  backupDatabase, backupName, checkDatabaseFile, listBackups, msUntilHour, scheduleBackups,
} from '../src/ops/backup.js';
import { restoreDatabase, serverRunning } from '../src/ops/restore.js';
import { config } from './helpers.js';

const HOUR = 3_600_000;
let tmp;
let db;
let dbPath;

before(async () => {
  tmp = mkdtempSync(join(tmpdir(), 'medicapp-backup-'));
  dbPath = join(tmp, 'clinic.db');
  db = openDatabase(dbPath);
  await seedClinic(db, { today: '2026-10-16' });
});
after(() => {
  db.close();
  rmSync(tmp, { recursive: true, force: true });
});

const count = (path, table) => {
  const d = new DatabaseSync(path, { readOnly: true });
  try {
    return d.prepare(`SELECT count(*) AS n FROM ${table}`).get().n;
  } finally {
    d.close();
  }
};

test('tên tệp theo giờ phòng khám, giờ chạy kế tiếp', () => {
  // 2026-10-15T19:00:00Z is 02:00 on 16/10 in Việt Nam.
  assert.equal(backupName(Date.parse('2026-10-15T19:00:00Z')), 'clinic-20261016-020000.db');
  const at = (iso) => Date.parse(iso);
  assert.equal(msUntilHour(2, at('2026-10-16T01:00:00+07:00')), HOUR);
  assert.equal(msUntilHour(2, at('2026-10-16T02:00:00+07:00')), 24 * HOUR);
  assert.equal(msUntilHour(2, at('2026-10-16T23:30:00+07:00')), 2.5 * HOUR);
  assert.equal(msUntilHour(0, at('2026-10-16T00:00:01+07:00')), 24 * HOUR - 1000);
});

test('sao lưu khi đang mở, kiểm tra được, giữ N bản mới nhất', async () => {
  const dir = join(tmp, 'backups');
  const start = Date.parse('2026-10-01T02:00:00+07:00');
  let last;
  for (let i = 0; i < 5; i++) last = await backupDatabase(db, dir, { keep: 3, now: start + i * 24 * HOUR });
  assert.equal(last.name, 'clinic-20261005-020000.db');
  assert.ok(last.bytes > 0);
  assert.deepEqual(last.removed, ['clinic-20261002-020000.db']);
  assert.deepEqual(listBackups(dir), ['clinic-20261005-020000.db', 'clinic-20261004-020000.db', 'clinic-20261003-020000.db']);
  assert.ok(!readdirSync(dir).some((n) => n.endsWith('.partial')));
  const check = checkDatabaseFile(last.file);
  assert.deepEqual(check, { ok: true, userVersion: migrations.length, error: null });
  assert.equal(count(last.file, 'patient'), count(dbPath, 'patient'));
  assert.equal(count(last.file, 'practitioner'), 2);
  // Other files in the folder are never touched.
  writeFileSync(join(dir, 'ghi-chu.txt'), 'x');
  await backupDatabase(db, dir, { keep: 1, now: start + 9 * 24 * HOUR });
  assert.deepEqual(readdirSync(dir).sort(), ['clinic-20261010-020000.db', 'ghi-chu.txt']);
});

test('lịch chạy trong server: ghi log kết quả, lỗi không làm dừng server', async () => {
  const events = [];
  const log = (event, fields) => events.push({ event, ...fields });
  const ok = scheduleBackups({ db, log, config: { backupDir: join(tmp, 'daily'), backupKeep: 14, backupHour: 2 } });
  const r = await ok.run();
  ok.stop();
  assert.ok(existsSync(r.file));
  assert.deepEqual(events[0], { event: 'backup_scheduled', hour: 2, keep: 14 });
  assert.equal(events[1].event, 'backup');
  assert.equal(events[1].result, 'ok');
  assert.match(events[1].name, /^clinic-\d{8}-\d{6}\.db$/);
  assert.ok(!JSON.stringify(events).includes(tmp)); // names only, no paths

  writeFileSync(join(tmp, 'not-a-dir'), 'x');
  const bad = scheduleBackups({ db, log, config: { backupDir: join(tmp, 'not-a-dir'), backupKeep: 14, backupHour: 2 } });
  assert.equal(await bad.run(), null);
  bad.stop();
  assert.equal(events.at(-1).result, 'failed');
  assert.ok(events.at(-1).code);
});

test('phục hồi: kiểm tra tệp, sao lại bản hiện tại trước khi thay, chạy migration', async () => {
  const dir = join(tmp, 'restore');
  const target = join(tmp, 'restore-target.db');
  const live = openDatabase(target);
  await seedClinic(live, { today: '2026-10-16' });
  const { file } = await backupDatabase(live, dir, { keep: 14 });
  live.exec("DELETE FROM self_medication; DELETE FROM audit_event; UPDATE patient SET full_name = 'Đã sửa nhầm'");
  live.close();

  const r = await restoreDatabase(file, target, { backupDir: dir, openDatabase });
  assert.equal(r.userVersion, migrations.length);
  assert.match(r.safetyCopy, /before-restore-\d{8}-\d{6}\.db$/);
  const back = new DatabaseSync(target, { readOnly: true });
  assert.equal(back.prepare("SELECT full_name FROM patient WHERE id = 'p2'").get().full_name, 'Phạm Thị Lan');
  back.close();
  assert.equal(count(r.safetyCopy, 'self_medication'), 0); // the replaced state is kept
  assert.ok(!listBackups(dir).some((n) => n.startsWith('before-restore')));

  writeFileSync(join(tmp, 'rac.db'), 'không phải sqlite');
  await assert.rejects(restoreDatabase(join(tmp, 'rac.db'), target, { backupDir: dir, openDatabase }), /không dùng được/);
  await assert.rejects(restoreDatabase(join(tmp, 'khong-co.db'), target, { backupDir: dir, openDatabase }), /Không thấy/);
  const other = join(tmp, 'other.db');
  new DatabaseSync(other).exec('CREATE TABLE x (a)');
  await assert.rejects(restoreDatabase(other, target, { backupDir: dir, openDatabase }), /not_clinic_db/);
  const newer = join(tmp, 'newer.db');
  const n = openDatabase(newer);
  n.exec(`PRAGMA user_version = ${migrations.length + 1}`);
  n.close();
  await assert.rejects(restoreDatabase(newer, target, { backupDir: dir, openDatabase }), /mới hơn/);
});

test('phục hồi từ chối khi server đang chạy', async () => {
  const s = createServer((req, res) => res.end('ok'));
  await new Promise((r) => s.listen(0, '127.0.0.1', r));
  const { port } = s.address();
  assert.equal(await serverRunning('127.0.0.1', port), true);
  await new Promise((r) => s.close(r));
  assert.equal(await serverRunning('127.0.0.1', port), false);
});

test('cấu hình sao lưu', () => {
  const c = config();
  assert.equal(c.backupEnabled, true);
  assert.equal(c.backupKeep, 14);
  assert.equal(c.backupHour, 2);
  assert.match(c.backupDir, /data[\\/]backups$/);
  const d = config({ BACKUP_ENABLED: '0', BACKUP_KEEP: '30', BACKUP_HOUR: '23', BACKUP_DIR: '/srv/sao-luu' });
  assert.deepEqual([d.backupEnabled, d.backupKeep, d.backupHour, d.backupDir], [false, 30, 23, '/srv/sao-luu']);
  assert.throws(() => config({ BACKUP_HOUR: '24' }), /BACKUP_HOUR/);
  assert.throws(() => config({ BACKUP_KEEP: '0' }), /BACKUP_KEEP/);
  assert.throws(() => config({ BACKUP_ENABLED: 'có' }), /BACKUP_ENABLED/);
});
