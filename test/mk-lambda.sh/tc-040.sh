#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# Lambda関数が存在する状態から実行、正常処理（削除して再作成）
#
# 前提: ts-010-role-lambda-010 が存在すること（mk-role-lambda-010.sh 実行済み）
#       ts-010-role-ec2-010 が存在すること（mk-role-ec2-010.sh 実行済み）
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
# テスト前処理: Lambda関数が存在することを確認（なければ作成）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# 前提条件チェック: IAMロール存在確認
if ! aws iam get-role --role-name "${LMD_ROLE_NAME}" >/dev/null 2>&1; then
  echo "前提条件エラー: IAMロール [${LMD_ROLE_NAME}] が存在しません"
  echo "先に mk-role-lambda-010.sh を実行してください"
  exit 1
fi
echo "前提条件OK: IAMロール [${LMD_ROLE_NAME}] が存在します"

# Lambda関数が存在することを確認（なければ作成）
if aws lambda get-function --function-name "${LMD_FUNC_NAME}" >/dev/null 2>&1; then
  echo "前処理: Lambda関数 [${LMD_FUNC_NAME}] は既に存在します"
else
  ROLE_ARN=$(aws iam get-role --role-name "${LMD_ROLE_NAME}" --query 'Role.Arn' --output text)
  # ダミーのzipを作成して関数を登録
  echo "def main_handler(event, context): pass" > /tmp/lambda_dummy.py
  (cd /tmp && zip lambda_dummy.zip lambda_dummy.py)
  aws lambda create-function \
    --function-name "${LMD_FUNC_NAME}" \
    --runtime python3.12 \
    --role "${ROLE_ARN}" \
    --handler "lambda_dummy.main_handler" \
    --zip-file fileb:///tmp/lambda_dummy.zip \
    --timeout 300 \
    --memory-size 256
  rm -f /tmp/lambda_dummy.py /tmp/lambda_dummy.zip
  echo "前処理: ダミーLambda関数 [${LMD_FUNC_NAME}] を作成しました"
fi

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
