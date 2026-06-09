# Match-up MVP 로드맵

> **Source of truth: [Linear — Match-up App 프로젝트](https://linear.app/ssfak/project/match-up-app-flutter-supabase-8c50f8db4e20)**
> 이 문서는 스프린트 구조의 **요약본**입니다. 개별 작업·상태·담당·마감은 Linear(team `Jyoung`, `JY-*`)가 관리합니다.
> 목표: 7/22 스토어 배포 — 7/15 첫 제출(`JY-53`, Apple 심사 버퍼)

## 운영 규칙

- **Linear** = 계획·상태·담당·마감 (스프린트/마일스톤 단위 관리).
- **GitHub** = 코드·PR·리뷰 (구현 증거).
- **연결**: 브랜치명·커밋·PR 본문에 `JY-XX` 포함 → Linear 자동 연결.
- 작업 항목을 여기에 손으로 복제하지 말 것. 현황은 항상 Linear에서 확인한다.

## 스프린트 타임라인

| 스프린트 | 기간 | 테마 | 비고 |
|---|---|---|---|
| Sprint 1 | 5/28 ~ 6/10 | 보안 + 핵심 동선 | 보안(`JY-15`) 완료 — legacy 키 revoke 포함 |
| Sprint 2 | 6/11 ~ 6/24 | 클럽 활동 + 데이터 품질 | 클럽 활동 MVP(PR #17) 머지됨, 상세화면 UI·데이터 검증 진행 |
| Sprint 3 | 6/25 ~ 7/8 | AI·운영 + 종합 QA | 챗봇 비용·품질 모니터링(`JY-10`) 완료, 푸시·E2E QA 남음 |
| Sprint 4 | 7/9 ~ 7/22 | 배포 준비 | 약관(`JY-50`) 완료, 카카오 로그인·스토어 에셋·릴리스 빌드 남음 |

각 스프린트의 세부 작업과 진행 상태는 Linear 마일스톤에서 확인:
[Sprint 1](https://linear.app/ssfak/project/match-up-app-flutter-supabase-8c50f8db4e20) · Sprint 2 · Sprint 3 · Sprint 4 (프로젝트 보드 내 마일스톤).

## 스코프 아웃 (MVP 이후)

Linear backlog에 Low priority로 보관:

- 스피드건 production (ML 모델·정확도 테스트)
- 풋살 크롤러 소스 확보 (`JY-39`)
- 다크 모드 최적화
- 클럽 운영/추천/모집 확장 (GitHub #23)

---

> 과거 상세 체크리스트 버전(2026-05-28 스냅샷)은 git 히스토리에서 확인 가능.
> 이 문서는 Linear 도입 이후 요약본으로 경량화됨.
