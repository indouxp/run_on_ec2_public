#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# Lambda関数設定の検証
# - 関数が存在すること
# - ランタイムが python3.12 であること
# - ハンドラが lambda_function.main_handler であること
# - タイムアウトが 300 秒であること
#
# 前提: ts-010-role-lambda-010 が存在すること（mk-role-lambda-010.sh 実行済み）
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

# 前提条件チェック: IAMロール存在確認
if ! aws iam get-role --role-name "${LMD_ROLE_NAME}" >/dev/null 2>&1; then
  echo "前提条件エラー: IAMロール [${LMD_ROLE_NAME}] が存在しません"
  echo "先に mk-role-lambda-010.sh を実行してください"
  exit 1
fi
echo "前提条件OK: IAMロール [${LMD_ROLE_NAME}] が存在します"

aws lambda delete-function --function-name "${LMD_FUNC_NAME}" 2>/dev/null || true
echo "前処理: Lambda関数 [${LMD_FUNC_NAME}] を削除（あれば）"

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

RUNTIME=$(aws lambda get-function --function-name "${LMD_FUNC_NAME}" \
  --query 'Configuration.Runtime' --output text 2>/dev/null || echo "")

if [[ -n "${RUNTIME}" && "${RUNTIME}" != "None" ]]; then
  echo "[OK] Lambda関数 [${LMD_FUNC_NAME}] が存在します"
else
  echo "[NG] Lambda関数 [${LMD_FUNC_NAME}] が存在しません"
fi

if [[ "${RUNTIME}" == "python3.12" ]]; then
  echo "[OK] ランタイム: ${RUNTIME}"
else
  echo "[NG] ランタイムが不正: ${RUNTIME}（期待値: python3.12）"
fi

HANDLER=$(aws lambda get-function --function-name "${LMD_FUNC_NAME}" \
  --query 'Configuration.Handler' --output text 2>/dev/null || echo "")
if [[ "${HANDLER}" == "lambda_function.main_handler" ]]; then
  echo "[OK] ハンドラ: ${HANDLER}"
else
  echo "[NG] ハンドラが不正: ${HANDLER}（期待値: lambda_function.main_handler）"
fi

TIMEOUT=$(aws lambda get-function --function-name "${LMD_FUNC_NAME}" \
  --query 'Configuration.Timeout' --output text 2>/dev/null || echo "")
if [[ "${TIMEOUT}" == "300" ]]; then
  echo "[OK] タイムアウト: ${TIMEOUT}秒"
else
  echo "[NG] タイムアウトが不正: ${TIMEOUT}（期待値: 300）"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
