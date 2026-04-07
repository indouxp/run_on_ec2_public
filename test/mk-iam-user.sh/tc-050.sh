#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# ユーザーが存在しない状態から実行、正常処理（新規作成）
#
# Last updated: 2026-03-11 22:30:00
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

# ユーザーを削除して存在しない状態にする
USER_EXISTS=$(aws iam get-user \
  --user-name "${IAM_USER_NAME}" \
  --query 'User.UserName' --output text 2>/dev/null || echo "")
if [[ -n "${USER_EXISTS}" ]]; then
  echo "前処理: ユーザー [${IAM_USER_NAME}] を削除します"

  # アクセスキーを削除（残っていると delete-user が DeleteConflict で失敗する）
  for KEY_ID in $(aws iam list-access-keys \
      --user-name "${IAM_USER_NAME}" \
      --query 'AccessKeyMetadata[*].AccessKeyId' --output text); do
    echo "前処理: アクセスキー [${KEY_ID}] を削除します"
    aws iam delete-access-key --user-name "${IAM_USER_NAME}" --access-key-id "${KEY_ID}"
  done

  # インラインポリシーを削除
  aws iam delete-user-policy \
    --user-name "${IAM_USER_NAME}" \
    --policy-name "${IAM_USER_NAME}-policy" 2>/dev/null || true

  # ユーザーを削除
  aws iam delete-user --user-name "${IAM_USER_NAME}"
  echo "前処理: ユーザー [${IAM_USER_NAME}] を削除しました"
else
  echo "前処理: ユーザー [${IAM_USER_NAME}] は存在しません（削除不要）"
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
