import http from 'k6/http';
import { sleep } from 'k6';
import { api, checkResponse, productId, productIds, stages } from '../lib/api-test-common.js';

const mode = __ENV.DETAIL_MODE || 'same';

export const options = {
  scenarios: { product_detail: { executor: 'ramping-vus', startVUs: 0, stages: stages(300), gracefulRampDown: '30s' } },
  thresholds: { http_req_duration: ['p(50)<500', 'p(95)<1000', 'p(99)<1500'], http_req_failed: ['rate<0.01'] },
};

export default function () {
  const id = mode === 'varied' ? productIds[(__VU - 1) % productIds.length] : productId;
  const response = http.get(`${api}/products/${id}`, { tags: { endpoint: `product-detail-${mode}` } });
  checkResponse(response, `product-detail-${mode}`);
  sleep(1);
}
