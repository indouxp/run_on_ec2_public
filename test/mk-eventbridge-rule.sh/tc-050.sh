#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# EventBridgeルールが存在しない状態から実行、正常処理（新規作成）
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
# テスト前処理: Lambda存在確認 + ルールを削除
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# 前提条件チェック: Lambda存在確認
if ! aws lambda get-function --function-name "${EB_LAMBDA_FUNC_NAME}" >/dev/null 2>&1; then
  echo "前提条件エラー: Lambda関数 [${EB_LAMBDA_FUNC_NAME}] が存在しません"
  echo "先に mk-lambda-terminator.sh を実行してください"
  exit 1
fi
echo "前提条件OK: Lambda関数 [${EB_LAMBDA_FUNC_NAME}] が存在します"

# ルールを削除
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
# テスト後処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
