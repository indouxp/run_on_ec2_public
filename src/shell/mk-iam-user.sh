#!/bin/bash
################################################################################
# IAMユーザー作成 (ts-010-user)
#
# 概要:
#   プロジェクト用IAMユーザーを作成し、構築用ロール(build)と実行用ロール(exec)への
#   AssumeRole権限を付与します。
#
# Last updated: 2026-03-26 20:37:01
################################################################################
set -euo pipefail

# スクリプト自身のディレクトリを取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)
# プロジェクトルートを取得
PROJECT_ROOT=$(cd ${SCRIPT_DIR}/../../; pwd)

# 設定ファイルを読み込む
source "${SCRIPT_DIR}/config.sh"

MY_NAME=${0##*/}
MY_SRC_DIR=./${MY_NAME}.src
LOG_PATH=${MY_NAME}.log

################################################################################
# MY_SRC_DIRの削除
################################################################################
term() {
  rm -rf "${MY_SRC_DIR:?}"
}
trap 'term; exit 1' ERR INT TERM
trap 'term' EXIT

################################################################################
# 以降ログ
################################################################################
exec >> "${LOG_PATH}" 2>&1

# アカウントID取得
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

USER_POLICY_NAME="${IAM_USER_NAME}-policy"

################################################################################
# ユーザー確認
################################################################################
confirm_user() {
  cat <<EOT
  # ユーザー詳細確認: $IAM_USER_NAME
EOT
  aws iam get-user --user-name "$IAM_USER_NAME" 2>/dev/null || \
    echo "ユーザー $IAM_USER_NAME は存在しません"
  
  aws iam list-user-policies --user-name "$IAM_USER_NAME" 2>/dev/null || true
}

################################################################################
# ユーザー作成処理
################################################################################
make_user() {
  cat <<EOT
  # 1. ユーザー作成 (存在する場合は削除して再作成)
EOT
  if aws iam get-user --user-name "$IAM_USER_NAME" >/dev/null 2>&1; then
    echo "  ユーザー $IAM_USER_NAME は既に存在します。削除して再作成します。"
    # アクセスキーを先に削除
    for key_id in $(aws iam list-access-keys --user-name "$IAM_USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
      aws iam delete-access-key --user-name "$IAM_USER_NAME" --access-key-id "$key_id"
    done
    # インラインポリシーを削除
    for policy_name in $(aws iam list-user-policies --user-name "$IAM_USER_NAME" --query 'PolicyNames[]' --output text); do
      aws iam delete-user-policy --user-name "$IAM_USER_NAME" --policy-name "$policy_name"
    done
    aws iam delete-user --user-name "$IAM_USER_NAME"
    echo "  ユーザー $IAM_USER_NAME を削除しました。"
  fi
  aws iam create-user --user-name "$IAM_USER_NAME" \
    --tags "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"
  echo "  ユーザー $IAM_USER_NAME を作成しました"

  cat <<EOT
  # 2. AssumeRoleポリシー定義
  # IAM_ROLE_BUILD_NAME(インフラ構築用)、IAM_ROLE_EXEC_NAME(スクリプト実行用)のロールへのスイッチ
  # 及び、ClaudWatchの閲覧が可能
EOT
  cat > ${MY_SRC_DIR}/user-assume-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAssumeProjectRoles",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_BUILD_NAME}",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_EXEC_NAME}"
      ]
    },
    {
      "Sid": "AllowViewLogs",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  cat <<EOT
  # 3. ポリシーをユーザーに適用 (インラインポリシー)
EOT
  aws iam put-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-name "$USER_POLICY_NAME" \
    --policy-document file://${MY_SRC_DIR}/user-assume-policy.json

  echo "  ユーザー $IAM_USER_NAME にAssumeRole権限を設定完了"
}

################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }

date
confirm_user
make_user
confirm_user

exit 0
