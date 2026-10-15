import { readConfig } from '../src/config.js';
import { extractMock } from '../src/extractors/mock.js';

export const TODAY = '2026-10-14'; // Wednesday; bookable: 15,16,17,19,20,21
export const PROFILES = [
  { id: 'self', relationship: 'Bản thân', age: 60 },
  { id: 'mother', relationship: 'Mẹ', age: 78 },
  { id: 'child', relationship: 'Cháu', age: 9 },
];
export const config = (env = {}) => readConfig({ SMART_MODE: 'mock', ...env });
export const mockExtractor = async (input) => extractMock(input);
export const silentLog = () => {};
