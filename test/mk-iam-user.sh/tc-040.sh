#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# ユーザーが存在する状態から実行、正常処理（削除して再作成）
#
# Last updated: 2026-03-18
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

# ユーザーが存在しない場合は作成
USER_EXISTS=$(aws iam get-user \
  --user-name "${IAM_USER_NAME}" \
  --query 'User.UserName' --output text 2>/dev/null || echo "")
if [[ -n "${USER_EXISTS}" ]]; then
  echo "前処理: ユーザー [${IAM_USER_NAME}] は既に存在します"
else
  echo "前処理: ユーザー [${IAM_USER_NAME}] を作成します"
  aws iam create-user --user-name "${IAM_USER_NAME}"
  echo "前処理: ユーザー [${IAM_USER_NAME}] を作成しました"
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
