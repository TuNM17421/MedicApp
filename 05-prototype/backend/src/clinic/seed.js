// Demo data for the doctor web: the clinic, one doctor and the six people of
// the approved click-through prototype (web-bac-si/src/data/mock-patients.js),
// with every date moved relative to the seed day so the demo always works.
//
//   npm run seed                  -> data/clinic.db, today in Asia/Ho_Chi_Minh
//   SEED_TODAY=2026-11-19 npm run seed
//   SEED_CLAIM_CODE=K7MQ-4XR2-9D npm run seed   (fixed claim code for p1)
//
// Each person gets the demo phone '0912' + their code (bước 16 sign-in);
// with DEMO_OTP=000000 in .env the server's sign-in code is fixed too.
// The admin quantri@anbinh.test has the same DEMO_PASSWORD (bước 18).
//
// Dev only. The file is deleted and recreated.
import { existsSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { transaction } from '../db/index.js';
import { hashPassword } from './auth.js';
import { formatClaimCode, newClaimCode, normalizeClaimCode } from './prescription.js';
import { addDays, at, minusYears, parseDay, today as clinicToday } from './time.js';

export const DEMO_EMAIL = 'bs.ha@anbinh.test';
export const DEMO_PASSWORD = 'medicapp-demo';
export const CLINIC_ID = 'c-anbinh';
export const DOCTOR_ID = 'pr-ha';
// Bước 18: the clinic's admin creates and locks doctor accounts; no charts.
export const ADMIN_EMAIL = 'quantri@anbinh.test';
export const ADMIN_ID = 'pr-admin';

// The prototype's TODAY: its "dd/mm" labels are read as offsets from it.
const PROTO_TODAY = '2026-11-19';
const HISTORY_OFFSET = -30; // prototype history visit 2026-10-20
// 06:30 so the morning (07:00) dose of the first day is due under the
// medic_core rule (doses before prescribedAt on day one do not count).
const HISTORY_TIME = '06:30';

const REASONS = { 'Quên uống': 'forgot', 'Thấy khó chịu': 'unwell', 'Hết thuốc': 'outOfStock', 'Lý do khác': 'other' };

// Prototype doseLog(): the recorded time of day i for a slot hour.
function protoTime(i, slotHour) {
  const mins = (i * 37 + slotHour * 11) % 75;
  return `${String(slotHour + Math.floor(mins / 60)).padStart(2, '0')}:${String(mins % 60).padStart(2, '0')}`;
}

const item = (name, strength, quantity, slot, days, { meal = 'any', note = '' } = {}) => ({
  name, strength, form: 'viên', quantity, route: 'Uống', doses: [{ slot, amount: 1 }], meal, days, note,
});

const PATIENTS = [
  {
    id: 'p1', code: '000317', time: '08:00', name: 'Trần Văn Minh', age: 52, sex: 'Nam', kind: 'Khám BHYT', specialty: 'Nội tổng hợp',
    insurance: 'DN4010120003921', allergy: 'Không ghi nhận', status: 'done', consent: { at: [-1, '20:15'] },
    conditions: ['Tăng huyết áp (I10)'], birthOffset: 143,
    summary: {
      chief: { text: 'Tái khám tăng huyết áp. Huyết áp đo ở nhà sáng nay 138/86.', src: [['Lúc đặt lịch, 12/11', '“Tái khám huyết áp, sáng nay đo 138 trên 86.”']] },
      course: { text: 'Không đau đầu, không chóng mặt.', src: [['Câu hỏi trước khám, 18/11', '“Không đau đầu, không chóng mặt gì.”']] },
      questions: { text: 'Có thể giảm liều thuốc huyết áp không?', src: [['Câu hỏi trước khám, 18/11', '“Có giảm thuốc được không bác sĩ.”']] },
    },
    history: {
      diagnosis: [['I10', 'Tăng huyết áp vô căn']],
      items: [item('Amlodipin', '5mg', 30, 'morning', 30)],
      advice: 'Ăn nhạt, đo huyết áp mỗi sáng.',
      logs: [{ slotHour: 6, missed: { 14: 'Quên uống' } }],
    },
    result: {
      time: '08:24', diagnosis: [['I10', 'Tăng huyết áp vô căn']],
      items: [item('Amlodipin', '5mg', 28, 'morning', 28)],
      advice: 'Giữ liều hiện tại. Ăn nhạt, đo huyết áp mỗi sáng và ghi lại.', followUpOffset: 28,
    },
  },
  {
    id: 'p2', code: '000482', time: '08:30', name: 'Phạm Thị Lan', age: 78, sex: 'Nữ', kind: 'Khám dịch vụ', specialty: 'Nội tổng hợp',
    insurance: '', allergy: 'Không ghi nhận', status: 'arrived', consent: { at: [0, '07:42'] },
    address: 'Số 8 ngõ 25 phố Hoa Sữa, phường An Phú', weight: 52,
    conditions: ['Gút (M10)', 'Rối loạn lipid máu (E78)'], birthOffset: 61,
    summary: {
      chief: { text: 'Đau khớp gối phải khoảng 1 tuần, sưng về đêm.', src: [['Lúc đặt lịch, 17/11', '“Dạo này cái gối bên phải đau quá, tối nằm thấy sưng lên, cũng được tuần rồi.”']] },
      course: {
        text: 'Đau tăng trong 2 ngày gần đây, đi lại khó hơn. Đã tự uống paracetamol, đỡ ít.',
        src: [['Câu hỏi trước khám, 18/11 · Nặng hơn hay nhẹ hơn?', '“Hai hôm nay đau hơn, đi chợ phải nghỉ mấy lần.”'], ['Câu hỏi trước khám, 18/11 · Đã tự dùng thuốc gì?', '“Có uống panadol, đỡ được chút.”']],
      },
      questions: {
        text: 'Có phải uống thuốc mỡ máu suốt đời không? Đau gối có phải do gút không?',
        src: [['Câu hỏi trước khám, 18/11 · Muốn hỏi bác sĩ điều gì?', '“Thuốc mỡ máu có phải uống mãi không, với cái gối này có phải do gút không.”']],
      },
    },
    selfMeds: [{ name: 'Paracetamol 500mg', how: '1 viên khi đau, khoảng 2 lần/ngày trong 2 ngày qua' }],
    history: {
      diagnosis: [['M10', 'Gút'], ['E78', 'Rối loạn lipid máu']],
      items: [
        item('Allopurinol', '300mg', 30, 'morning', 30, { meal: 'after', note: 'Uống nhiều nước trong ngày' }),
        item('Atorvastatin', '10mg', 30, 'evening', 30),
      ],
      advice: 'Uống đủ 2 lít nước mỗi ngày; hạn chế nội tạng, hải sản và bia rượu. Hạn chế mỡ động vật và đồ chiên rán.',
      logs: [
        { slotHour: 7, missed: { 9: 'Quên uống', 20: 'Quên uống', 27: 'Quên uống' } },
        { slotHour: 20, missed: { 3: 'Quên uống', 7: 'Quên uống', 9: 'Lý do khác', 11: 'Quên uống', 13: 'Quên uống', 16: 'Thấy khó chịu',
          18: 'Thấy khó chịu', 19: 'Quên uống', 21: 'Thấy khó chịu', 22: 'Thấy khó chịu', 24: 'Quên uống', 26: 'Thấy khó chịu' } },
      ],
    },
  },
  {
    id: 'p3', code: '000455', time: '09:00', name: 'Phạm Văn Hòa', age: 49, sex: 'Nam', kind: 'Khám dịch vụ', specialty: 'Nội tổng hợp',
    insurance: '', allergy: 'Chưa có thông tin', status: 'arrived', consent: { declined: true, at: [-1, '18:40'] }, birthOffset: 212,
  },
  {
    id: 'p4', code: '000501', time: '09:30', name: 'Lê Thị Mai', age: 34, sex: 'Nữ', kind: 'Khám BHYT', specialty: 'Nội tổng hợp',
    insurance: 'GD4797932107716', allergy: 'Penicilin (người bệnh khai)', status: 'booked', consent: { at: [-1, '21:10'] }, birthOffset: 25,
    flag: { text: 'Có lúc leo cầu thang thấy tức ngực, ngồi nghỉ thì hết.', section: 'course' },
    summary: {
      chief: { text: 'Hay mệt và hơi khó thở khi gắng sức, khoảng 3 tuần nay.', src: [['Lúc đặt lịch, 16/11', '“Dạo này em hay mệt, leo cầu thang là thở dốc, chắc 3 tuần rồi.”']] },
      course: { text: 'Không sốt. Thỉnh thoảng tức ngực khi leo cầu thang, nghỉ thì hết.', src: [['Câu hỏi trước khám, 18/11', '“Không sốt ạ. Có lúc leo cầu thang thấy tức ngực, ngồi nghỉ thì hết.”']] },
      questions: { text: 'Có cần làm xét nghiệm máu không?', src: [['Câu hỏi trước khám, 18/11', '“Em có cần thử máu không ạ.”']] },
    },
  },
  {
    id: 'p5', code: '000233', time: '10:00', name: 'Đỗ Văn Tùng', age: 61, sex: 'Nam', kind: 'Khám BHYT', specialty: 'Nội tổng hợp',
    insurance: 'HT2010120010458', allergy: 'Chưa có thông tin', status: 'booked', consent: null, birthOffset: 300,
  },
  {
    id: 'p6', code: '000519', time: '10:30', name: 'Vũ Thị Hạnh', age: 45, sex: 'Nữ', kind: 'Khám dịch vụ', specialty: 'Nội tổng hợp',
    insurance: '', allergy: 'Không ghi nhận', status: 'booked', consent: { at: [-1, '19:05'] }, birthOffset: 97,
    summary: {
      chief: { text: 'Đau vùng thượng vị sau ăn, kèm ợ chua, khoảng 2 tháng.', src: [['Lúc đặt lịch, 15/11', '“Ăn xong là đau bụng trên rốn, hay ợ chua, cũng 2 tháng nay.”']] },
      course: { text: 'Đau nhiều hơn khi ăn cay hoặc uống cà phê. Đã tự mua thuốc dạ dày uống 1 tuần.', src: [['Câu hỏi trước khám, 18/11', '“Ăn cay với cà phê là đau hơn. Có ra hiệu thuốc mua thuốc dạ dày uống 1 tuần.”']] },
      questions: { text: 'Có cần nội soi không?', src: [['Câu hỏi trước khám, 18/11', '“Chị có phải nội soi không bác sĩ.”']] },
    },
    selfMeds: [{ name: 'Thuốc dạ dày (không rõ tên)', how: 'Tự mua ở hiệu thuốc, đã dùng 1 tuần' }],
  },
];

const unquote = (s) => s.replace(/^[“"]\s*|\s*[”"]$/g, '');

/** "Câu hỏi trước khám, 18/11 · Đã tự dùng thuốc gì?" -> channel, day offset, question. */
function parseSource(label) {
  const [head, question = ''] = label.split(' · ');
  const [, dd, mm] = head.match(/(\d{2})\/(\d{2})/);
  const offset = Math.round((Date.parse(`2026-${mm}-${dd}T00:00:00Z`) - Date.parse(`${PROTO_TODAY}T00:00:00Z`)) / 86_400_000);
  return { channel: head.startsWith('Lúc đặt lịch') ? 'booking' : 'pre_visit', offset, question: question.trim() };
}

const compact = (day) => day.replaceAll('-', '');

/** Demo phone of a seeded person, e.g. Phạm Thị Lan (000482) -> 0912000482. */
export const demoPhone = (code) => `0912${code}`;

/**
 * Writes the demo data into [db] (already migrated, empty). Dates are
 * relative to [today] ("yyyy-MM-dd", clinic time). Returns the ids tests need.
 */
export async function seedClinic(db, { today = clinicToday(), password = DEMO_PASSWORD, claimCode = null } = {}) {
  if (!parseDay(today)) throw new Error('SEED_TODAY phải có dạng yyyy-MM-dd.');
  const p1Claim = claimCode ? normalizeClaimCode(claimCode) : newClaimCode();
  if (!p1Claim) throw new Error('SEED_CLAIM_CODE phải gồm 10 ký tự Crockford base32, ví dụ K7MQ-4XR2-9D.');
  const passwordHash = await hashPassword(password);
  const historyDay = addDays(today, HISTORY_OFFSET);
  const ids = { claimCodes: {}, phones: {}, clinicId: CLINIC_ID, doctorId: DOCTOR_ID, adminId: ADMIN_ID, today, historyDay, appointments: {}, historyAppointments: {}, summaries: {} };

  transaction(db, () => {
    const run = (sql, ...args) => db.prepare(sql).run(...args);
    run('INSERT INTO clinic (id, name, phone, address) VALUES (?, ?, ?, ?)', CLINIC_ID, 'Phòng khám Đa khoa An Bình', '0900 000 000', '');
    run(`INSERT INTO practitioner (id, clinic_id, full_name, title, role, email, password_hash, created_at)
      VALUES (?, ?, ?, 'BS.', 'doctor', ?, ?, ?)`, DOCTOR_ID, CLINIC_ID, 'Nguyễn Thu Hà', DEMO_EMAIL, passwordHash, at(addDays(today, -365), '08:00'));
    run(`INSERT INTO practitioner (id, clinic_id, full_name, title, role, email, password_hash, created_at)
      VALUES (?, ?, ?, '', 'admin', ?, ?, ?)`, ADMIN_ID, CLINIC_ID, 'Quản trị An Bình', ADMIN_EMAIL, passwordHash, at(addDays(today, -365), '08:00'));

    const appointment = (id, patientId, startsAt, p, status) => run(
      `INSERT INTO appointment (id, clinic_id, patient_id, practitioner_id, starts_at, specialty, kind, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, id, CLINIC_ID, patientId, DOCTOR_ID, startsAt, p.specialty, p.kind, status);
    const result = (apptId, version, signedAt, r, followUp) => run(
      `INSERT INTO visit_result (id, appointment_id, version, status, diagnosis, items, advice, follow_up_date, signed_by, signed_at, updated_at)
       VALUES (?, ?, ?, 'sent', ?, ?, ?, ?, ?, ?, ?)`,
      `r-${apptId}-v${version}`, apptId, version, JSON.stringify(r.diagnosis), JSON.stringify(r.items), r.advice, followUp,
      DOCTOR_ID, signedAt, signedAt);

    for (const p of PATIENTS) {
      const birthDate = minusYears(addDays(today, -p.birthOffset), p.age);
      ids.phones[p.id] = demoPhone(p.code);
      run(`INSERT INTO patient (id, clinic_id, code, full_name, birth_date, gender, address, weight_kg, insurance_code, allergy, conditions, phone)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, p.id, CLINIC_ID, p.code, p.name, birthDate, p.sex, p.address ?? '',
      p.weight ?? null, p.insurance, p.allergy, JSON.stringify(p.conditions ?? []), ids.phones[p.id]);

      // Visit 30 days ago: its sent result is the source of the courses.
      if (p.history) {
        const hId = `a-${p.id}-${compact(historyDay)}`;
        const prescribedAt = at(historyDay, HISTORY_TIME);
        ids.historyAppointments[p.id] = hId;
        appointment(hId, p.id, prescribedAt, p, 'done');
        result(hId, 1, prescribedAt, p.history, today);
        p.history.items.forEach((it, index) => {
          const courseId = `${hId}#${index + 1}`;
          run('INSERT INTO med_course (id, patient_id, item, prescribed_at) VALUES (?, ?, ?, ?)', courseId, p.id, JSON.stringify(it), prescribedAt);
          const { slotHour, missed } = p.history.logs[index];
          const slot = it.doses[0].slot;
          for (let i = 0; i < 30; i++) {
            const day = addDays(historyDay, i);
            const time = protoTime(i, slotHour);
            if (missed[i]) {
              // Skipped from the reminder shortly after the slot time.
              const skipAt = slot === 'morning' ? '07:20' : '19:25';
              run(`INSERT INTO dose_event (patient_id, course_id, day, slot, mark, reason, recorded_at)
                VALUES (?, ?, ?, ?, 'skipped', ?, ?)`, p.id, courseId, day, slot, REASONS[missed[i]], at(day, skipAt));
            } else {
              run(`INSERT INTO dose_event (patient_id, course_id, day, slot, mark, reason, recorded_at)
                VALUES (?, ?, ?, ?, 'taken', NULL, ?)`, p.id, courseId, day, slot, at(day, time));
            }
          }
        });
      }

      const aId = `a-${p.id}-${compact(today)}`;
      ids.appointments[p.id] = aId;
      appointment(aId, p.id, at(today, p.time), p, p.status);

      if (p.consent) {
        const grantedAt = at(addDays(today, p.consent.at[0]), p.consent.at[1]);
        run(`INSERT INTO consent (id, appointment_id, scope, wording_version, granted_at, expires_at, revoked_at)
          VALUES (?, ?, ?, 1, ?, ?, ?)`, `cs-${aId}`, aId,
        JSON.stringify(p.consent.declined ? [] : ['intake', 'dose_log', 'self_meds']),
        grantedAt, at(addDays(today, 30), '23:59'), p.consent.declined ? grantedAt : null);
      }

      if (p.summary) {
        let n = 0;
        const sections = [];
        const sourceOf = {};
        for (const [key, s] of Object.entries(p.summary)) {
          const sources = s.src.map(([label, quote], k) => {
            const src = parseSource(label);
            const id = `i-${p.id}-${++n}`;
            const hhmm = src.channel === 'booking' ? `19:${String(10 + k).padStart(2, '0')}` : `20:${String(5 * n).padStart(2, '0')}`;
            run(`INSERT INTO intake_answer (id, appointment_id, channel, question, answer, answered_at)
              VALUES (?, ?, ?, ?, ?, ?)`, id, aId, src.channel, src.question, unquote(quote), at(addDays(today, src.offset), hhmm));
            return id;
          });
          sourceOf[key] = sources;
          sections.push({ key, text: s.text, sources });
        }
        const flags = p.flag ? [{ text: p.flag.text, sources: sourceOf[p.flag.section] }] : [];
        const created = at(addDays(today, p.consent.at[0]), p.consent.at[1]).replace(/:00\+/, ':30+');
        const sId = `s-${aId}`;
        ids.summaries[p.id] = sId;
        run(`INSERT INTO visit_summary (id, appointment_id, sections, flags, mode, model, prompt_version, created_at)
          VALUES (?, ?, ?, ?, 'mock', '', 'seed', ?)`, sId, aId, JSON.stringify(sections), JSON.stringify(flags), created);
      }

      for (const [k, m] of (p.selfMeds ?? []).entries()) {
        run('INSERT INTO self_medication (id, appointment_id, name, how) VALUES (?, ?, ?, ?)', `sm-${aId}-${k + 1}`, aId, m.name, m.how);
      }

      if (p.result) {
        result(aId, 1, at(today, p.result.time), p.result, addDays(today, p.result.followUpOffset));
        // Claim code of the sent result, valid 30 days from sending.
        run('UPDATE appointment SET claim_code = ?, claim_expires_at = ? WHERE id = ?', p1Claim, at(addDays(today, 30), p.result.time), aId);
        ids.claimCodes[p.id] = formatClaimCode(p1Claim);
        run(`INSERT INTO med_course (id, patient_id, item, prescribed_at) VALUES (?, ?, ?, ?)`,
          `${aId}#1`, p.id, JSON.stringify(p.result.items[0]), at(today, p.result.time));
      }
    }
  });
  return ids;
}

// ---- CLI -----------------------------------------------------------------

/** Only files under backend/data or the system temp folder may be replaced. */
export function assertSeedPath(path, backendDir) {
  const target = resolve(path);
  const real = (p) => (existsSync(p) ? realpathSync(p) : resolve(p));
  const dir = real(dirname(target));
  const allowed = [real(resolve(backendDir, 'data')), real(tmpdir())];
  if (!allowed.some((root) => dir === root || dir.startsWith(root + sep))) {
    throw new Error('Seed chỉ ghi vào backend/data hoặc thư mục tạm.');
  }
  return target;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { backendDir, loadEnvFile, readConfig } = await import('../config.js');
  const { openDatabase } = await import('../db/index.js');
  loadEnvFile();
  const config = readConfig();
  const path = assertSeedPath(config.clinicDb, backendDir);
  for (const suffix of ['', '-wal', '-shm']) rmSync(path + suffix, { force: true });
  const db = openDatabase(path);
  const today = (process.env.SEED_TODAY ?? '').trim() || clinicToday();
  const password = process.env.DEMO_PASSWORD || DEMO_PASSWORD;
  const ids = await seedClinic(db, { today, password, claimCode: (process.env.SEED_CLAIM_CODE ?? '').trim() || null });
  db.close();
  // Demo data only: the claim code and the phones are printed for the app demo.
  console.log(JSON.stringify({
    event: 'seeded', today, email: DEMO_EMAIL, adminEmail: ADMIN_EMAIL, patients: PATIENTS.length, claimCodeP1: ids.claimCodes.p1,
    patientPhones: Object.fromEntries(PATIENTS.map((p) => [p.code, ids.phones[p.id]])),
    demoOtp: config.demoOtp ?? (config.patientOtpMode === 'dev' ? 'devCode (random, in the server log)' : 'off'),
  }));
}
