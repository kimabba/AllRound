# CLAUDE.md — Match-up

This repository uses a **small loader** rule system.

- `AGENTS.md` is the canonical always-loaded router.
- Keep this file small; do not paste long project manuals here.
- Detailed rules live under `docs/rules/` and must be read only when the task touches that area.

## Minimum mandatory rules

1. Preserve user changes; do not overwrite unrelated work.
2. Server/DB are the source of truth for auth, eligibility, visibility, quotas, and admin decisions.
3. Type safety is mandatory: no TypeScript `any`, avoid Dart `dynamic`, and require RLS/policies for new SQL tables.
4. Run relevant checks before final response, or explain why they were not run.
5. If a change needs more project context, read `AGENTS.md` and the matching rule file under `docs/rules/` first.

## Git/PR workflow

- **admin 강제 머지 금지** — 항상 PR → CI 통과 → 리뷰 → 머지 순서.
- `gh pr merge --admin` 사용하지 않음.
- main 브랜치는 보호됨 (직접 push 불가, 5개 CI 체크 필요).

## Rule index

See `AGENTS.md` for the load-on-demand map.
Start with `docs/rules/README.md` when adding, moving, or changing project rules.
