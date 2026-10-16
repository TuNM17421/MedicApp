// Schema of the clinic database (doctor web and data shared from the app).
// Table names follow the matching FHIR resource so a later FHIR export maps
// one to one. SQL stays portable (TEXT ids, ISO-8601 text times, JSON as
// TEXT) so the pilot can move to PostgreSQL without rewriting it.
//
// Append new migrations; never edit one that has shipped.
export const migrations = [
  `
  CREATE TABLE clinic (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT NOT NULL DEFAULT '',
    address TEXT NOT NULL DEFAULT ''
  );

  CREATE TABLE practitioner (
    id TEXT PRIMARY KEY,
    clinic_id TEXT NOT NULL REFERENCES clinic(id),
    full_name TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT 'BS.',
    license_no TEXT NOT NULL DEFAULT '',
    role TEXT NOT NULL CHECK (role IN ('doctor', 'admin')),
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    failed_logins INTEGER NOT NULL DEFAULT 0,
    locked_until TEXT,
    created_at TEXT NOT NULL
  );

  -- profile_id is the person's profile id in the app; set once the app
  -- account is linked to the clinic.
  CREATE TABLE patient (
    id TEXT PRIMARY KEY,
    clinic_id TEXT NOT NULL REFERENCES clinic(id),
    profile_id TEXT,
    code TEXT NOT NULL,
    full_name TEXT NOT NULL,
    birth_date TEXT NOT NULL,
    gender TEXT NOT NULL CHECK (gender IN ('Nam', 'Nữ')),
    address TEXT NOT NULL DEFAULT '',
    weight_kg REAL,
    insurance_code TEXT NOT NULL DEFAULT '',
    allergy TEXT NOT NULL DEFAULT '',
    conditions TEXT NOT NULL DEFAULT '[]',
    UNIQUE (clinic_id, code)
  );

  CREATE TABLE appointment (
    id TEXT PRIMARY KEY,
    clinic_id TEXT NOT NULL REFERENCES clinic(id),
    patient_id TEXT NOT NULL REFERENCES patient(id),
    practitioner_id TEXT REFERENCES practitioner(id),
    starts_at TEXT NOT NULL,
    specialty TEXT NOT NULL DEFAULT '',
    kind TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL CHECK (status IN ('booked', 'arrived', 'in_progress', 'done', 'cancelled'))
  );
  CREATE INDEX appointment_day ON appointment (clinic_id, starts_at);

  -- Sharing with the clinic, per visit, separate from the app's on-device
  -- storage consent. scope is a JSON array of 'intake', 'dose_log',
  -- 'self_meds'. Revoking hides the data at once.
  CREATE TABLE consent (
    id TEXT PRIMARY KEY,
    appointment_id TEXT NOT NULL REFERENCES appointment(id),
    scope TEXT NOT NULL,
    wording_version INTEGER NOT NULL,
    granted_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    revoked_at TEXT
  );
  CREATE INDEX consent_appointment ON consent (appointment_id);

  -- The person's own words before the visit: the only input to the summary.
  CREATE TABLE intake_answer (
    id TEXT PRIMARY KEY,
    appointment_id TEXT NOT NULL REFERENCES appointment(id),
    channel TEXT NOT NULL CHECK (channel IN ('booking', 'pre_visit')),
    question TEXT NOT NULL DEFAULT '',
    answer TEXT NOT NULL,
    answered_at TEXT NOT NULL
  );
  CREATE INDEX intake_appointment ON intake_answer (appointment_id);

  -- Courses and doses as the app records them (MedicationCourse,
  -- DoseLogEntry in medic_core). course_id is the app's '<visitId>#<line>'.
  CREATE TABLE med_course (
    id TEXT NOT NULL,
    patient_id TEXT NOT NULL REFERENCES patient(id),
    item TEXT NOT NULL,
    prescribed_at TEXT NOT NULL,
    PRIMARY KEY (patient_id, id)
  );

  CREATE TABLE dose_event (
    patient_id TEXT NOT NULL REFERENCES patient(id),
    course_id TEXT NOT NULL,
    day TEXT NOT NULL,
    slot TEXT NOT NULL CHECK (slot IN ('morning', 'noon', 'afternoon', 'evening')),
    mark TEXT NOT NULL CHECK (mark IN ('taken', 'skipped')),
    reason TEXT CHECK (reason IN ('forgot', 'outOfStock', 'unwell', 'other')),
    recorded_at TEXT NOT NULL,
    PRIMARY KEY (patient_id, course_id, day, slot)
  );

  CREATE TABLE self_medication (
    id TEXT PRIMARY KEY,
    appointment_id TEXT NOT NULL REFERENCES appointment(id),
    name TEXT NOT NULL,
    how TEXT NOT NULL DEFAULT ''
  );

  -- Never overwritten: regenerating adds a row. sections is JSON:
  -- [{key, text, sources: [intake_answer.id]}]; flags come from the rule
  -- list, not the model.
  CREATE TABLE visit_summary (
    id TEXT PRIMARY KEY,
    appointment_id TEXT NOT NULL REFERENCES appointment(id),
    sections TEXT NOT NULL,
    flags TEXT NOT NULL DEFAULT '[]',
    mode TEXT NOT NULL,
    model TEXT NOT NULL DEFAULT '',
    prompt_version TEXT NOT NULL,
    created_at TEXT NOT NULL,
    feedback TEXT,
    feedback_by TEXT REFERENCES practitioner(id),
    feedback_at TEXT
  );

  -- A sent result is never edited: an amendment is a new version with a
  -- reason. items is JSON of medic_core PrescriptionItem.
  CREATE TABLE visit_result (
    id TEXT PRIMARY KEY,
    appointment_id TEXT NOT NULL REFERENCES appointment(id),
    version INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('draft', 'sent', 'amended')),
    diagnosis TEXT NOT NULL DEFAULT '[]',
    items TEXT NOT NULL DEFAULT '[]',
    advice TEXT NOT NULL DEFAULT '',
    follow_up_date TEXT,
    internal_note TEXT NOT NULL DEFAULT '',
    amend_reason TEXT,
    signed_by TEXT REFERENCES practitioner(id),
    signed_at TEXT,
    pdf_path TEXT,
    updated_at TEXT NOT NULL,
    UNIQUE (appointment_id, version)
  );

  CREATE TABLE audit_event (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    at TEXT NOT NULL,
    actor TEXT NOT NULL,
    action TEXT NOT NULL,
    patient_id TEXT,
    appointment_id TEXT,
    detail TEXT NOT NULL DEFAULT '{}',
    ip TEXT NOT NULL DEFAULT ''
  );
  CREATE INDEX audit_patient ON audit_event (patient_id, at);
  `,
  // Bước 15: code the person types in the app to fetch the sent result of
  // this visit (no patient accounts yet). Stored without dashes.
  `
  ALTER TABLE appointment ADD COLUMN claim_code TEXT;
  ALTER TABLE appointment ADD COLUMN claim_expires_at TEXT;
  CREATE UNIQUE INDEX appointment_claim_code ON appointment (claim_code);
  `,
  // Bước 16: patient sign-in by phone and one-time code. phone is normalised
  // '0xxxxxxxxx'; one phone may belong to patients of several clinics, and a
  // session is per phone. Codes and tokens are stored hashed only.
  `
  ALTER TABLE patient ADD COLUMN phone TEXT;
  CREATE UNIQUE INDEX patient_clinic_phone ON patient (clinic_id, phone) WHERE phone IS NOT NULL;
  CREATE INDEX patient_phone ON patient (phone);

  -- At most one live code per phone; a new request replaces it.
  CREATE TABLE patient_otp (
    phone TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  );

  CREATE TABLE patient_session (
    token_hash TEXT PRIMARY KEY,
    phone TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    revoked_at TEXT
  );
  CREATE INDEX patient_session_phone ON patient_session (phone);
  `,
  // Bước 17: fingerprint of the intake answers a summary was made from, so
  // re-sending the same answers does not add an identical summary.
  `
  ALTER TABLE visit_summary ADD COLUMN input_hash TEXT;
  CREATE INDEX visit_summary_appointment ON visit_summary (appointment_id, created_at);
  `,
];
