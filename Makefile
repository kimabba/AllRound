SUPABASE ?= supabase
# 원격 Supabase 프로젝트 ref (make backend 에서 사용)
PROJECT_REF ?= bsjdgwmveokanclqwtvx
# 기본 실행 대상. iOS 시뮬레이터/실기기로 돌리려면:
#   make app DEVICE_ID=<flutter devices 의 id>
# 실기기는 --release 필수 (debug 는 iOS 26 ProMotion 크래시 flutter#183900)
DEVICE_ID ?= macos

.PHONY: setup backend app admin web check reset release-android release-ios

# ────────────────────────────────────────────────────
# iOS/macOS 의존성 = Swift Package Manager (CocoaPods 사용 안 함)
# ────────────────────────────────────────────────────
# 플러그인이 전부 Swift Package 라서 2026-07 에 CocoaPods 를 완전히 걷어냈다
# (Podfile · Podfile.lock · [CP] 빌드 페이즈 · Pods xcconfig include 제거).
# 남겨두면 빌드마다 pod install 이 빈 Pods 프로젝트를 만들며 pbxproj·Podfile.lock
# 을 다시 써서 워킹트리가 더러워졌다. brew install cocoapods 도 이제 불필요.
# 새 플러그인이 SPM 미지원이면 flutter 가 Podfile 을 자동 생성하므로 그때 복원하면 된다.

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

# 터미널 3: 웹빌드 — 로컬 전용 (빌드 후 로컬 서버, 배포 안 함 · JY-81)
web:
	@test -f app/.env.local || (echo "app/.env.local 파일이 없습니다." && exit 1)
	cd app && flutter build web --dart-define-from-file=.env.local
	@echo ""
	@echo "✅ 웹빌드 완료 — http://localhost:8080 에서 접속 가능"
	@echo "   종료: Ctrl+C"
	@echo ""
	cd app && python3 -m http.server 8080 --directory build/web/

# 터미널 4: 웹 어드민 대시보드 (Chrome)
admin:
	@test -f app/.env.local || (echo "app/.env.local 파일이 없습니다. app/.env.local.example 을 복사해서 anon key 를 채우세요." && exit 1)
	cd app && flutter run -d chrome --web-port=3000 --dart-define-from-file=.env.local --dart-define=ADMIN_MODE=true

# ────────────────────────────────────────────────────
# 프로덕션 릴리스 빌드 (스토어 제출용)
# ────────────────────────────────────────────────────
# 전제(모두 gitignore — 빌드하는 사람 로컬에만 존재):
#   · app/android/key.properties + 서명 .jks  (Play 업로드용 서명)
#   · app/android/app/google-services.json     (구글 로그인/FCM)
#   · app/.env.local 에 프로덕션 SUPABASE_URL / SUPABASE_ANON_KEY / API_BASE_URL
#     (구글 로그인은 signInWithOAuth 라 앱 클라이언트 ID 불필요 — Supabase 설정 사용)
# --release → kReleaseMode=true 라 config.dart 의 개발용 우회 플래그
#   (ADMIN_MODE / *_DESIGN_PREVIEW) 가드가 활성화된다 (JY-6). 프로덕션 빌드에
#   dev 플래그가 새면 앱이 시작 즉시 실패하므로 dart-define 에 절대 넣지 않는다.

release-android:
	@test -f app/.env.local || (echo "❌ app/.env.local 없음" && exit 1)
	@test -f app/android/key.properties || (echo "❌ app/android/key.properties 없음 — 없이 빌드하면 debug 서명이라 Play 업로드 불가" && exit 1)
	cd app && flutter build appbundle --release --dart-define-from-file=.env.local
	@echo "✅ .aab 생성: app/build/app/outputs/bundle/release/app-release.aab → Play Console 업로드"

release-ios:
	@test -f app/.env.local || (echo "❌ app/.env.local 없음" && exit 1)
	@test -f app/ios/ExportOptions.plist || (echo "❌ app/ios/ExportOptions.plist 없음 — Apple 서명/배포 설정 필요 (Apple Developer 조직 계정 승인 후 생성)" && exit 1)
	cd app && flutter build ipa --release --dart-define-from-file=.env.local --export-options-plist=ios/ExportOptions.plist
	@echo "✅ .ipa 생성: app/build/ios/ipa/ → Transporter/Xcode 로 App Store Connect 업로드"

# ────────────────────────────────────────────────────
# 정적 검증
# ────────────────────────────────────────────────────
check:
	cd app && flutter analyze
	cd supabase/functions && deno lint
