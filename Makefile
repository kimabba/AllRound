SUPABASE ?= supabase
# 원격 Supabase 프로젝트 ref (make backend 에서 사용)
PROJECT_REF ?= bsjdgwmveokanclqwtvx
# iOS Simulator: ffmpeg_kit arm64 미지원으로 현재 macOS 로 실행
# 추후 iOS 빌드 준비되면: DEVICE_ID = 35686810-DADA-43C3-B3BF-E420C50AFF8B
DEVICE_ID := macos

.PHONY: setup backend app admin check deps reset

# ────────────────────────────────────────────────────
# macOS 시스템 의존성 (ffmpeg_kit_flutter_new 요구)
# ────────────────────────────────────────────────────
deps:
	brew install fontconfig zlib fribidi harfbuzz glib pcre2 graphite2 libiconv libsamplerate srt

# ────────────────────────────────────────────────────
# DB reset 후 시뮬레이터 앱 캐시 초기화
# (make setup 이후 세션 불일치 방지)
# ────────────────────────────────────────────────────
reset:
	# macOS 앱 데이터 삭제 (세션 캐시 초기화)
	rm -rf ~/Library/Containers/kr.matchpoint.app 2>/dev/null || true
	find ~/Library/Preferences -name "*matchpoint*" -delete 2>/dev/null || true
	# iOS 시뮬레이터 앱 삭제
	xcrun simctl boot 35686810-DADA-43C3-B3BF-E420C50AFF8B 2>/dev/null || true
	xcrun simctl uninstall 35686810-DADA-43C3-B3BF-E420C50AFF8B kr.matchpoint.app 2>/dev/null || true
	@echo "앱 캐시 초기화 완료. make app 으로 재실행하세요."

# ────────────────────────────────────────────────────
# 최초 1회 — 로컬 개발 환경 (Docker Desktop 필요, 현재 미사용)
# ────────────────────────────────────────────────────
setup:
	@echo "1) Supabase 로컬 스택 기동..."
	$(SUPABASE) start
	@echo "2) 마이그레이션 + 시드 적용..."
	$(SUPABASE) db reset
	@echo ""
	@echo "SUPABASE_ANON_KEY 를 복사해서 app/.env.local 에 붙여넣으세요:"
	@$(SUPABASE) status | grep -i "publishable\|anon"

# ────────────────────────────────────────────────────
# 매일 개발 — 터미널 두 개 열기
# ────────────────────────────────────────────────────

# 터미널 1: 백엔드 (Edge Functions 로컬 핫리로드 → 원격 DB 연결)
backend:
	@test -f supabase/functions/.env || (echo "supabase/functions/.env 파일이 없습니다. .env.example 을 복사해서 GEMINI_API_KEY 를 채우세요." && exit 1)
	$(SUPABASE) functions serve --env-file ./supabase/functions/.env --project-ref $(PROJECT_REF)

# 터미널 2: Flutter 앱 — 일반 사용자 (모바일 레이아웃)
app:
	@test -f app/.env.local || (echo "app/.env.local 파일이 없습니다. app/.env.local.example 을 복사해서 anon key 를 채우세요." && exit 1)
	cd app && flutter run -d $(DEVICE_ID) --dart-define-from-file=.env.local

# 터미널 3: 웹 어드민 대시보드 (Chrome)
admin:
	@test -f app/.env.local || (echo "app/.env.local 파일이 없습니다. app/.env.local.example 을 복사해서 anon key 를 채우세요." && exit 1)
	cd app && flutter run -d chrome --dart-define-from-file=.env.local --dart-define=ADMIN_MODE=true

# ────────────────────────────────────────────────────
# 정적 검증
# ────────────────────────────────────────────────────
check:
	cd app && flutter analyze
	cd supabase/functions && deno lint
