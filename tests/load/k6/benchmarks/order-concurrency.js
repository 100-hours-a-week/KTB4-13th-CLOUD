import http from 'k6/http';
import { check, fail } from 'k6';
import { api, authParams, commonThresholds, csv, recordResponse, tokenForVu } from '../lib/common.js';

const vus = Number(__ENV.ORDER_VUS || 50);
const tokens = csv('ACCESS_TOKENS');
const productId = (__ENV.ORDER_PRODUCT_ID || '').trim();
const quantity = Number(__ENV.ORDER_QUANTITY || 1);

export const options = {
  scenarios: {
    concurrent_orders: {
      executor: 'per-vu-iterations',
      vus,
      iterations: 1,
      maxDuration: __ENV.MAX_DURATION || '2m',
    },
  },
  thresholds: {
    ...commonThresholds,
    'http_req_duration{endpoint:order-checkout}': ['p(95)<1000', 'p(99)<1500'],
  },
};

export default function () {
  if (tokens.length === 0 || !productId) fail('ACCESS_TOKENS와 ORDER_PRODUCT_ID가 필요합니다.');
  const token = tokenForVu(tokens, __VU);
  const body = JSON.stringify({ items: [{ itemId: Number(productId), quantity }] });
  const response = http.post(`${api}/orders/checkout`, body, authParams(token, { endpoint: 'order-checkout', order_vus: String(vus) }));
  check(response, { '주문 생성 성공': (res) => recordResponse(res) });
}
