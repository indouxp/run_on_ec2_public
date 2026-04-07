#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# EventBridgeルール設定の検証
# - ルールが存在すること
# - ターゲット（Lambda）が設定されていること
# - ルールが ENABLED 状態であること
#
# 前提: ts-010-lmd-020 が存在すること（mk-lambda-terminator.sh 実行済み）
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
# テスト前処理: Lambda存在確認 + ルールを削除（クリーンな状態から）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# 前提条件チェック: Lambda存在確認
if ! aws lambda get-function --function-name "${EB_LAMBDA_FUNC_NAME}" >/dev/null 2>&1; then
  echo "前提条件エラー: Lambda関数 [${EB_LAMBDA_FUNC_NAME}] が存在しません"
  echo "先に mk-lambda-terminator.sh を実行してください"
  exit 1
fi
echo "前提条件OK: Lambda関数 [${EB_LAMBDA_FUNC_NAME}] が存在します"

# ルールを削除（クリーンな状態から）
aws events remove-targets --rule "${RULE_NAME}" --ids "1" 2>/dev/null || true
aws lambda remove-permission \
  --function-name "${EB_LAMBDA_FUNC_NAME}" \
  --statement-id "EventBridgeInvoke-${RULE_NAME}" 2>/dev/null || true
aws events delete-rule --name "${RULE_NAME}" 2>/dev/null || true
echo "前処理: EventBridgeルール [${RULE_NAME}] を削除（あれば）"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理: EventBridgeルール設定検証
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# EventBridgeルール設定検証"

# ルール存在確認
RULE_STATE=$(aws events describe-rule --name "${RULE_NAME}" \
  --query 'State' --output text 2>/dev/null || echo "")

if [[ -n "${RULE_STATE}" ]]; then
  echo "[OK] EventBridgeルール [${RULE_NAME}] が存在します"
else
  echo "[NG] EventBridgeルール [${RULE_NAME}] が存在しません"
fi

if [[ "${RULE_STATE}" == "ENABLED" ]]; then
  echo "[OK] ルール状態: ENABLED"
else
  echo "[NG] ルール状態が不正: ${RULE_STATE}（期待値: ENABLED）"
fi

# ターゲット確認
TARGET_ARN=$(aws events list-targets-by-rule --rule "${RULE_NAME}" \
  --query 'Targets[0].Arn' --output text 2>/dev/null || echo "")

LAMBDA_ARN=$(aws lambda get-function --function-name "${EB_LAMBDA_FUNC_NAME}" \
  --query 'Configuration.FunctionArn' --output text 2>/dev/null || echo "")

if [[ "${TARGET_ARN}" == "${LAMBDA_ARN}" ]]; then
  echo "[OK] ターゲット Lambda [${EB_LAMBDA_FUNC_NAME}] が設定されています"
else
  echo "[NG] ターゲット設定が不正: ${TARGET_ARN}"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
