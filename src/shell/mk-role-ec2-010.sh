#!/bin/bash
################################################################################
# EC2実行用IAMロール作成
#
# 新しいS3バケット構成に対応:
# - 入力バケット: ${BKT_IN} (読み取り専用)
# - 出力バケット: ${BKT_OUT} (書き込み専用)
# - SNS/SES通知権限追加
# Last updated: 2026-03-26 20:41:44
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

################################################################################
# 作成されたロールの確認
################################################################################
confirm_role() {
  cat <<EOT
  # 1. ロール一覧確認（${PRJ_PREFIX}-プレフィックス）
EOT
  aws iam list-roles --query "Roles[?RoleName && starts_with(RoleName, '${PRJ_PREFIX}-role')].{RoleName:RoleName,Arn:Arn}"

  cat <<EOT
  # 2. EC2実行ロール詳細確認
EOT
  aws iam get-role --role-name "$IAM_ROLE_EC2_NAME" 2>/dev/null || \
    echo "EC2実行ロール $IAM_ROLE_EC2_NAME は存在しません"
  
  aws iam list-attached-role-policies --role-name "$IAM_ROLE_EC2_NAME" 2>/dev/null || true
  aws iam list-role-policies --role-name "$IAM_ROLE_EC2_NAME" 2>/dev/null || true

  cat <<EOT
  # 3. インスタンスプロファイル確認
EOT
  aws iam get-instance-profile --instance-profile-name "$IAM_ROLE_EC2_NAME" 2>/dev/null || \
    echo "インスタンスプロファイル $IAM_ROLE_EC2_NAME は存在しません"
}

################################################################################
# EC2実行ロール作成処理
################################################################################
make_role() {
  cat <<EOT
  # 1-1. 既存ロール削除（存在する場合）
EOT
  aws iam remove-role-from-instance-profile \
    --instance-profile-name "$IAM_ROLE_EC2_NAME" \
    --role-name "$IAM_ROLE_EC2_NAME" 2>/dev/null && \
    echo "  インスタンスプロファイルからロール削除完了" || true
  
  aws iam delete-instance-profile \
    --instance-profile-name "$IAM_ROLE_EC2_NAME" 2>/dev/null && \
    echo "  インスタンスプロファイル削除完了" || true
  
  aws iam delete-role-policy \
    --role-name "$IAM_ROLE_EC2_NAME" \
    --policy-name "$IAM_POLICY_EC2_NAME" 2>/dev/null && \
    echo "  カスタムポリシー削除完了" || true
  
  aws iam detach-role-policy \
    --role-name "$IAM_ROLE_EC2_NAME" \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null && \
    echo "  CloudWatch管理ポリシーデタッチ完了" || true
  
  aws iam delete-role --role-name "$IAM_ROLE_EC2_NAME" 2>/dev/null && \
    echo "  既存ロール削除完了" || echo "  既存ロールは存在しませんでした"

  cat <<EOT
  # 1-2. 信頼関係ポリシー作成
EOT
  cat > ${MY_SRC_DIR}/trust-policy-ec2.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  cat <<EOT
  # 1-3. EC2実行ロール作成
EOT
  aws iam create-role \
    --role-name "$IAM_ROLE_EC2_NAME" \
    --assume-role-policy-document file://${MY_SRC_DIR}/trust-policy-ec2.json \
    --description "EC2 execution role for ${PRJ_PREFIX} system" \
    --tags "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"

  cat <<EOT
  # 1-4. AWS管理ポリシーをアタッチ
EOT
  aws iam attach-role-policy \
    --role-name "$IAM_ROLE_EC2_NAME" \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

  cat <<EOT
  # 1-5. カスタムポリシー作成
EOT
  cat > ${MY_SRC_DIR}/ec2-custom-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::$S3_BKT_IN_NAME",
        "arn:aws:s3:::$S3_BKT_IN_NAME/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::$S3_BKT_OUT_NAME",
        "arn:aws:s3:::$S3_BKT_OUT_NAME/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:*:log-group:${PRJ_PREFIX}-log-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:ResourceTag/Name": "${PRJ_PREFIX}-ec2-010"
        }
      }
    }
  ]
}
EOF

  cat <<EOT
  # 1-6. カスタムポリシーをアタッチ
EOT
  aws iam put-role-policy \
    --role-name "$IAM_ROLE_EC2_NAME" \
    --policy-name "$IAM_POLICY_EC2_NAME" \
    --policy-document file://${MY_SRC_DIR}/ec2-custom-policy.json

  cat <<EOT
  # 1-7. インスタンスプロファイル作成
EOT
  aws iam create-instance-profile --instance-profile-name "$IAM_ROLE_EC2_NAME" \
    --tags "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"

  cat <<EOT
  # 1-8. インスタンスプロファイルにロールを関連付け
EOT
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$IAM_ROLE_EC2_NAME" \
    --role-name "$IAM_ROLE_EC2_NAME"

  cat <<EOT
  # 1-9. ロール作成完了待機（AWS反映待ち）
EOT
  echo "  IAMロール作成完了。AWS反映まで少し時間がかかる場合があります。"
  sleep 10
}

################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

# メイン処理実行
date
confirm_role
make_role
confirm_role

exit 0

################################################################################
# 変更履歴:
# 2025-08-26: EC2実行用IAMロール作成スクリプト新規作成
#             - 分離バケット構成(${BKT_IN}/out)対応
#             - プレフィックスをts-からts-010-に変更
#             - 権限を読み取り/書き込み専用に分離してセキュリティ向上
#             - SNS/SES通知権限追加
#             - EC2自動停止権限追加
#             - インスタンスプロファイル作成・関連付け
#             - 既存ロール削除・再作成機能
################################################################################
