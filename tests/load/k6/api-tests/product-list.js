import http from 'k6/http';
import { sleep } from 'k6';
import { api, checkResponse, stages } from '../lib/api-test-common.js';

export const options = {
  scenarios: { popularity_list: { executor: 'ramping-vus', startVUs: 0, stages: stages(500), gracefulRampDown: '30s' } },
  thresholds: { http_req_duration: ['p(50)<500', 'p(95)<1000', 'p(99)<1500'], http_req_failed: ['rate<0.01'] },
};

export default function () {
  const response = http.get(`${api}/items?sort=POPULARITY&limit=20`, { tags: { endpoint: 'product-list-popularity' } });
  checkResponse(response, 'product-list-popularity');
  sleep(1);
}
