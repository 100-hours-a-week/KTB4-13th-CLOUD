import http from 'k6/http';
import { check, fail } from 'k6';
import { api, authParams, commonThresholds, csv, recordResponse, tokenForVu } from '../lib/common.js';

const vus = Number(__ENV.AI_VUS || 1);
const tokens = csv('ACCESS_TOKENS');

export const options = {
  scenarios: {
    concurrent_ai_chat: {
      executor: 'per-vu-iterations',
      vus,
      iterations: 1,
      maxDuration: __ENV.MAX_DURATION || '3m',
    },
  },
  thresholds: {
    ...commonThresholds,
    'http_req_duration{endpoint:ai-chat}': ['p(95)<5000', 'p(99)<10000'],
  },
};

export default function () {
  if (tokens.length === 0) fail('ACCESS_TOKENS가 필요합니다.');
  const token = tokenForVu(tokens, __VU);
  const body = JSON.stringify({
    consented: true,
    spec: { intent: {}, exact: {}, filters: {}, semantic: {}, anchor_book: {}, exclude: [] },
    message: __ENV.AI_MESSAGE || '최근에 읽은 책과 비슷하지만 조금 더 가벼운 책을 추천해줘',
    recentTurns: [],
    excludeBookIds: [],
  });
  const response = http.post(`${api}/recommend/chat`, body, authParams(token, { endpoint: 'ai-chat', ai_vus: String(vus) }));
  check(response, { 'AI 채팅 성공': (res) => recordResponse(res) });
}
