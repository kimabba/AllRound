#!/bin/bash
# =============================================================================
# Android 릴리스 서명 키 생성 스크립트
# =============================================================================
# 사전 조건: JDK 설치 필요 (brew install openjdk)
#
# 실행: cd app/android && bash generate-keystore.sh
# =============================================================================

set -e

KEYSTORE_DIR="keystore"
KEYSTORE_FILE="$KEYSTORE_DIR/upload-keystore.jks"
KEY_ALIAS="allround-upload"
VALIDITY_DAYS=10000

mkdir -p "$KEYSTORE_DIR"

if [ -f "$KEYSTORE_FILE" ]; then
  echo "이미 존재합니다: $KEYSTORE_FILE"
  echo "새로 생성하려면 기존 파일을 삭제하세요."
  exit 1
fi

echo "=== Android 릴리스 서명 키 생성 ==="
echo ""
echo "비밀번호를 입력하세요 (최소 6자):"

keytool -genkey -v \
  -keystore "$KEYSTORE_FILE" \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$VALIDITY_DAYS" \
  -storetype JKS

echo ""
echo "=== 키 생성 완료 ==="
echo ""
echo "key.properties 파일을 생성하세요:"
echo ""
echo "  storePassword=<입력한 비밀번호>"
echo "  keyPassword=<입력한 비밀번호>"
echo "  keyAlias=$KEY_ALIAS"
echo "  storeFile=../$KEYSTORE_FILE"
echo ""
echo "중요: $KEYSTORE_FILE 파일을 안전한 곳에 백업하세요."
echo "      이 파일을 잃어버리면 앱 업데이트를 할 수 없습니다."
