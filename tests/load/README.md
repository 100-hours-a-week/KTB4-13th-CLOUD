# V1 부하테스트 실행 안내

이 디렉터리는 Dev Backend API를 대상으로 하는 k6 기반 부하테스트의 기준입니다.

- 혼합 사용자 여정: `smoke.js`, `load.js`, `spike.js`
- API별 병목 벤치마크: `k6/benchmarks/*.js`
- 실행 방법: [BENCHMARKS.md](./BENCHMARKS.md)
- 결과 기록: [RESULTS_TEMPLATE.md](./RESULTS_TEMPLATE.md)

## 대상 흐름

- 공개 조회: 상품 목록, 검색, 상품 상세
- 인증 조회: 추천 피드, 장바구니, 주문 목록
- 쓰기 흐름: 장바구니 상품 추가

소셜 로그인은 Kakao 인가 코드와 외부 provider 상태에 의존하므로 부하테스트 대상에서 제외합니다. 테스트 계정으로 발급한 Access Token을 `ACCESS_TOKENS`에 넣어 사용합니다.

## 실행

```bash
BASE_URL=https://api-dev.example.com \
ACCESS_TOKENS='token-a,token-b,token-c' \
k6 run tests/load/k6/smoke.js
```

```bash
BASE_URL=https://api-dev.example.com \
ACCESS_TOKENS='token-a,token-b,token-c' \
k6 run tests/load/k6/load.js
```

```bash
BASE_URL=https://api-dev.example.com \
ACCESS_TOKENS='token-a,token-b,token-c' \
k6 run tests/load/k6/spike.js
```

필요한 환경변수:

- `BASE_URL`: `/api/v1` 앞의 서버 주소
- `ACCESS_TOKENS`: 쉼표로 구분한 테스트 계정 Access Token
- `PRODUCT_ID`: 기본값 `1`
- `SEARCH_QUERY`: 기본값 `여행`
- `SECOND_SEARCH_QUERY`: 기본값 `소설`
- `AI_MESSAGE`: 선택값, AI 추천 테스트 질문
- `CATEGORY_ID`: 선택값

## v1 판정 기준

- HTTP 5xx 및 timeout 없음
- Tier 1 기준: 800ms 이하 요청 비율 99% 이상
- Tier 2 기준: 1,000ms 이하 요청 비율 95% 이상
- Load 테스트에서 전체 실패율 0.1% 이하
- Spike 종료 후 정상 요청 처리가 회복됨

세부 사용자 플로우와 요청 비율은 [SCENARIOS.md](./SCENARIOS.md)에 정의합니다. 이 문서의 VU 단계는 첫 실행을 위한 기준값이며 실제 결과에 따라 조정합니다.

## 부하 단계의 의미

- Smoke는 1~5 VU로 핵심 플로우, 인증 토큰, 테스트 데이터, 계측이 정상인지 확인합니다.
- Load는 20~100 VU로 예상 Peak보다 여유 있는 일반 부하를 단계적으로 검증합니다.
- Spike는 50 VU에서 200 VU 이상으로 급격히 증가시키고, 500 VU까지 확장한 뒤 정상 상태로 회복되는지 확인합니다.

VU 수는 고정된 표준값이 아니라 현재 서비스 규모와 홍보 직후 유입 가설을 바탕으로 한 초기 기준입니다.

## 실행 순서

1. `SCENARIOS.md`의 테스트 계정·상품·토큰 조건을 확인합니다.
2. Smoke를 실행해 API, 인증, 데이터, 계측을 확인합니다.
3. Load를 실행해 20 → 50 → 100 VU를 단계별로 확인합니다.
4. 결과가 정상일 때 Spike를 실행해 50 → 200 VU를 검증합니다.
5. 200 VU 결과가 안정적일 때만 500 VU 단계를 추가합니다.
6. 각 실행 결과에 VU, 요청 수, p95/p99, 오류율, SLO 결과를 기록합니다.

## 사전 준비

1. Dev DB에 테스트 상품과 테스트 계정을 준비합니다.
2. 각 토큰이 서로 다른 계정인지 확인합니다. 장바구니 추가와 주문 계열은 같은 계정 공유 시 데이터 경합이 발생합니다.
3. `PRODUCT_ID`가 실제 활성 재고 상품인지 확인합니다.
4. CloudWatch에서 Application Signals, DB connection pool, CPU, memory를 함께 확인합니다.
5. 주문 생성과 AI 추천 채팅은 전용 스크립트로 분리하며, 데이터와 외부 AI 비용을 확인한 뒤 실행합니다.
