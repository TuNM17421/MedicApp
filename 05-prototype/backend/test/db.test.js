import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { migrate, openDatabase, transaction } from '../src/db/index.js';
import { migrations } from '../src/db/migrations.js';

const tables = (db) =>
  db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all().map((r) => r.name);

test('tạo đủ bảng theo plan và ghi phiên bản schema', () => {
  const db = openDatabase();
  assert.deepEqual(tables(db), [
    'appointment', 'audit_event', 'clinic', 'consent', 'dose_event', 'intake_answer', 'med_course',
    'patient', 'practitioner', 'self_medication', 'visit_result', 'visit_summary',
  ]);
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, migrations.length);
});

test('mở lại file không chạy lại migration', () => {
  const dir = mkdtempSync(join(tmpdir(), 'medicapp-db-'));
  try {
    const path = join(dir, 'clinic.db');
    openDatabase(path).close();
    const db = openDatabase(path);
    assert.equal(migrate(db), migrations.length);
    db.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('khóa ngoại và ràng buộc trạng thái có hiệu lực', () => {
  const db = openDatabase();
  assert.throws(() =>
    db.prepare("INSERT INTO appointment (id, clinic_id, patient_id, starts_at, status) VALUES ('a', 'x', 'y', '2026-11-19T08:30', 'booked')").run(),
  /FOREIGN KEY/);
  db.prepare("INSERT INTO clinic (id, name) VALUES ('c1', 'Phòng khám Đa khoa An Bình')").run();
  db.prepare(`INSERT INTO patient (id, clinic_id, code, full_name, birth_date, gender)
    VALUES ('p2', 'c1', '000482', 'Phạm Thị Lan', '1948-03-02', 'Nữ')`).run();
  assert.throws(() =>
    db.prepare("INSERT INTO appointment (id, clinic_id, patient_id, starts_at, status) VALUES ('a', 'c1', 'p2', '2026-11-19T08:30', 'lost')").run(),
  /CHECK/);
});

test('một lượt nhật ký thuốc chỉ có một dòng mỗi liều', () => {
  const db = openDatabase();
  db.prepare("INSERT INTO clinic (id, name) VALUES ('c1', 'PK')").run();
  db.prepare("INSERT INTO patient (id, clinic_id, code, full_name, birth_date, gender) VALUES ('p2', 'c1', '1', 'Lan', '1948-03-02', 'Nữ')").run();
  const upsert = db.prepare(`INSERT INTO dose_event (patient_id, course_id, day, slot, mark, reason, recorded_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (patient_id, course_id, day, slot) DO UPDATE SET mark = excluded.mark, reason = excluded.reason, recorded_at = excluded.recorded_at`);
  transaction(db, () => {
    upsert.run('p2', 'v1#2', '2026-11-05', 'evening', 'skipped', 'unwell', '2026-11-05T20:10:00');
    upsert.run('p2', 'v1#2', '2026-11-05', 'evening', 'taken', null, '2026-11-05T21:00:00');
  });
  assert.deepEqual({ ...db.prepare('SELECT mark, reason FROM dose_event').get() }, { mark: 'taken', reason: null });
  assert.equal(db.prepare('SELECT count(*) n FROM dose_event').get().n, 1);
});

test('giao dịch lỗi được hoàn tác', () => {
  const db = openDatabase();
  assert.throws(() => transaction(db, () => {
    db.prepare("INSERT INTO clinic (id, name) VALUES ('c1', 'PK')").run();
    throw new Error('stop');
  }), /stop/);
  assert.equal(db.prepare('SELECT count(*) n FROM clinic').get().n, 0);
});
