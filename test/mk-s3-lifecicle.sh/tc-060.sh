#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# ライフサイクルルール設定検証
# mk-s3-lifecicle.sh 実行後、以下を確認する
# - バケットにライフサイクルルールが存在すること
# - ルールの Status が Enabled であること
# - Expiration.Days が指定値（${TEST_EXPIRE_DAYS}）であること
#
# 前提: ${BKT_IN} が存在すること（mk-s3bkt.sh 実行済み）
#
# Last updated: 2026-03-19 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

cp config.sh.org config.sh

. assume-role.sh

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
# 変更部表示
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理: バケット存在確認 + ライフサイクル設定を削除
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# 前提条件チェック
if ! aws s3api head-bucket --bucket "${TEST_BUCKET}" 2>/dev/null; then
  echo "前提条件エラー: バケット [${TEST_BUCKET}] が存在しません"
  echo "mk-s3bkt.sh を先に実行してください"
  exit 1
fi

# 既存ライフサイクル設定を削除
aws s3api delete-bucket-lifecycle --bucket "${TEST_BUCKET}" 2>/dev/null || true
echo "前処理: ライフサイクル設定を削除（あれば）[${TEST_BUCKET}]"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-s3-lifecicle.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT} "${TEST_BUCKET}" "${TEST_EXPIRE_DAYS}"
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（ライフサイクルルール設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# ライフサイクルルール設定検証: ${TEST_BUCKET}"

# ルール存在確認
RULES=$(aws s3api get-bucket-lifecycle-configuration \
  --bucket "${TEST_BUCKET}" \
  --query 'Rules' \
  --output json 2>/dev/null || echo '[]')

if [[ "${RULES}" == "[]" ]] || [[ -z "${RULES}" ]]; then
  echo "[NG] バケット [${TEST_BUCKET}] にライフサイクルルールが存在しません"
  exit 1
fi
echo "[OK] ライフサイクルルールが存在します"

# Status=Enabled 確認
STATUS=$(aws s3api get-bucket-lifecycle-configuration \
  --bucket "${TEST_BUCKET}" \
  --query 'Rules[0].Status' \
  --output text 2>/dev/null || echo "None")
if [[ "${STATUS}" == "Enabled" ]]; then
  echo "[OK] Status: Enabled"
else
  echo "[NG] Status が想定外です: ${STATUS}（期待値: Enabled）"
  exit 1
fi

# Expiration.Days 確認
DAYS=$(aws s3api get-bucket-lifecycle-configuration \
  --bucket "${TEST_BUCKET}" \
  --query 'Rules[0].Expiration.Days' \
  --output text 2>/dev/null || echo "None")
if [[ "${DAYS}" == "${TEST_EXPIRE_DAYS}" ]]; then
  echo "[OK] Expiration.Days: ${DAYS}"
else
  echo "[NG] Expiration.Days が想定外です: ${DAYS}（期待値: ${TEST_EXPIRE_DAYS}）"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
