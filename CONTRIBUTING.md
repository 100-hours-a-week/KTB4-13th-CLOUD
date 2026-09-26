# 기여 가이드

## 브랜치

`main`에 직접 Push하지 않고 작업 종류에 맞는 브랜치에서 Pull Request를 생성합니다.

```text
feat/<이슈번호>-<작업명>
fix/<이슈번호>-<작업명>
chore/<이슈번호>-<작업명>
```

## 커밋

커밋 메시지는 Conventional Commits 형식을 사용합니다.

```text
<type>: <간단한 변경 내용>(#<이슈번호>)
```

주요 type은 `feat`, `fix`, `chore`, `docs`, `refactor`, `test`입니다.

## Pull Request

- 관련 Issue를 `Closes #번호` 또는 `Fixes #번호`로 연결합니다.
- 변경 이유, 주요 변경, 검증 결과, 위험과 Rollback 방법을 작성합니다.
- Workflow·배포 스크립트 변경은 실패 시 영향 범위와 복구 방법을 함께 적습니다.
- 검증이 끝난 뒤 PR을 요청합니다.
