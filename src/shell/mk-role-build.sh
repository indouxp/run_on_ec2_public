#!/bin/bash
################################################################################
# インフラ構築用IAMロール作成 (ts-010-role-build)
#
# 概要:
#   管理者がシステム構築スクリプトを実行するために必要な権限を持つロールを作成します。
#   docs/IAM_Policy_Requirements.md の「1. インフラ構築フェーズ」に基づきます。
# Last updated: 2026-03-26 20:41:41
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
  # ロール詳細確認: $IAM_ROLE_BUILD_NAME
EOT
  aws iam get-role --role-name "$IAM_ROLE_BUILD_NAME" 2>/dev/null || \
    echo "ロール $IAM_ROLE_BUILD_NAME は存在しません"
  
  aws iam list-role-policies --role-name "$IAM_ROLE_BUILD_NAME" 2>/dev/null || true
}

################################################################################
# ロール作成処理
################################################################################
make_role() {
  cat <<EOT
  # 1. 既存ロール削除（再作成のため）
EOT
  # インラインポリシー削除
  aws iam delete-role-policy \
    --role-name "$IAM_ROLE_BUILD_NAME" \
    --policy-name "${IAM_ROLE_BUILD_NAME}-policy" 2>/dev/null || true
  
  # ロール削除
  aws iam delete-role --role-name "$IAM_ROLE_BUILD_NAME" 2>/dev/null || true

  cat <<EOT
  # 2. 信頼関係ポリシー作成 (Account Rootを信頼 - UserポリシーでAssumeRoleを制御)
EOT
  cat > ${MY_SRC_DIR}/trust-policy-build.json << EOF
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
    --role-name "$IAM_ROLE_BUILD_NAME" \
    --assume-role-policy-document file://${MY_SRC_DIR}/trust-policy-build.json \
    --description "Infrastructure Build Role for ${PRJ_PREFIX}" \
    --tags "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"

  cat <<EOT
  # 4. カスタムポリシー定義 (インフラ構築権限)
EOT
  cat > ${MY_SRC_DIR}/build-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IAMManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:ListRoles", "iam:PassRole",
        "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:ListPolicies",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
        "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
        "iam:ListInstanceProfiles", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        "iam:TagRole", "iam:UntagRole",
        "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
        "iam:TagUser", "iam:UntagUser"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2VPCManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute", "ec2:DescribeVpcAttribute",
        "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:DescribeInternetGateways",
        "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
        "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
        "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable",
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateKeyPair", "ec2:DeleteKeyPair", "ec2:DescribeKeyPairs",
        "ec2:RunInstances", "ec2:TerminateInstances", "ec2:DescribeInstances", "ec2:CreateTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3Management",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket", "s3:ListAllMyBuckets", "s3:GetBucketLocation",
        "s3:PutBucketPolicy", "s3:GetBucketPolicy", "s3:DeleteBucketPolicy",
        "s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock",
        "s3:PutEncryptionConfiguration", "s3:GetEncryptionConfiguration",
        "s3:PutBucketVersioning", "s3:GetBucketVersioning",
        "s3:ListBucketVersions", "s3:DeleteObjectVersion",
        "s3:PutLifecycleConfiguration", "s3:GetLifecycleConfiguration",
        "s3:PutBucketNotification", "s3:GetBucketNotification",
        "s3:PutBucketOwnershipControls", "s3:GetBucketOwnershipControls",
        "s3:PutBucketTagging", "s3:GetBucketTagging"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaManagement",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
        "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy",
        "lambda:ListFunctions", "lambda:ListTags", "lambda:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsManagement",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy", "logs:DeleteLogStream", "logs:DescribeLogStreams",
        "logs:TagLogGroup", "logs:PutMetricFilter", "logs:DeleteMetricFilter",
        "logs:DescribeMetricFilters"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EventBridgeManagement",
      "Effect": "Allow",
      "Action": [
        "events:PutRule", "events:DeleteRule", "events:DescribeRule", "events:ListRules",
        "events:PutTargets", "events:RemoveTargets", "events:ListTargetsByRule", "events:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudTrailManagement",
      "Effect": "Allow",
      "Action": [
        "cloudtrail:CreateTrail", "cloudtrail:DeleteTrail", "cloudtrail:DescribeTrails",
        "cloudtrail:GetTrail", "cloudtrail:StartLogging", "cloudtrail:StopLogging",
        "cloudtrail:PutEventSelectors", "cloudtrail:AddTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SNSManagement",
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic", "sns:DeleteTopic", "sns:GetTopicAttributes",
        "sns:SetTopicAttributes", "sns:Subscribe", "sns:ListTopics", "sns:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSUtils",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  cat <<EOT
  # 5. ポリシーをロールにアタッチ
EOT
  aws iam put-role-policy \
    --role-name "$IAM_ROLE_BUILD_NAME" \
    --policy-name "${IAM_ROLE_BUILD_NAME}-policy" \
    --policy-document file://${MY_SRC_DIR}/build-policy.json

  echo "  ロール $IAM_ROLE_BUILD_NAME 作成完了"
}

################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

date
confirm_role
make_role
confirm_role

exit 0
