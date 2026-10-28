import http from 'k6/http';
import { sleep } from 'k6';
import { api, checkResponse, stages } from '../lib/api-test-common.js';

const mode = __ENV.SEARCH_MODE || 'same';
const queries = (__ENV.SEARCH_QUERIES || '여행,소설,역사').split(',').map((value) => value.trim()).filter(Boolean);
let failureLogs = 0;

export const options = {
  scenarios: { search: { executor: 'ramping-vus', startVUs: 0, stages: stages(500), gracefulRampDown: '30s' } },
  thresholds: { http_req_duration: ['p(50)<500', 'p(95)<1000', 'p(99)<1500'], http_req_failed: ['rate<0.01'] },
};

export default function () {
  const query = mode === 'varied' ? queries[(__VU - 1) % queries.length] : queries[0];
  const response = http.get(`${api}/search?query=${encodeURIComponent(query)}&size=12&sort=popular`, { tags: { endpoint: `search-${mode}` } });
  if (response.status !== 200 && failureLogs < 10) {
    console.log(`[search-${mode}] status=${response.status}, error=${response.error || 'none'}, body=${String(response.body || '').slice(0, 200)}`);
    failureLogs += 1;
  }
  checkResponse(response, `search-${mode}`);
  sleep(1);
}
