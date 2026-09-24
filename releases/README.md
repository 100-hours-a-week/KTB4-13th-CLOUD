# Release Manifest

운영 배포할 버전을 하나의 Manifest로 묶습니다.

```yaml
release: v1.2.0
frontend_sha: abc1234
backend_sha: def5678
ai_sha: ghi9012
```

Manifest의 `release` 값과 Git tag는 동일해야 하며, 각 SHA는 해당 서비스 CI가 ECR에 게시한 이미지 태그와 연결됩니다.
