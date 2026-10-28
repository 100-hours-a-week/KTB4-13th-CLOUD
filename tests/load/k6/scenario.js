import http from 'k6/http';
import { check, sleep } from 'k6';

const baseUrl = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const api = `${baseUrl}/api/v1`;
const tokens = (__ENV.ACCESS_TOKENS || '').split(',').map((v) => v.trim()).filter(Boolean);
const productId = __ENV.PRODUCT_ID || '1';
const query = encodeURIComponent(__ENV.SEARCH_QUERY || '여행');
const categoryId = __ENV.CATEGORY_ID ? `&categoryId=${encodeURIComponent(__ENV.CATEGORY_ID)}` : '';

export function authHeaders() {
  if (tokens.length === 0) return {};
  const token = tokens[(__VU - 1) % tokens.length];
  return { Authorization: `Bearer ${token}` };
}

export function publicFlow() {
  const params = { tags: { tier: 'tier2' } };
  const requests = [
    ['catalog', http.get(`${api}/items?limit=20${categoryId}`, params)],
    ['search', http.get(`${api}/search?query=${query}&size=12&sort=popular`, params)],
    ['detail', http.get(`${api}/products/${productId}`, params)],
  ];
  requests.forEach(([name, response]) => check(response, { [`${name}: status is 2xx`]: (r) => r.status >= 200 && r.status < 300 }));
}

function homeFlow() {
  const params = { tags: { flow: 'home-curation' } };
  const responses = [
    http.get(`${api}/items?sort=POPULARITY&limit=20`, params),
  ];
  if (tokens.length > 0) {
    responses.push(http.get(`${api}/recommend/feed?surface=home&size=10`, { headers: authHeaders(), tags: { flow: 'home-curation' } }));
  }
  responses.forEach((response) => check(response, { 'home flow: status is 2xx': (r) => r.status >= 200 && r.status < 300 }));
}

function searchFlow() {
  const params = { tags: { flow: 'search' } };
  const responses = [
    http.get(`${api}/search?query=${query}&size=12&sort=popular`, params),
    http.get(`${api}/search?query=${encodeURIComponent(__ENV.SECOND_SEARCH_QUERY || '소설')}&size=12&sort=popular`, params),
    http.get(`${api}/products/${productId}`, params),
    http.get(`${api}/products/${productId}`, params),
    http.get(`${api}/products/${productId}`, params),
  ];
  responses.forEach((response) => check(response, { 'search flow: status is 2xx': (r) => r.status >= 200 && r.status < 300 }));
}

function aiFlow() {
  if (tokens.length === 0) return;
  const params = {
    headers: { ...authHeaders(), 'Content-Type': 'application/json' },
    tags: { flow: 'ai-recommendation' },
  };
  const body = JSON.stringify({
    consented: true,
    spec: { intent: {}, exact: {}, filters: {}, semantic: {}, anchor_book: {}, exclude: [] },
    message: __ENV.AI_MESSAGE || '최근에 읽은 책과 비슷하지만 새로운 책을 추천해줘',
    recentTurns: [],
    excludeBookIds: [],
  });
  const response = http.post(`${api}/recommend/chat`, body, params);
  check(response, { 'ai flow: status is 2xx': (r) => r.status >= 200 && r.status < 300 });
  const cardResponse = http.get(`${api}/products/${productId}`, params);
  check(cardResponse, { 'ai detail flow: status is 2xx': (r) => r.status >= 200 && r.status < 300 });
}

export function authenticatedFlow() {
  if (tokens.length === 0) return;
  const params = { headers: authHeaders(), tags: { tier: 'tier1' } };
  const requests = [
    ['recommend', http.get(`${api}/recommend/feed?surface=home&size=10`, params)],
    ['cart', http.get(`${api}/cart`, params)],
    ['orders', http.get(`${api}/orders?limit=20`, params)],
  ];
  requests.forEach(([name, response]) => check(response, { [`${name}: status is 2xx`]: (r) => r.status >= 200 && r.status < 300 }));
}

export function smokeFlow() {
  searchFlow();
  if (tokens.length > 0) {
    homeFlow();
    aiFlow();
    authenticatedFlow();
  } else {
    publicFlow();
  }
  sleep(1);
}

export function userFlow() {
  userFlowOnce();
  sleep(Math.random() * 3 + 1);
}

export function userFlowOnce() {
  const roll = Math.random();
  if (roll < 0.4) searchFlow();
  else if (roll < 0.7) aiFlow();
  else homeFlow();
}
