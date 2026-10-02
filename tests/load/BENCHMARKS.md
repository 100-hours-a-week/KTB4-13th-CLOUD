# API별 부하테스트 실행안

혼합 사용자 여정 테스트와 별도로 병목 지점을 찾기 위한 API 단위 벤치마크를 실행한다. 모든 명령은 저장소 루트에서 실행한다.

공통 k6 출력 통계는 다음 옵션으로 통일한다.

```bash
--summary-trend-stats='avg,p(50),p(95),p(99),max'
```

## 1. 상품 목록·인기순 첫 페이지

동일한 첫 페이지를 50 → 100 → 300 → 500 VU로 조회한다.

```bash
BASE_URL=https://api-dev.example.com \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/product-list.js
```

측정: RPS, p50/p95/p99, 에러율, RDS `CPUUtilization`, `DatabaseConnections`.

## 2. 검색 결과

동일 검색어와 서로 다른 검색어를 분리 실행한다. 두 실행의 결과를 합치지 않는다.

```bash
BASE_URL=https://api-dev.example.com \
SEARCH_MODE=same SEARCH_QUERIES='여행' \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/search.js
```

```bash
BASE_URL=https://api-dev.example.com \
SEARCH_MODE=varied SEARCH_QUERIES='여행,소설,에세이,자기계발,경제' \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/search.js
```

측정: RPS, p50/p95/p99, `scenario_error_rate`, `timeout_rate`. BE→AI 호출시간은 Application Signals 또는 X-Ray의 검색 AI downstream span으로 확인한다.

## 3. 상품 상세

동일 상품과 서로 다른 상품을 분리 실행한다.

```bash
BASE_URL=https://api-dev.example.com \
PRODUCT_MODE=same PRODUCT_IDS='101' \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/product-detail.js
```

```bash
BASE_URL=https://api-dev.example.com \
PRODUCT_MODE=varied PRODUCT_IDS='101,102,103,104,105' \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/product-detail.js
```

측정: RPS, p95/p99, 에러율, RDS `CPUUtilization`, `DatabaseConnections`.

## 4. 동일 상품 동시 주문

50, 100, 300 VU를 각각 독립 실행한다. VU마다 1회만 주문을 생성한다.

```bash
BASE_URL=https://api-dev.example.com \
ORDER_VUS=50 ORDER_PRODUCT_ID=101 \
ACCESS_TOKENS='token-1,token-2,...' \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/order-concurrency.js
```

`ORDER_VUS`를 100, 300으로 바꾸어 반복한다. 각 토큰의 사용자는 해당 상품을 장바구니에 담은 상태여야 한다.

측정: `successful_transactions`의 rate(TPS), p95/p99, 성공·실패율, 테스트 전후 주문 건수.

현재 Backend 주문 생성은 재고를 차감하지 않고 재고 수량만 검증한다. 따라서 최종 재고는 **테스트 전후 동일해야 한다**. 재고 차감 경쟁 조건을 검증하는 테스트가 아니다.

## 5. 주문 상품 개수

각 사용자의 장바구니에 테스트 대상 상품이 모두 있어야 한다. `ITEM_COUNT`를 1, 10, 30, 50으로 바꾸어 독립 실행한다.

```bash
BASE_URL=https://api-dev.example.com \
ORDER_VUS=10 ITEM_COUNT=10 \
ORDER_PRODUCT_IDS='101,102,103,104,105,106,107,108,109,110' \
ACCESS_TOKENS='token-1,token-2,...' \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/order-item-count.js
```

측정: TPS, p95/p99, 성공·실패율. 요청당 DB Query 수는 현재 CloudWatch 지표만으로 측정할 수 없다. 필요하면 Dev Backend에 datasource-proxy/P6Spy 또는 JDBC 계측을 추가해 요청 trace별 Query 수를 집계한다.

## 6. AI 채팅

1, 10, 30, 50 VU를 각각 독립 실행한다. 각 VU는 채팅 요청을 1회 수행한다.

```bash
BASE_URL=https://api-dev.example.com \
AI_VUS=10 ACCESS_TOKENS='token-1,token-2,...' \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/ai-chat.js
```

측정: 평균, p95/p99, timeout/error율, Backend CPU·Memory, Application Signals/X-Ray의 BE→AI downstream 시간.

## 7. 인기순 스냅샷 갱신 중 조회

15분 동안 인기순 조회를 유지한다. 시작 5분 후 스냅샷 갱신이 시작되도록 매시 정각 UTC 스케줄에 맞추거나 Dev Backend 재시작 시점을 조절한다.

```bash
BASE_URL=https://api-dev.example.com \
POPULARITY_VUS=50 REFRESH_AT_SECONDS=300 REFRESH_WINDOW_SECONDS=180 \
k6 run --summary-trend-stats='avg,p(50),p(95),p(99),max' \
tests/load/k6/benchmarks/popularity-refresh.js
```

k6 결과는 `phase=before`, `phase=during`, `phase=after` 태그로 분리된다. 측정: 단계별 p95/p99, RDS CPU, DB Connection.

현재 Backend는 갱신 완료 로그만 기록하고 시작 시각·소요시간을 기록하지 않는다. 전체 갱신 시간을 정확히 측정하려면 Dev Backend에 시작/완료 시간 또는 Timer 메트릭을 추가해야 한다.

## 공통 CloudWatch 확인 항목

| 대상 | 지표 |
|---|---|
| Application Signals | API별 Volume, Availability, Latency, Faults, Errors |
| Backend | CPUUtilization, Memory 사용률, JVM GC·Thread, 5xx |
| RDS | CPUUtilization, DatabaseConnections, FreeableMemory, Read/WriteLatency, Deadlocks |
| AI 호출 | downstream span latency, timeout, 5xx |

각 테스트의 시작·종료 시각을 기록하고 같은 시간 범위로 CloudWatch를 조회한다.
