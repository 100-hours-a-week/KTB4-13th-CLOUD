import http from 'k6/http';
import { check, sleep } from 'k6';
import { api, commonThresholds, csv, publicParams, recordResponse } from '../lib/common.js';

const mode = (__ENV.PRODUCT_MODE || 'same').toLowerCase();
const productIds = csv('PRODUCT_IDS', __ENV.PRODUCT_ID || '1');

export const options = {
  scenarios: {
    product_detail: {
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
    'http_req_duration{endpoint:product-detail}': ['p(95)<1000', 'p(99)<1500'],
    'http_req_failed{endpoint:product-detail}': ['rate<0.01'],
  },
};

export default function () {
  const productId = mode === 'varied' ? productIds[(__VU + __ITER) % productIds.length] : productIds[0];
  const response = http.get(`${api}/products/${productId}`, publicParams({ endpoint: 'product-detail', product_mode: mode }));
  check(response, { '상품 상세 조회 성공': (res) => recordResponse(res) });
  sleep(Number(__ENV.THINK_TIME_SECONDS || 1));
}
