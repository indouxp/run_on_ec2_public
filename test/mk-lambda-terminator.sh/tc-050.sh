#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# Lambda関数が存在しない状態から実行、正常処理（新規作成）
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
# テスト前処理: Lambda関数とIAMロールを削除（クリーンな状態から）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# Lambda関数を削除
aws lambda delete-function --function-name "${TERM_FUNC_NAME}" 2>/dev/null || true
echo "前処理: Lambda関数 [${TERM_FUNC_NAME}] を削除（あれば）"

# IAMロールをクリーンアップ
aws iam detach-role-policy --role-name "${TERM_ROLE_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role-policy --role-name "${TERM_ROLE_NAME}" \
  --policy-name "ts-010-policy-lambda-020" 2>/dev/null || true
aws iam delete-role --role-name "${TERM_ROLE_NAME}" 2>/dev/null || true
echo "前処理: IAMロール [${TERM_ROLE_NAME}] を削除（あれば）"

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
