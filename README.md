# KTB4-13th Cloud

운영 Release와 통합 CD를 관리하는 저장소입니다.

서비스 저장소의 CI는 각 서비스 이미지를 ECR에 SHA 태그로 게시하고, 이 저장소의 Release Manifest가 운영에 배포할 버전을 결정합니다.

## Release 흐름

1. Backend·AI·Frontend의 검증된 버전을 Release Manifest에 기록합니다.
2. `v*` 태그를 생성합니다.
3. CD가 Manifest와 ECR 이미지를 검증합니다.
4. `production` Environment 승인 후 AI → Backend → Frontend 순서로 배포합니다.

운영 배포 Workflow와 스크립트는 `.github/workflows/`와 `scripts/`에서 관리합니다.

기여 방법은 [CONTRIBUTING.md](CONTRIBUTING.md)를 참고합니다.

Release Manifest는 `scripts/verify-release.sh`로 Git tag와 버전 값을 검증합니다.
