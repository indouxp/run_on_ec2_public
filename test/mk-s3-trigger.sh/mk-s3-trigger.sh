#!/bin/bash
################################################################################
# S3トリガー設定スクリプト
#
# - 対象S3バケット: ${BKT_IN}
# - 対象Lambda関数: ts-010-lmd-010
# - トリガー条件: .confファイルの作成
################################################################################
set -euo pipefail
MY_NAME=${0##*/}
MY_SRC_DIR=./${MY_NAME}.src
LOG_PATH=${MY_NAME}.log

exec >> "${LOG_PATH}" 2>&1

# config.shから変数を読み込む
source "$(dirname "$0")/config.sh"

# --- 設定 ---
BUCKET_NAME="$S3_BKT_IN_NAME"
FUNC_NAME="$LAMBDA_FUNC_NAME"
STATEMENT_ID="s3-trigger-for-$FUNC_NAME"
NOTIFICATION_ID="lambda-trigger-for-conf-files"

################################################################################
# 確認
################################################################################
confirm_trigger() {
  echo "############################################################"
  echo "# S3トリガー設定の確認"
  echo "############################################################"
  
  echo "--- 1. Lambda関数のリソースベースポリシー確認 ---"
  aws lambda get-policy --function-name "$FUNC_NAME" 2>/dev/null || \
    echo "Lambda関数 [$FUNC_NAME] にリソースベースポリシーは設定されていません。"
  
  echo "--- 2. S3バケットの通知設定確認 ---"
  aws s3api get-bucket-notification-configuration --bucket "$BUCKET_NAME" 2>/dev/null || \
    echo "S3バケット [$BUCKET_NAME] に通知設定はありません。"
  echo
}

################################################################################
# 設定処理
################################################################################
set_trigger() {
  echo "############################################################"
  echo "# S3トリガーの設定処理"
  echo "############################################################"

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  LAMBDA_ARN=$(aws lambda get-function --function-name "$FUNC_NAME" --query 'Configuration.FunctionArn' --output text)
  BUCKET_ARN="arn:aws:s3:::$BUCKET_NAME"

  # 1. LambdaにS3からの呼び出し権限を付与
  echo "--- 1. Lambda関数にS3からの呼び出し権限を付与します ---"
  # 既存の権限を削除しようと試みる（なければエラーになるが無視）
  aws lambda remove-permission --function-name "$FUNC_NAME" --statement-id "$STATEMENT_ID" 2>/dev/null || \
    echo "既存の権限 [$STATEMENT_ID] は存在しませんでした。"
  
  aws lambda add-permission --function-name "$FUNC_NAME" \
    --statement-id "$STATEMENT_ID" \
    --action "lambda:InvokeFunction" \
    --principal s3.amazonaws.com \
    --source-arn "$BUCKET_ARN" \
    --source-account "$ACCOUNT_ID"
  echo "権限の付与が完了しました。"

  # 2. S3バケットに通知設定を作成
  echo "--- 2. S3バケットに通知設定を作成します ---"
  NOTIFICATION_CONFIG='{
    "LambdaFunctionConfigurations": [
      {
        "Id": "'$NOTIFICATION_ID'",
        "LambdaFunctionArn": "'$LAMBDA_ARN'",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
          "Key": {
            "FilterRules": [
              {
                "Name": "Suffix",
                "Value": ".conf"
              }
            ]
          }
        }
      }
    ]
  }'
  
  aws s3api put-bucket-notification-configuration \
    --bucket "$BUCKET_NAME" \
    --notification-configuration "$NOTIFICATION_CONFIG"
  echo "S3バケットの通知設定が完了しました。"
  echo
}

################################################################################
# メイン処理
################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }

echo "実行開始: $(date)"
echo "------------------------------------------------------------"

confirm_trigger
set_trigger
confirm_trigger

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0