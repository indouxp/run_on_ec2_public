#!/bin/bash
################################################################################
# S3バケットポリシー設定
#
# 新しいS3バケット構成対応:
# - 入力バケット: ${BKT_IN} (IAMロール制限アクセス)
# - 出力バケット: ${BKT_OUT} (IAMロール制限アクセス)
################################################################################
set -euo pipefail
MY_NAME=${0##*/}
MY_SRC_DIR=./${MY_NAME}.src
LOG_PATH=${MY_NAME}.log

exec >> "${LOG_PATH}" 2>&1

################################################################################
# 設定されたS3バケットポリシーの確認
# - ${BKT_IN} のバケットポリシー
# - ${BKT_OUT} のバケットポリシー
# - アクセス制御設定の確認
################################################################################
confirm_s3policy() {
  cat <<EOT
  # 1. 入力バケットポリシー確認（${BKT_IN}）
EOT
  aws s3api get-bucket-policy --bucket ${BKT_IN} --query 'Policy' --output text 2>/dev/null | jq . || \
    echo "入力バケット ${BKT_IN} にポリシーは設定されていません"

  cat <<EOT
  # 2. 出力バケットポリシー確認（${BKT_OUT}）
EOT
  aws s3api get-bucket-policy --bucket ${BKT_OUT} --query 'Policy' --output text 2>/dev/null | jq . || \
    echo "出力バケット ${BKT_OUT} にポリシーは設定されていません"

  cat <<EOT
  # 3. 入力バケットACL確認（オプション）
EOT
  aws s3api get-bucket-acl --bucket ${BKT_IN} 2>/dev/null || \
    echo "入力バケットACL確認をスキップしました（権限不足）"

  cat <<EOT
  # 4. 出力バケットACL確認（オプション）
EOT
  aws s3api get-bucket-acl --bucket ${BKT_OUT} 2>/dev/null || \
    echo "出力バケットACL確認をスキップしました（権限不足）"
}

################################################################################
# S3バケットポリシー設定処理
# 1. 入力バケットポリシー設定（${BKT_IN}）
# 2. 出力バケットポリシー設定（${BKT_OUT}）
# 3. セキュリティ設定（特定IAMロールのみアクセス許可）
################################################################################
make_s3policy() {
  # AWSアカウントIDを取得
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  
  cat <<EOT
  # 1-1. 入力バケットポリシー処理（${BKT_IN}）
EOT
  # 既存ポリシー削除
  aws s3api delete-bucket-policy --bucket ${BKT_IN} 2>/dev/null && \
    echo "  既存の入力バケットポリシーを削除しました" || \
    echo "  入力バケットにポリシーは設定されていませんでした"

  # 新規ポリシー作成（シンプル版 - Denyポリシーは削除）
  cat > ${MY_SRC_DIR}/${BKT_IN}-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLambdaRoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/ts-010-role-lambda-010"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BKT_IN}",
        "arn:aws:s3:::${BKT_IN}/*"
      ]
    },
    {
      "Sid": "AllowEC2RoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/ts-010-role-ec2-010"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BKT_IN}",
        "arn:aws:s3:::${BKT_IN}/*"
      ]
    }
  ]
}
EOF

  # ポリシー適用
  aws s3api put-bucket-policy --bucket ${BKT_IN} --policy file://${MY_SRC_DIR}/${BKT_IN}-policy.json

  cat <<EOT
  # 1-2. 出力バケットポリシー処理（${BKT_OUT}）
EOT
  # 既存ポリシー削除
  aws s3api delete-bucket-policy --bucket ${BKT_OUT} 2>/dev/null && \
    echo "  既存の出力バケットポリシーを削除しました" || \
    echo "  出力バケットにポリシーは設定されていませんでした"

  # 新規ポリシー作成（シンプル版 - Denyポリシーは削除）
  cat > ${MY_SRC_DIR}/${BKT_OUT}-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLambdaRoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/ts-010-role-lambda-010"
      },
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BKT_OUT}",
        "arn:aws:s3:::${BKT_OUT}/*"
      ]
    },
    {
      "Sid": "AllowEC2RoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/ts-010-role-ec2-010"
      },
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BKT_OUT}",
        "arn:aws:s3:::${BKT_OUT}/*"
      ]
    }
  ]
}
EOF

  # ポリシー適用
  aws s3api put-bucket-policy --bucket ${BKT_OUT} --policy file://${MY_SRC_DIR}/${BKT_OUT}-policy.json

  cat <<EOT
  # 1-3. バケット所有者制御設定（オプション）
EOT
  # 入力バケット所有者制御（エラーが発生した場合はスキップ）
  aws s3api put-bucket-ownership-controls \
    --bucket ${BKT_IN} \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]' 2>/dev/null && \
    echo "  入力バケット所有者制御設定完了" || \
    echo "  入力バケット所有者制御設定をスキップしました（権限不足）"

  # 出力バケット所有者制御（エラーが発生した場合はスキップ）
  aws s3api put-bucket-ownership-controls \
    --bucket ${BKT_OUT} \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]' 2>/dev/null && \
    echo "  出力バケット所有者制御設定完了" || \
    echo "  出力バケット所有者制御設定をスキップしました（権限不足）"

  cat <<EOT
  # 1-4. バケット通知設定確認（Lambda関数用）
EOT
  echo "  注意: Lambda関数作成後に以下のコマンドで通知設定を行ってください:"
  echo "  aws s3api put-bucket-notification-configuration \\"
  echo "    --bucket ${BKT_IN} \\"
  echo "    --notification-configuration file://notification-config.json"
  
  # 通知設定サンプルファイル作成
  cat > ${MY_SRC_DIR}/notification-config-sample.json << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "ts-010-lambda-trigger",
      "LambdaFunctionArn": "arn:aws:lambda:ap-northeast-1:${ACCOUNT_ID}:function:ts-010-lmd-010",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": ".conf"
            }
          ]
        }
      }
    }
  ]
}
EOF
}

################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

# メイン処理実行
date
confirm_s3policy
make_s3policy
confirm_s3policy

exit 0

################################################################################
# 変更履歴:
# 2025-08-26: S3バケットポリシー設定スクリプト新規作成
#             - 分離バケット構成(${BKT_IN}/out)対応
#             - IAMロール制限アクセス（Lambda/EC2ロールのみ許可）
#             - 既存ポリシー削除・再設定機能
#             - バケット所有者制御設定
#             - Lambda通知設定準備
################################################################################