import http from 'k6/http';
import { check, sleep } from 'k6';
import { api, commonThresholds, csv, publicParams, recordResponse } from '../lib/common.js';

const mode = (__ENV.SEARCH_MODE || 'same').toLowerCase();
const queries = csv('SEARCH_QUERIES', '여행,소설,에세이,자기계발,경제');

export const options = {
  scenarios: {
    search: {
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
    'http_req_duration{endpoint:search}': ['p(95)<1000', 'p(99)<1500'],
    'http_req_failed{endpoint:search}': ['rate<0.01'],
  },
};

export default function () {
  const query = mode === 'varied' ? queries[(__VU + __ITER) % queries.length] : queries[0];
  const url = `${api}/search?query=${encodeURIComponent(query)}&size=12&sort=popular`;
  const response = http.get(url, publicParams({ endpoint: 'search', search_mode: mode }));
  check(response, { '검색 결과 조회 성공': (res) => recordResponse(res) });
  sleep(Number(__ENV.THINK_TIME_SECONDS || 1));
}
