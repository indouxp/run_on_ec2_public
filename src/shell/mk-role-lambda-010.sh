#!/bin/bash
################################################################################
# Lambda実行用IAMロール作成 (更新対応版)
#
# 新しいS3バケット構成に対応:
# - 入力バケット: ${BKT_IN} (読み取り専用)
# - 出力バケット: ${BKT_OUT} (書き込み専用)
# SNS/SES通知権限を追加
# Last updated: 2026-03-26 20:41:51
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

# config.shから変数を読み込む
ROLE_NAME="$IAM_ROLE_LAMBDA_NAME"
POLICY_NAME="$IAM_POLICY_LAMBDA_NAME"
MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

################################################################################
# 作成されたロールの確認
################################################################################
confirm_role() {
  echo "############################################################"
  echo "# ロール [$ROLE_NAME] の設定確認"
  echo "############################################################"
  
  if ! aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    echo "ロール [$ROLE_NAME] は存在しません。"
    return
  fi
  
  echo "--- ロール詳細 ---"
  aws iam get-role --role-name "$ROLE_NAME"
  echo "--- アタッチされた管理ポリシー ---"
  aws iam list-attached-role-policies --role-name "$ROLE_NAME"
  echo "--- インラインポリシー ---"
  aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME"
  echo
}

################################################################################
# Lambda実行ロール作成・更新処理
################################################################################
make_role() {
  echo "############################################################"
  echo "# ロール [$ROLE_NAME] の作成・更新処理"
  echo "############################################################"

  # 既存ロールの確認と削除
  if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "既存のロール [$ROLE_NAME] が存在します。更新のために削除・再作成します。"
    # インラインポリシーを削除 (存在しない場合もエラーにしない)
    aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" 2>/dev/null || echo "インラインポリシー [$POLICY_NAME] は存在しませんでした。"
    # 管理ポリシーをデタッチ (存在しない場合もエラーにしない)
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$MANAGED_POLICY_ARN" 2>/dev/null || echo "管理ポリシー [$MANAGED_POLICY_ARN] はアタッチされていませんでした。"
    # ロールを削除
    aws iam delete-role --role-name "$ROLE_NAME"
    echo "既存ロールの削除が完了しました。"
    sleep 5 # AWSの反映待ち
  fi

  echo "--- 信頼関係ポリシーを作成しています ---"
  cat > ${MY_SRC_DIR}/trust-policy-lambda.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  echo "--- IAMロール [$ROLE_NAME] を作成しています ---"
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://${MY_SRC_DIR}/trust-policy-lambda.json \
    --description "Lambda execution role for ts-010 system" \
    --tags "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"

  echo "--- AWS管理ポリシー [$MANAGED_POLICY_ARN] をアタッチしています ---"
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$MANAGED_POLICY_ARN"

  # AWS Account IDを取得
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

  echo "--- カスタムポリシーを作成しています (SNS/SES/EC2検索権限追加) ---"
  cat > ${MY_SRC_DIR}/lambda-custom-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$S3_BKT_IN_NAME/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::$S3_BKT_OUT_NAME/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:CreateTags",
        "iam:GetInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::*:role/ts-010-role-ec2-010"
    },
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME"
    },
    {
      "Effect": "Allow",
      "Action": "ses:SendEmail",
      "Resource": "arn:aws:ses:$AWS_REGION:$AWS_ACCOUNT_ID:identity/*"
    }
  ]
}
EOF

  echo "--- カスタムポリシー [$POLICY_NAME] をアタッチしています ---"
  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document file://${MY_SRC_DIR}/lambda-custom-policy.json
  
  echo "ロール [$ROLE_NAME] の作成・更新が完了しました。"
  echo
}

################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

# メイン処理実行
echo "実行開始: $(date)"
echo "------------------------------------------------------------"
# 実行前確認
confirm_role
# 作成・更新処理
make_role
# 実行後確認
confirm_role
echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
