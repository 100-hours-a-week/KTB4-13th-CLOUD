import { Trend, Counter } from 'k6/metrics';
import { check } from 'k6';
import { api, authParams, csv, publicParams, recordResponse, tokenForVu } from './common.js';

export const productId = __ENV.PRODUCT_ID || '2103860';
export const productIds = csv('PRODUCT_IDS', productId);
export const tokens = csv('ACCESS_TOKENS');

export const benchmarkDuration = new Trend('benchmark_duration', true);
export const successfulRequests = new Counter('benchmark_successes');
export const failedRequests = new Counter('benchmark_failures');

export function stages(maxVus) {
  return [
    { duration: '30s', target: 50 },
    { duration: '1m', target: 50 },
    { duration: '30s', target: 100 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: maxVus },
    { duration: '2m', target: maxVus },
    { duration: '30s', target: 0 },
  ];
}

export function requestParams(tag, token = null) {
  return token ? authParams(token, { benchmark: tag }) : publicParams({ benchmark: tag });
}

export function selectedToken() {
  return tokenForVu(tokens, __VU);
}

export function checkResponse(response, tag, statuses = [200]) {
  const ok = recordResponse(response, statuses);
  benchmarkDuration.add(response.timings.duration, { benchmark: tag });
  (ok ? successfulRequests : failedRequests).add(1, { benchmark: tag });
  check(response, { [`${tag}: expected status`]: () => ok });
  return ok;
}

export function orderBody(itemCount = 1) {
  const items = Array.from({ length: itemCount }, (_, index) => ({
    itemId: Number(productIds[index % productIds.length]),
    quantity: 1,
  }));
  return JSON.stringify({ items });
}

export { api };
