# M7 장애 알림 및 모니터링

## 범위

현재 운영 환경의 장애 감지는 다음 두 영역으로 나눕니다.

1. GitHub Actions CI/CD 장애
2. AWS 인프라 장애

애플리케이션의 API Health Check를 CloudWatch에서 직접 감시하는 구성은 별도 작업으로 남아 있습니다.

## 완료된 구성

### CI/CD 및 PR 알림

- 각 저장소 CI 실패를 Discord Webhook으로 알립니다.
- Cloud Production CD 성공·실패를 Discord Webhook으로 알립니다.
- AI와 Cloud의 PR 생성, 재오픈, Draft 해제, 리뷰 요청을 Discord Webhook으로 알립니다.
- Webhook Secret이 없을 때 배포나 CI를 실패시키지 않고 알림만 건너뜁니다.

### EC2 기본 장애 알림

대상 인스턴스:

| 대상 | Instance ID |
| --- | --- |
| App | `i-02549e178513b10b4` |
| AI | `i-062ff04c0548849bd` |

모든 Alarm은 다음 SNS Topic으로 연결되어 있습니다.

`arn:aws:sns:ap-northeast-2:522688057030:Default_CloudWatch_Alarms_Topic`

현재 SNS 구독 방식은 이메일이며, 등록된 수신자는 AWS 계정에 설정된 확인된 이메일 주소입니다.

| Alarm | 조건 | 평가 |
| --- | --- | --- |
| `bookjeok-ec2-cpu-high` | App CPU 80% 초과 | 5분 × 3회 |
| `bookjeok-ai-cpu-high` | AI CPU 80% 초과 | 5분 × 3회 |
| `bookjeok-app-status-check-failed` | App EC2 상태 검사 실패 | 1분 × 2회 |
| `bookjeok-ai-status-check-failed` | AI EC2 상태 검사 실패 | 1분 × 2회 |
| `bookjeok-app-memory-high` | App 메모리 80% 초과 | 5분 × 3회 |
| `bookjeok-ai-memory-high` | AI 메모리 80% 초과 | 5분 × 3회 |
| `bookjeok-app-disk-high` | App `/` 디스크 85% 초과 | 5분 × 3회 |
| `bookjeok-ai-disk-high` | AI `/` 디스크 85% 초과 | 5분 × 3회 |

### CloudWatch Agent

App·AI EC2에 CloudWatch Agent를 설치하고 다음 `CWAgent` 지표를 수집합니다.

- `mem_used_percent`
- `disk_used_percent` (`/` 파일시스템)

두 인스턴스가 사용하는 `SSM` IAM 역할에는 `CloudWatchAgentServerPolicy`가 추가되어 있습니다.

## 남은 작업

현재 M7은 인프라 기본 감지까지 완료된 상태입니다. 다음 항목까지 구현해야 M7 전체 완료로 볼 수 있습니다.

- Backend API Health Check의 CloudWatch 지표화
- AI API Health Check의 CloudWatch 지표화
- Health Check 실패를 기준으로 하는 CloudWatch Alarm 추가
- 필요 시 SNS에서 Discord로 전달하는 별도 연동 검토

현재 배포 과정의 Health Check는 CD 스크립트에서 수행되며, 실패 시 배포 실패 및 롤백에 사용됩니다. 이는 CloudWatch 상시 모니터링과는 별개의 기능입니다.

## 운영 확인

AWS Console에서 다음 경로로 확인합니다.

1. CloudWatch → Alarms → `bookjeok-` 검색
2. Alarm 상태가 `OK`인지 확인
3. CloudWatch → Metrics → `CWAgent`에서 App·AI 인스턴스의 메모리·디스크 지표 확인
4. SNS Topic의 이메일 구독이 `Confirmed`인지 확인

장애를 의도적으로 발생시키는 테스트는 운영 환경에서 수행하지 않습니다. 배포 Health Check 실패 및 실제 Alarm 상태 변화는 운영 로그와 CloudWatch 상태 이력으로 확인합니다.
