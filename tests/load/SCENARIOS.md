# V1 부하테스트 시나리오

## 실행 안내

Dev Backend API를 대상으로 k6 부하테스트를 실행한다.

필요한 환경변수는 `BASE_URL`, `ACCESS_TOKENS`, `PRODUCT_ID`, `SEARCH_QUERY`, `SECOND_SEARCH_QUERY`, `AI_MESSAGE`이다.

```bash
BASE_URL=https://api-dev.bookjeok.site \
ACCESS_TOKENS='token-a,token-b,token-c' \
k6 run tests/load/k6/smoke.js
```

Load와 Spike는 위 명령의 파일명만 각각 `load.js`, `spike.js`로 바꿔 실행한다. 실행 순서는 Smoke → API별 상세 테스트 → Load → 주문·AI·스냅샷 갱신 → Spike다.

API별 상세 테스트는 `tests/load/k6/api-tests` 아래 스크립트를 사용한다. 주문과 AI 테스트는 `ACCESS_TOKENS`가 필요하며, `PRODUCT_ID` 또는 `PRODUCT_IDS`에는 Dev에서 실제로 판매 중인 상품 ID를 넣는다.

```bash
# 상품 목록·인기순: 50 → 100 → 300 VU
BASE_URL=https://api-dev.bookjeok.site k6 run tests/load/k6/api-tests/product-list.js

# 검색: 동일 검색어 / 서로 다른 검색어를 각각 실행
SEARCH_MODE=same SEARCH_QUERIES='여행,소설,역사' k6 run tests/load/k6/api-tests/search.js
SEARCH_MODE=varied SEARCH_QUERIES='여행,소설,역사' k6 run tests/load/k6/api-tests/search.js

# 상품 상세: 동일 상품 / 서로 다른 상품을 각각 실행
DETAIL_MODE=same PRODUCT_ID=2103860 k6 run tests/load/k6/api-tests/product-detail.js
DETAIL_MODE=varied PRODUCT_IDS='2103860,2103861,2103862' k6 run tests/load/k6/api-tests/product-detail.js

# 주문 생성: 50·100·300건 동시 요청
ORDER_VUS=50 ACCESS_TOKENS='token-a,token-b' PRODUCT_ID=2103860 k6 run tests/load/k6/api-tests/order-concurrency.js
ORDER_VUS=100 ACCESS_TOKENS='token-a,token-b' PRODUCT_ID=2103860 k6 run tests/load/k6/api-tests/order-concurrency.js
ORDER_VUS=300 ACCESS_TOKENS='token-a,token-b' PRODUCT_ID=2103860 k6 run tests/load/k6/api-tests/order-concurrency.js

# 주문 상품 수: 1·10·30·50개를 각각 실행
ITEM_COUNT=1 ORDER_VUS=50 ACCESS_TOKENS='token-a,token-b' PRODUCT_IDS='2103860,2103861' k6 run tests/load/k6/api-tests/order-item-count.js
ITEM_COUNT=10 ORDER_VUS=50 ACCESS_TOKENS='token-a,token-b' PRODUCT_IDS='2103860,2103861' k6 run tests/load/k6/api-tests/order-item-count.js

# AI 채팅: 1·10·30·50 VU를 각각 실행
AI_VUS=1 ACCESS_TOKENS='token-a,token-b' k6 run tests/load/k6/api-tests/ai-chat.js
AI_VUS=10 ACCESS_TOKENS='token-a,token-b' k6 run tests/load/k6/api-tests/ai-chat.js

# 인기순 스냅샷 갱신 전·중·후에 각각 실행
REFRESH_PHASE=before k6 run tests/load/k6/api-tests/popularity-refresh.js
REFRESH_PHASE=during k6 run tests/load/k6/api-tests/popularity-refresh.js
REFRESH_PHASE=after k6 run tests/load/k6/api-tests/popularity-refresh.js
```

`REFRESH_PHASE=during` 실행 시점은 스냅샷 갱신 작업과 맞추고, 갱신 시작·종료 시각을 별도로 기록한다. 주문 테스트는 테스트 계정별 토큰을 겹치지 않게 준비하고, 실행 전후 주문 건수와 재고를 확인한다.

## 1. 목적과 공통 조건

Dev 환경에서 실제 사용자 흐름과 핵심 API에 부하를 발생시켜 응답시간, 처리량, 오류율, 병목 지점을 확인한다. k6로 Backend API를 직접 호출하며, 카카오 로그인은 사전 발급한 테스트 토큰으로 대체한다.

- 대상: `https://api-dev.bookjeok.site`
- Smoke·Load·Spike 최대 부하: 300 VU. API별 인기순·검색 테스트는 현재 상태 확인을 위해 최대 500 VU까지 별도로 수행한다.
- 데이터: Dev 전용 계정·상품·주소·재고
- 공통 측정: VU, RPS 또는 TPS, p50/p95/p99, 에러율, timeout 비율
- 일반 API p95: 1초 이내
- 주문·AI API p95: 2초 이내
- 에러율 1% 미만, timeout 0.1% 미만
- 가능하면 App CPU·Memory, DB CPU·Connection, slow query, AI 호출시간도 기록

## 2. 사용자 플로우

### 일반 검색

```text
홈 조회 → 검색 → 검색 결과 → 재검색 → 상품 상세 3권 비교
```

### AI 추천

```text
홈 조회 → AI 추천 질문 → 추천 결과 확인 → 상품 상세 3권 비교
```

### 홈 큐레이션

```text
홈 조회 → 인기순·개인화 추천 확인 → 상품 상세 3권 비교
```

### 구매 전환

```text
상품 상세 → 장바구니 조회 → 상품 추가 → 주소 조회
→ 주문 생성 → 주문 목록·상세 확인
```

검색·AI 추천·홈 큐레이션은 각각 40%·30%·30% 비율로 시작한다. 탐색 세션의 15%는 구매 전환으로 이어진다고 가정한다. 주문 테스트에서는 계정별 장바구니를 분리하고, 충분한 재고가 있는 Dev 전용 상품을 사용한다.

## 3. 테스트 유형

### Smoke

정상 동작, 토큰, 테스트 데이터, 측정 구성을 확인한다.

```text
1 VU 1분 → 5 VU까지 30초 → 5 VU 3분 유지 → 0 VU
```

### Load

일반적인 지속 부하에서 성능과 병목을 확인한다.

```text
20 VU 2분 증가 → 20 VU 5분
→ 50 VU 2분 증가 → 50 VU 10분
→ 100 VU 2분 증가 → 100 VU 10분
→ 0 VU 3분 회복
```

### Spike

급격한 유입과 부하 감소 후 회복을 확인한다.

```text
50 VU 5분 → 200 VU까지 30초 → 200 VU 5분
→ 300 VU까지 30초 → 300 VU 5분
→ 50 VU까지 30초 → 50 VU 10분 → 0 VU
```

## 4. API별 상세 측정 시나리오

아래 항목은 사용자 플로우와 별도로 API별 병목을 확인하기 위한 시나리오다. 각 항목은 공통 측정값과 함께 필요한 인프라 지표를 기록한다.

### 상품 목록·인기순 조회

동일한 인기순 첫 페이지 요청을 반복한다. 50 → 100 → 300 VU로 증가시키며 RPS, p50/p95/p99, 에러율을 측정하고 DB CPU와 DB Connection 사용량을 확인한다.

### 검색 결과 조회

동일 검색어와 서로 다른 검색어를 각각 테스트한다. 부하를 단계적으로 증가시키며 RPS, p50/p95/p99, 에러율, timeout 비율을 측정한다. 가능하면 Backend에서 AI를 호출하는 데 걸린 시간도 기록한다.

### 상품 상세 조회

동일 상품 조회와 서로 다른 상품 조회를 각각 테스트한다. RPS, p95/p99, 에러율을 측정하고 DB CPU와 DB Connection 사용량을 확인한다.

### 주문 생성

동일 상품에 50·100·300건의 주문을 동시에 요청한다. TPS, p95/p99, 성공·실패율을 측정하고 종료 후 최종 주문 건수와 재고 상태를 확인한다.

### 주문 상품 개수별 성능

한 주문에 포함되는 상품 수를 1·10·30·50개로 나누어 각각 테스트한다. TPS와 p95/p99를 측정하고 가능하면 요청당 DB Query 수도 기록한다.

### AI 채팅

동시 요청을 1·10·30·50 VU로 증가시킨다. 평균 응답시간, p95/p99, timeout·에러 비율을 측정하고 AI 서버 CPU·Memory와 Backend → AI 호출시간을 확인한다.

### 인기순 스냅샷 갱신 중 조회

갱신 전·중·후에 동일한 인기순 조회를 발생시킨다. 조회 API의 p95/p99 변화, 에러율, DB CPU·Connection, 스냅샷 전체 갱신시간을 기록한다.

## 5. 결과 기록

| 시나리오 | VU | RPS/TPS | p50 | p95 | p99 | 에러율 | timeout |
|---|---:|---:|---:|---:|---:|---:|---:|
| 상품 목록·인기순 |  |  |  |  |  |  |  |
| 검색 |  |  |  |  |  |  |  |
| 상품 상세 |  |  |  |  |  |  |  |

주문은 성공·실패 건수와 테스트 전후 주문·재고를 함께 기록한다. AI와 스냅샷 갱신은 관련 인프라 지표를 추가한다.

## 6. 실행 순서

1. 테스트 계정·상품·주소·재고·토큰을 준비한다.
2. Health와 단일 API 요청으로 연결을 확인한다.
3. Smoke를 실행한다.
4. API별 상세 테스트를 실행한다.
5. Load를 실행하고 SLO를 확인한다.
6. 주문·AI·스냅샷 갱신 테스트를 실행한다.
7. Spike를 실행하고 종료 후 회복 여부를 확인한다.
8. 공통 결과 표와 인프라 지표를 정리한다.
