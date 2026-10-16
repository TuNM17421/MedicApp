import { bookableDates, department, doctor, facility } from './catalog.js';

/**
 * Structured output both extractors return. `null` means "not mentioned in
 * these utterances", never "clear the field". Strict JSON Schema for the
 * Responses API: every property required, nullable where optional.
 */
export const EXTRACTION_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'patient_id',
    'visit_type',
    'facility_id',
    'department_id',
    'department_reason',
    'doctor_id',
    'time_kind',
    'date',
    'period',
    'symptoms_summary',
    'urgent_signal',
    'out_of_scope',
  ],
  properties: {
    patient_id: { type: ['string', 'null'] },
    visit_type: { type: ['string', 'null'], enum: ['insurance', 'service', null] },
    facility_id: { type: ['string', 'null'] },
    department_id: { type: ['string', 'null'] },
    department_reason: { type: ['string', 'null'] },
    doctor_id: { type: ['string', 'null'] },
    time_kind: { type: ['string', 'null'], enum: ['earliest', 'date', null] },
    date: { type: ['string', 'null'] },
    period: { type: ['string', 'null'], enum: ['morning', 'afternoon', null] },
    symptoms_summary: { type: ['string', 'null'] },
    urgent_signal: { type: 'boolean' },
    out_of_scope: { type: 'boolean' },
  },
};

export const emptyExtraction = () => ({
  patient_id: null,
  visit_type: null,
  facility_id: null,
  department_id: null,
  department_reason: null,
  doctor_id: null,
  time_kind: null,
  date: null,
  period: null,
  symptoms_summary: null,
  urgent_signal: false,
  out_of_scope: false,
});

const text = (value, max) =>
  typeof value === 'string' && value.trim() ? value.trim().slice(0, max) : null;

/**
 * Server-side validation. The model (or the mock) only proposes values: IDs
 * outside the catalog, dates outside the bookable window and malformed
 * values are dropped and reported in `rejected`.
 */
export function validateExtraction(raw, { profiles, today }) {
  const rejected = [];
  const patch = {};
  const value = raw && typeof raw === 'object' ? raw : {};
  const take = (field, ok, apply) => {
    const v = value[field];
    if (v === null || v === undefined) return;
    if (ok(v)) apply(v);
    else rejected.push(field);
  };
  take('patient_id', (v) => profiles.some((p) => p.id === v), (v) => (patch.patientId = v));
  take('visit_type', (v) => v === 'insurance' || v === 'service', (v) => (patch.type = v));
  take('facility_id', (v) => Boolean(facility(v)), (v) => (patch.facilityId = v));
  take('department_id', (v) => Boolean(department(v)), (v) => {
    patch.departmentId = v;
    patch.departmentReason = text(value.department_reason, 200);
  });
  take('doctor_id', (v) => Boolean(doctor(v)), (v) => (patch.doctorId = v));
  const dates = bookableDates(today);
  if (value.time_kind === 'earliest') {
    patch.time = { kind: 'earliest', date: null, period: null };
  } else if (value.time_kind === 'date') {
    if (dates.includes(value.date)) patch.time = { kind: 'date', date: value.date, period: null };
    else rejected.push('date');
  } else if (value.time_kind !== null && value.time_kind !== undefined) {
    rejected.push('time_kind');
  }
  take('period', (v) => v === 'morning' || v === 'afternoon', (v) => (patch.period = v));
  const symptoms = text(value.symptoms_summary, 300);
  if (symptoms) patch.symptoms = symptoms;
  return {
    patch,
    rejected,
    urgent: value.urgent_signal === true,
    outOfScope: value.out_of_scope === true,
  };
}

export class ExtractorError extends Error {
  /**
   * @param {'config'|'permission'|'quota'|'network'|'timeout'|'incomplete'|'refusal'|'invalid_output'|'aborted'} code
   */
  constructor(code, message) {
    super(message ?? code);
    this.code = code;
  }
}
