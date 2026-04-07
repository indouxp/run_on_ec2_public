#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# ロールが存在しない状態から実行、正常処理（新規作成）
#
# Last updated: 2026-03-11 23:20:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

cp config.sh.org config.sh
. config.sh

export AWS_PROFILE=ts-usr-admin  # IAMスクリプトのテストは管理者プロファイルで実行

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
# 変更部表示
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm ${TARGET_SCRIPT}.log

# ロールを削除して存在しない状態にする
readonly MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
aws iam delete-role-policy \
  --role-name "${IAM_ROLE_LAMBDA_NAME}" \
  --policy-name "${IAM_POLICY_LAMBDA_NAME}" 2>/dev/null || true
aws iam detach-role-policy \
  --role-name "${IAM_ROLE_LAMBDA_NAME}" \
  --policy-arn "${MANAGED_POLICY_ARN}" 2>/dev/null || true
ROLE_EXISTS=$(aws iam get-role \
  --role-name "${IAM_ROLE_LAMBDA_NAME}" \
  --query 'Role.RoleName' --output text 2>/dev/null || echo "")
if [[ -n "${ROLE_EXISTS}" ]]; then
  echo "前処理: ロール [${IAM_ROLE_LAMBDA_NAME}] を削除します"
  aws iam delete-role --role-name "${IAM_ROLE_LAMBDA_NAME}"
  echo "前処理: ロール [${IAM_ROLE_LAMBDA_NAME}] を削除しました"
else
  echo "前処理: ロール [${IAM_ROLE_LAMBDA_NAME}] は存在しません（削除不要）"
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
# なし
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
