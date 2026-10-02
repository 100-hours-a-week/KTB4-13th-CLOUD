import http from 'k6/http';
import { check, fail } from 'k6';
import { api, authParams, commonThresholds, csv, recordResponse, tokenForVu } from '../lib/common.js';

const vus = Number(__ENV.ORDER_VUS || 10);
const itemCount = Number(__ENV.ITEM_COUNT || 1);
const tokens = csv('ACCESS_TOKENS');
const productIds = csv('ORDER_PRODUCT_IDS');

export const options = {
  scenarios: {
    order_by_item_count: {
      executor: 'per-vu-iterations',
      vus,
      iterations: 1,
      maxDuration: __ENV.MAX_DURATION || '3m',
    },
  },
  thresholds: {
    ...commonThresholds,
    'http_req_duration{endpoint:order-item-count}': ['p(95)<1500', 'p(99)<2500'],
  },
};

export default function () {
  if (tokens.length === 0 || productIds.length < itemCount) {
    fail(`ACCESS_TOKENS와 ${itemCount}개 이상의 ORDER_PRODUCT_IDS가 필요합니다.`);
  }
  const token = tokenForVu(tokens, __VU);
  const items = productIds.slice(0, itemCount).map((itemId) => ({ itemId: Number(itemId), quantity: 1 }));
  const response = http.post(`${api}/orders/checkout`, JSON.stringify({ items }), authParams(token, {
    endpoint: 'order-item-count',
    item_count: String(itemCount),
  }));
  check(response, { '상품 개수별 주문 생성 성공': (res) => recordResponse(res) });
}
