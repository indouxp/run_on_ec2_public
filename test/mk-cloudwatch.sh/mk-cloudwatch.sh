#!/bin/bash
################################################################################
# CloudWatchロググループ作成
#
# 新しい命名規則対応:
# - Lambdaログ: ts-010-log-lambda-010
# - EC2ログ: ts-010-log-ec2-010
# - システムログ: ts-010-log-system-010
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

exec >> "${LOG_PATH}" 2>&1

################################################################################
# 作成されたCloudWatchロググループの確認
################################################################################
confirm_cloudwatch() {
  cat <<EOT
  # 1. CloudWatchロググループ一覧確認（${PRJ_PREFIX}-プレフィックス）
EOT
  aws logs describe-log-groups --log-group-name-prefix "${PRJ_PREFIX}-log" --query 'logGroups[].{LogGroupName:logGroupName,CreationTime:creationTime,RetentionInDays:retentionInDays}' 2>/dev/null || \
    echo "${PRJ_PREFIX}-プレフィックスのロググループは存在しません"

  cat <<EOT
  # 2. Lambdaロググループ詳細確認
EOT
  aws logs describe-log-groups --log-group-name-prefix "$CW_LOG_GROUP_LAMBDA_NAME" --query 'logGroups[0].{LogGroupName:logGroupName,CreationTime:creationTime,RetentionInDays:retentionInDays,SizeInBytes:storedBytes}' 2>/dev/null || \
    echo "Lambdaロググループ $CW_LOG_GROUP_LAMBDA_NAME は存在しません"

  cat <<EOT
  # 3. EC2ロググループ詳細確認
EOT
  aws logs describe-log-groups --log-group-name-prefix "$CW_LOG_GROUP_EC2_NAME" --query 'logGroups[0].{LogGroupName:logGroupName,CreationTime:creationTime,RetentionInDays:retentionInDays,SizeInBytes:storedBytes}' 2>/dev/null || \
    echo "EC2ロググループ $CW_LOG_GROUP_EC2_NAME は存在しません"

  cat <<EOT
  # 4. システムロググループ詳細確認
EOT
  aws logs describe-log-groups --log-group-name-prefix "$CW_LOG_GROUP_SYSTEM_NAME" --query 'logGroups[0].{LogGroupName:logGroupName,CreationTime:creationTime,RetentionInDays:retentionInDays,SizeInBytes:storedBytes}' 2>/dev/null || \
    echo "システムロググループ $CW_LOG_GROUP_SYSTEM_NAME は存在しません"
}

################################################################################
# CloudWatchロググループ作成処理
################################################################################
make_cloudwatch() {
  cat <<EOT
  # 1-1. Lambdaロググループ処理（$CW_LOG_GROUP_LAMBDA_NAME）
EOT
  if aws logs describe-log-groups --log-group-name-prefix "$CW_LOG_GROUP_LAMBDA_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$CW_LOG_GROUP_LAMBDA_NAME"; then
    echo "  Lambdaロググループ $CW_LOG_GROUP_LAMBDA_NAME が既に存在するため削除します"
    LOG_STREAMS=$(aws logs describe-log-streams --log-group-name "$CW_LOG_GROUP_LAMBDA_NAME" --query 'logStreams[].logStreamName' --output text 2>/dev/null || echo "")
    if [ -n "$LOG_STREAMS" ]; then
      for stream in $LOG_STREAMS; do
        aws logs delete-log-stream --log-group-name "$CW_LOG_GROUP_LAMBDA_NAME" --log-stream-name "$stream" 2>/dev/null || true
      done
    fi
    aws logs delete-log-group --log-group-name "$CW_LOG_GROUP_LAMBDA_NAME"
    echo "  Lambdaロググループ削除完了"
  fi
  aws logs create-log-group --log-group-name "$CW_LOG_GROUP_LAMBDA_NAME"
  aws logs put-retention-policy --log-group-name "$CW_LOG_GROUP_LAMBDA_NAME" --retention-in-days 30

  cat <<EOT
  # 1-2. EC2ロググループ処理（$CW_LOG_GROUP_EC2_NAME）
EOT
  if aws logs describe-log-groups --log-group-name-prefix "$CW_LOG_GROUP_EC2_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$CW_LOG_GROUP_EC2_NAME"; then
    echo "  EC2ロググループ $CW_LOG_GROUP_EC2_NAME が既に存在するため削除します"
    LOG_STREAMS=$(aws logs describe-log-streams --log-group-name "$CW_LOG_GROUP_EC2_NAME" --query 'logStreams[].logStreamName' --output text 2>/dev/null || echo "")
    if [ -n "$LOG_STREAMS" ]; then
      for stream in $LOG_STREAMS; do
        aws logs delete-log-stream --log-group-name "$CW_LOG_GROUP_EC2_NAME" --log-stream-name "$stream" 2>/dev/null || true
      done
    fi
    aws logs delete-log-group --log-group-name "$CW_LOG_GROUP_EC2_NAME"
    echo "  EC2ロググループ削除完了"
  fi
  aws logs create-log-group --log-group-name "$CW_LOG_GROUP_EC2_NAME"
  aws logs put-retention-policy --log-group-name "$CW_LOG_GROUP_EC2_NAME" --retention-in-days 30

  cat <<EOT
  # 1-3. システムロググループ処理（$CW_LOG_GROUP_SYSTEM_NAME）
EOT
  if aws logs describe-log-groups --log-group-name-prefix "$CW_LOG_GROUP_SYSTEM_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$CW_LOG_GROUP_SYSTEM_NAME"; then
    echo "  システムロググループ $CW_LOG_GROUP_SYSTEM_NAME が既に存在するため削除します"
    LOG_STREAMS=$(aws logs describe-log-streams --log-group-name "$CW_LOG_GROUP_SYSTEM_NAME" --query 'logStreams[].logStreamName' --output text 2>/dev/null || echo "")
    if [ -n "$LOG_STREAMS" ]; then
      for stream in $LOG_STREAMS; do
        aws logs delete-log-stream --log-group-name "$CW_LOG_GROUP_SYSTEM_NAME" --log-stream-name "$stream" 2>/dev/null || true
      done
    fi
    aws logs delete-log-group --log-group-name "$CW_LOG_GROUP_SYSTEM_NAME"
    echo "  システムロググループ削除完了"
  fi
  aws logs create-log-group --log-group-name "$CW_LOG_GROUP_SYSTEM_NAME"
  aws logs put-retention-policy --log-group-name "$CW_LOG_GROUP_SYSTEM_NAME" --retention-in-days 30

  cat <<EOT
  # 1-4. ロググループタグ設定
EOT
  aws logs tag-log-group --log-group-name "$CW_LOG_GROUP_LAMBDA_NAME" --tags Project=${PRJ_PREFIX}-system,Component=lambda
  aws logs tag-log-group --log-group-name "$CW_LOG_GROUP_EC2_NAME" --tags Project=${PRJ_PREFIX}-system,Component=ec2
  aws logs tag-log-group --log-group-name "$CW_LOG_GROUP_SYSTEM_NAME" --tags Project=${PRJ_PREFIX}-system,Component=system

  cat <<EOT
  # 1-5. メトリックフィルター作成（エラー監視用）
EOT
  # Lambdaエラーメトリックフィルター
  aws logs put-metric-filter \
    --log-group-name "$CW_LOG_GROUP_LAMBDA_NAME" \
    --filter-name "${PRJ_PREFIX}-lambda-error-filter" \
    --filter-pattern "ERROR" \
    --metric-transformations \
      metricName=${PRJ_PREFIX}-lambda-errors,metricNamespace=${PRJ_PREFIX}/Lambda,metricValue=1

  # EC2エラーメトリックフィルター
  aws logs put-metric-filter \
    --log-group-name "$CW_LOG_GROUP_EC2_NAME" \
    --filter-name "${PRJ_PREFIX}-ec2-error-filter" \
    --filter-pattern "ERROR" \
    --metric-transformations \
      metricName=${PRJ_PREFIX}-ec2-errors,metricNamespace=${PRJ_PREFIX}/EC2,metricValue=1

  # システムエラーメトリックフィルター
  aws logs put-metric-filter \
    --log-group-name "$CW_LOG_GROUP_SYSTEM_NAME" \
    --filter-name "${PRJ_PREFIX}-system-error-filter" \
    --filter-pattern "ERROR" \
    --metric-transformations \
      metricName=${PRJ_PREFIX}-system-errors,metricNamespace=${PRJ_PREFIX}/System,metricValue=1
}

################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

# メイン処理実行
date
confirm_cloudwatch
make_cloudwatch
confirm_cloudwatch

exit 0

################################################################################
# 変更履歴:
# 2025-08-26: CloudWatchログ設定スクリプト新規作成
#             - ロググループ構成(ts-010-log-lambda/ec2/system-010)対応
#             - 既存ロググループ削除・再作成機能
#             - 保持期間設定（30日）
#             - エラー監視用メトリックフィルター設定
#             - タグ設定によるリソース管理
################################################################################
