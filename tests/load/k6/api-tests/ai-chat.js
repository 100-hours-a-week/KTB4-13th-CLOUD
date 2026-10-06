import http from 'k6/http';
import { sleep } from 'k6';
import { api, checkResponse, requestParams, selectedToken, stages, tokens } from '../lib/api-test-common.js';

const maxVus = Number(__ENV.AI_VUS || 1);
const body = JSON.stringify({
  consented: true,
  spec: { intent: {}, exact: {}, filters: {}, semantic: {}, anchor_book: {}, exclude: [] },
  message: __ENV.AI_MESSAGE || '최근에 읽은 책과 비슷하지만 새로운 책을 추천해줘',
  recentTurns: [],
  excludeBookIds: [],
});

export const options = {
  scenarios: { ai_chat: { executor: 'ramping-vus', startVUs: 0, stages: [{ duration: '30s', target: maxVus }, { duration: '2m', target: maxVus }, { duration: '30s', target: 0 }], gracefulRampDown: '30s' } },
  thresholds: { http_req_duration: ['p(95)<2000', 'p(99)<3000'], http_req_failed: ['rate<0.01'] },
};

export default function () {
  if (tokens.length === 0) throw new Error('ACCESS_TOKENS is required for AI chat tests');
  const response = http.post(`${api}/recommend/chat`, body, requestParams('ai-chat', selectedToken()));
  checkResponse(response, 'ai-chat');
  sleep(1);
}
