# 개발 EKS 배포 설정

실행 중인 dev 백엔드와 CPU AI를 공통 Helm Chart로 관리하기 위한 구성입니다. ECS 배포와 Route53 설정은 이 디렉터리에서 관리하지 않습니다.

## 디렉터리

- `charts/application`: Deployment, Service, ServiceAccount, ExternalSecret, 선택적 HPA 공통 Chart
- `environments/dev/backend.values.yaml`: 백엔드 이미지 digest, Probe, 자원, NodePort, ESO 참조
- `environments/dev/ai.values.yaml`: CPU AI 이미지 digest, Probe, 자원, 전용 노드 배치, ESO 참조
- `bootstrap/argocd`: Argo CD v3.6.1 공식 설치와 개발용 자원 설정
- `argocd`: dev 전용 AppProject와 수동 동기화 Application 두 개

실제 비밀번호·API 키·Kubernetes Secret은 포함하지 않습니다. ExternalSecret에는 AWS Parameter Store 경로만 기록합니다. EKS 백엔드는 `AI_BASE_URL`을 EKS 전용 Parameter Store 경로 `/bookjeok/eks/dev/AI_BASE_URL`에서 받습니다.

## 배포 소유권

백엔드 HPA가 실행 중인 replicas를 관리하며, Application은 `/spec/replicas` 차이를 무시합니다. 개발 백엔드는 현재 HPA 범위가 2~2이므로 첫 인계 때 일시적으로 기본값인 1개로 축소되지 않도록 Chart에도 초기 복제본 2개를 명시합니다. AI replicas는 Values로 관리합니다. 기존 Pod selector·Service 이름·NodePort·Probe·이미지 digest를 유지했습니다. 첫 인계 때 불필요한 재배포를 피하도록 기존 재시작 annotation도 보존했습니다.

첫 Application 연결은 수동 동기화입니다. 자동 동기화·prune·selfHeal은 켜지 않습니다. Application 삭제 시 앱 리소스를 자동 삭제하는 finalizer도 넣지 않았습니다. main에 이 구성이 반영된 뒤 Application을 연결합니다.

공통 Chart는 두 서비스의 단일 앱 컨테이너를 지원합니다. 환경변수·Probe·lifecycle·자원은 `container`, 노드 선택·toleration·종료 유예·ServiceAccount는 `podSpec`에 지정합니다. 운영 환경 Values는 이번에 만들지 않았습니다.

## 확인 방법

```sh
helm lint gitops/charts/application -f gitops/environments/dev/backend.values.yaml
helm lint gitops/charts/application -f gitops/environments/dev/ai.values.yaml
helm template dev-backend gitops/charts/application -n dev -f gitops/environments/dev/backend.values.yaml
helm template dev-ai gitops/charts/application -n dev -f gitops/environments/dev/ai.values.yaml
```

서버에서 실제 변경 없이 검증하려면 렌더링 파일에 `kubectl apply --dry-run=server`를 사용합니다. 이 작업에서 렌더링/서버 검증을 통과했고, 양쪽 Deployment Pod template·strategy와 Service spec이 현재와 동일함을 확인했습니다. GitHub Actions는 이번에 변경하지 않았습니다.

## Argo CD 설치와 연결

```sh
kubectl apply --server-side -k gitops/bootstrap/argocd
# PR 병합으로 main에 chart/values가 존재한 뒤:
kubectl apply -f gitops/argocd/project.yaml
kubectl apply -f gitops/argocd/dev-backend.yaml -f gitops/argocd/dev-ai.yaml
kubectl port-forward -n argocd svc/argocd-server 18443:443
```

브라우저에서 `https://localhost:18443`에 접속합니다. 초기 인증서는 자체 서명입니다. 초기 관리자 비밀번호는 argocd-initial-admin-secret에서 본인 터미널로 조회하고 로그인 후 변경합니다. Secret은 파일이나 Git에 저장하지 않습니다.

Dex SSO·ApplicationSet·알림 컨트롤러는 현재 사용하지 않아 replicas 0으로 설치합니다. 서버·repo-server·application-controller·Redis는 각각 1개입니다. Argo CD도 노드 자원을 사용하므로 pod/메모리 여유가 부족하면 CA가 일반 노드를 증설할 수 있습니다.

## 기존 인프라와 경계

VPC·EKS·노드 그룹·IAM·Calico·ESO·LBC·CA·SecretStore·Gateway·통신 정책·모니터링 수집기는 이미 설치된 선행 인프라입니다. 이 앱 Chart가 해당 인프라를 덮어쓰지 않습니다. 노드 주소를 갱신하는 node-ingress-sync의 NetworkPolicy도 앱 Application에 넣지 않았습니다. 별도 플랫폼 Application으로 편입할 때 컨트롤러 소유 필드와 Helm 릴리스 인계를 검토해야 합니다.

## 되돌리기

이 단계는 기존 이미지·실행 설정을 보존합니다. 이후 배포를 되돌릴 때는 Values를 이전 커밋으로 복구하고 수동 Sync 합니다. Application 연결만 해제하려면 자동 삭제 finalizer가 없는 Application 두 개를 삭제합니다. `argocd` Namespace 삭제는 Argo CD 구성요소를 제거하므로 별도 계획 후 진행합니다. 기존 앱 Namespace `dev`는 삭제하지 않습니다.

참고: https://argo-cd.readthedocs.io/en/stable/getting_started/
