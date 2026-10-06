import http from 'k6/http';
import { sleep } from 'k6';
import { api, checkResponse, orderBody, requestParams, selectedToken, tokens } from '../lib/api-test-common.js';

const itemCount = Number(__ENV.ITEM_COUNT || 1);
const vus = Number(__ENV.ORDER_VUS || 50);

export const options = {
  scenarios: { order_item_count: { executor: 'per-vu-iterations', vus, iterations: 1, maxDuration: '2m' } },
  thresholds: { http_req_duration: ['p(95)<2000', 'p(99)<3000'], http_req_failed: ['rate<0.01'] },
};

export default function () {
  if (tokens.length === 0) throw new Error('ACCESS_TOKENS is required for order tests');
  const response = http.post(`${api}/orders/checkout`, orderBody(itemCount), requestParams(`order-items-${itemCount}`, selectedToken()));
  checkResponse(response, `order-items-${itemCount}`, [200, 201]);
  sleep(1);
}
