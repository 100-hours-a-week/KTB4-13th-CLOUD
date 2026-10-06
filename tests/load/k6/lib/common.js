import { Counter, Rate } from 'k6/metrics';

export const baseUrl = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
export const api = `${baseUrl}/api/v1`;
export const scenarioErrors = new Rate('scenario_error_rate');
export const timeoutRate = new Rate('timeout_rate');
export const successfulTransactions = new Counter('successful_transactions');
export const failedTransactions = new Counter('failed_transactions');

export function csv(name, fallback = '') {
  return (__ENV[name] || fallback).split(',').map((value) => value.trim()).filter(Boolean);
}

export function tokenForVu(tokens, vuId) {
  return tokens.length === 0 ? null : tokens[(vuId - 1) % tokens.length];
}

export function authParams(token, tags = {}) {
  return {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    tags,
    timeout: __ENV.REQUEST_TIMEOUT || '30s',
  };
}

export function publicParams(tags = {}) {
  return { tags, timeout: __ENV.REQUEST_TIMEOUT || '30s' };
}

export function recordResponse(response, expectedStatuses = [200]) {
  const success = expectedStatuses.includes(response.status);
  const timeout = response.status === 0 || String(response.error || '').toLowerCase().includes('timeout');
  scenarioErrors.add(!success);
  timeoutRate.add(timeout);
  if (success) successfulTransactions.add(1);
  else failedTransactions.add(1);
  return success;
}

export const commonThresholds = {
  scenario_error_rate: ['rate<0.01'],
  timeout_rate: ['rate<0.001'],
};
