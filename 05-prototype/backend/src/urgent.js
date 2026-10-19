// Urgent-care signs in what the user says to Smart Scheduling. The app always
// checks this list in code (urgent-signs.json); with real AI on, the model's
// urgent_signal only adds to it and never replaces it, and the list still
// works when the model call fails. The list is a mock pending clinical review.
import { readFileSync } from 'node:fs';

import { compileSigns, findSigns } from './summary/red-flags.js';

export const urgentList = JSON.parse(readFileSync(new URL('./urgent-signs.json', import.meta.url), 'utf8'));

const SIGNS = compileSigns(urgentList);

/** Labels of the listed urgent signs stated (not denied) in [utterances]. */
export function urgentSigns(utterances) {
  const codes = new Set(utterances.flatMap((u) => findSigns(SIGNS, String(u ?? ''))));
  return SIGNS.filter((s) => codes.has(s.code)).map((s) => s.label);
}
