import http from 'k6/http';
import { check, sleep } from 'k6';
import { api, commonThresholds, publicParams, recordResponse } from '../lib/common.js';

const startedAt = Date.now();
const refreshAtSeconds = Number(__ENV.REFRESH_AT_SECONDS || 300);
const refreshWindowSeconds = Number(__ENV.REFRESH_WINDOW_SECONDS || 180);

export const options = {
  scenarios: {
    popularity_during_refresh: {
      executor: 'constant-vus',
      vus: Number(__ENV.POPULARITY_VUS || 50),
      duration: __ENV.TEST_DURATION || '15m',
    },
  },
  thresholds: {
    ...commonThresholds,
    'http_req_duration{endpoint:popularity-refresh,phase:before}': ['p(95)<1000', 'p(99)<1500'],
    'http_req_duration{endpoint:popularity-refresh,phase:during}': ['p(95)<1500', 'p(99)<2500'],
  },
};

function currentPhase() {
  const elapsedSeconds = (Date.now() - startedAt) / 1000;
  if (elapsedSeconds < refreshAtSeconds) return 'before';
  if (elapsedSeconds < refreshAtSeconds + refreshWindowSeconds) return 'during';
  return 'after';
}

export default function () {
  const phase = currentPhase();
  const response = http.get(`${api}/items?sort=POPULARITY&limit=20`, publicParams({ endpoint: 'popularity-refresh', phase }));
  check(response, { [`인기순 조회 성공 (${phase})`]: (res) => recordResponse(res) });
  sleep(Number(__ENV.THINK_TIME_SECONDS || 1));
}
