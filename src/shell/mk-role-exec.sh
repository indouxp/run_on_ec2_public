#!/bin/bash
################################################################################
# 実行用IAMロール作成 (ts-010-role-exec)
#
# 概要:
#   システム運用・実行時に必要な権限を持つロールを作成します。
#   docs/IAM_Policy_Requirements.md の「2. システム実行フェーズ」に基づき、
#   LambdaおよびEC2が保持する権限（S3アクセス、EC2操作、ログ出力等）を網羅します。
#   このロールを使用することで、ユーザーはシステムの動作をシミュレートまたは手動実行できます。
# Last updated: 2026-03-26 20:41:48
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

################################################################################
# 作成されたロールの確認
################################################################################
confirm_role() {
  cat <<EOT
  # ロール詳細確認: $IAM_ROLE_EXEC_NAME
EOT
  aws iam get-role --role-name "$IAM_ROLE_EXEC_NAME" 2>/dev/null || \
    echo "ロール $IAM_ROLE_EXEC_NAME は存在しません"
  
  aws iam list-role-policies --role-name "$IAM_ROLE_EXEC_NAME" 2>/dev/null || true
}

################################################################################
# ロール作成処理
################################################################################
make_role() {
  cat <<EOT
  # 1. 既存ロール削除（再作成のため）
EOT
  aws iam delete-role-policy \
    --role-name "$IAM_ROLE_EXEC_NAME" \
    --policy-name "${IAM_ROLE_EXEC_NAME}-policy" 2>/dev/null || true
  
  aws iam delete-role --role-name "$IAM_ROLE_EXEC_NAME" 2>/dev/null || true

  cat <<EOT
  # 2. 信頼関係ポリシー作成 (Account Rootを信頼)
EOT
  cat > ${MY_SRC_DIR}/trust-policy-exec.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  cat <<EOT
  # 3. ロール作成
EOT
  aws iam create-role \
    --role-name "$IAM_ROLE_EXEC_NAME" \
    --assume-role-policy-document file://${MY_SRC_DIR}/trust-policy-exec.json \
    --description "System Execution Role for ${PRJ_PREFIX}" \
    --tags "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"

  cat <<EOT
  # 4. カスタムポリシー定義 (システム実行権限)
EOT
  # IAM_Policy_Requirements.md の「2. システム実行フェーズ」 (Lambda + EC2権限)
  cat > ${MY_SRC_DIR}/exec-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:ListAllMyBuckets"
      ],
      "Resource": [
        "arn:aws:s3:::$S3_BKT_IN_NAME",
        "arn:aws:s3:::$S3_BKT_IN_NAME/*",
        "arn:aws:s3:::$S3_BKT_OUT_NAME",
        "arn:aws:s3:::$S3_BKT_OUT_NAME/*"
      ]
    },
    {
      "Sid": "EC2Operation",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2SelfTermination",
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
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": [
        "iam:PassRole",
        "iam:GetInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_EC2_NAME}",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_LAMBDA_NAME}",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_EXEC_NAME}"
      ]
    },
    {
      "Sid": "Notifications",
      "Effect": "Allow",
      "Action": [
        "sns:Publish",
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": [
        "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}",
        "arn:aws:ses:${AWS_REGION}:${AWS_ACCOUNT_ID}:identity/*"
      ]
    },
    {
      "Sid": "Logging",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${PRJ_PREFIX}-log-*"
    }
  ]
}
EOF

  cat <<EOT
  # 5. ポリシーをロールにアタッチ
EOT
  aws iam put-role-policy \
    --role-name "$IAM_ROLE_EXEC_NAME" \
    --policy-name "${IAM_ROLE_EXEC_NAME}-policy" \
    --policy-document file://${MY_SRC_DIR}/exec-policy.json

  echo "  ロール $IAM_ROLE_EXEC_NAME 作成完了"
}

################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }

date
confirm_role
make_role
confirm_role

exit 0
