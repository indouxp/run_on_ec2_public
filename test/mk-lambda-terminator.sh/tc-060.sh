#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# Lambda関数設定の検証
# - 関数が存在すること
# - ランタイムが python3.12 であること
# - ハンドラが terminator_lambda_function.handler であること
# - IAMロール ts-010-role-lambda-020 が設定されていること
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
# テスト前処理: Lambda関数を削除（クリーンな状態から）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

aws lambda delete-function --function-name "${TERM_FUNC_NAME}" 2>/dev/null || true
echo "前処理: Lambda関数 [${TERM_FUNC_NAME}] を削除（あれば）"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理: Lambda関数設定検証
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# Lambda関数設定検証"

RUNTIME=$(aws lambda get-function --function-name "${TERM_FUNC_NAME}" \
  --query 'Configuration.Runtime' --output text 2>/dev/null || echo "")

if [[ -n "${RUNTIME}" && "${RUNTIME}" != "None" ]]; then
  echo "[OK] Lambda関数 [${TERM_FUNC_NAME}] が存在します"
else
  echo "[NG] Lambda関数 [${TERM_FUNC_NAME}] が存在しません"
fi

if [[ "${RUNTIME}" == "python3.12" ]]; then
  echo "[OK] ランタイム: ${RUNTIME}"
else
  echo "[NG] ランタイムが不正: ${RUNTIME}（期待値: python3.12）"
fi

HANDLER=$(aws lambda get-function --function-name "${TERM_FUNC_NAME}" \
  --query 'Configuration.Handler' --output text 2>/dev/null || echo "")
if [[ "${HANDLER}" == "terminator_lambda_function.handler" ]]; then
  echo "[OK] ハンドラ: ${HANDLER}"
else
  echo "[NG] ハンドラが不正: ${HANDLER}（期待値: terminator_lambda_function.handler）"
fi

ROLE_ARN=$(aws lambda get-function --function-name "${TERM_FUNC_NAME}" \
  --query 'Configuration.Role' --output text 2>/dev/null || echo "")
EXPECTED_ROLE_ARN=$(aws iam get-role --role-name "${TERM_ROLE_NAME}" \
  --query 'Role.Arn' --output text 2>/dev/null || echo "")
if [[ "${ROLE_ARN}" == "${EXPECTED_ROLE_ARN}" ]]; then
  echo "[OK] IAMロール: ${TERM_ROLE_NAME}"
else
  echo "[NG] IAMロールが不正: ${ROLE_ARN}（期待値: ${EXPECTED_ROLE_ARN}）"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
