import http from 'k6/http';
import { sleep } from 'k6';
import { api, checkResponse, orderBody, requestParams, selectedToken, tokens } from '../lib/api-test-common.js';

const vus = Number(__ENV.ORDER_VUS || 50);

export const options = {
  scenarios: { order_concurrency: { executor: 'per-vu-iterations', vus, iterations: 1, maxDuration: '2m' } },
  thresholds: { http_req_duration: ['p(95)<2000', 'p(99)<3000'], http_req_failed: ['rate<0.01'] },
};

export default function () {
  if (tokens.length === 0) throw new Error('ACCESS_TOKENS is required for order tests');
  const response = http.post(`${api}/orders/checkout`, orderBody(1), requestParams('order-concurrency', selectedToken()));
  checkResponse(response, 'order-concurrency', [200, 201]);
  sleep(1);
}
