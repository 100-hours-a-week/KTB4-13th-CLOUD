import http from 'k6/http';
import { check, sleep } from 'k6';
import { api, checkResponse, orderBody, productIds, requestParams, selectedToken, tokens } from '../lib/api-test-common.js';

const itemCount = Number(__ENV.ITEM_COUNT || 1);
const vus = Number(__ENV.ORDER_VUS || 50);
let failureLogs = 0;

export const options = {
  scenarios: { order_item_count: { executor: 'per-vu-iterations', vus, iterations: 1, maxDuration: '2m' } },
  thresholds: { http_req_duration: ['p(95)<2000', 'p(99)<3000'], http_req_failed: ['rate<0.01'] },
};

export default function () {
  if (tokens.length === 0) throw new Error('ACCESS_TOKENS is required for order tests');
  if (productIds.length < itemCount) {
    throw new Error(`PRODUCT_IDS must contain at least ${itemCount} different product IDs`);
  }

  const token = selectedToken();
  const params = requestParams(`order-items-${itemCount}`, token);

  productIds.slice(0, itemCount).forEach((productId) => {
    const cartResponse = http.post(`${api}/cart/items`, JSON.stringify({ productId, quantity: 1 }), params);
    if (cartResponse.status !== 200 && failureLogs < 10) {
      console.log(`[order-setup] productId=${productId}, status=${cartResponse.status}, error=${cartResponse.error || 'none'}, body=${String(cartResponse.body || '').slice(0, 300)}`);
      failureLogs += 1;
    }
    check(cartResponse, { 'order setup: cart item added': (response) => response.status === 200 });
  });

  const response = http.post(`${api}/orders/checkout`, orderBody(itemCount), params);
  if (![200, 201].includes(response.status) && failureLogs < 10) {
    console.log(`[order-items-${itemCount}] status=${response.status}, error=${response.error || 'none'}, body=${String(response.body || '').slice(0, 300)}`);
    failureLogs += 1;
  }
  checkResponse(response, `order-items-${itemCount}`, [200, 201]);
  sleep(1);
}
