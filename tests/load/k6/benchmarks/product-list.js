import http from 'k6/http';
import { check, sleep } from 'k6';
import { api, commonThresholds, publicParams, recordResponse } from '../lib/common.js';

export const options = {
  scenarios: {
    popularity_first_page: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 50 },
        { duration: '3m', target: 50 },
        { duration: '1m', target: 100 },
        { duration: '3m', target: 100 },
        { duration: '1m', target: 300 },
        { duration: '3m', target: 300 },
        { duration: '1m', target: 500 },
        { duration: '3m', target: 500 },
        { duration: '1m', target: 0 },
      ],
    },
  },
  thresholds: {
    ...commonThresholds,
    'http_req_duration{endpoint:product-list-popularity}': ['p(95)<1000', 'p(99)<1500'],
    'http_req_failed{endpoint:product-list-popularity}': ['rate<0.01'],
  },
};

export default function () {
  const response = http.get(`${api}/items?sort=POPULARITY&limit=20`, publicParams({ endpoint: 'product-list-popularity' }));
  check(response, { '인기순 첫 페이지 조회 성공': (res) => recordResponse(res) });
  sleep(Number(__ENV.THINK_TIME_SECONDS || 1));
}
