#!/bin/bash
################################################################################
# CloudTrail証跡作成スクリプト
#
# - S3データイベントを記録する証跡を作成します
# - ログは専用のS3バケットに保存します
################################################################################
set -euo pipefail

# スクリプト自身のディレクトリを取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)
# プロジェクトルートを取得
PROJECT_ROOT=$(cd ${SCRIPT_DIR}/../../; pwd)

# 設定ファイルを読み込みます
source "${SCRIPT_DIR}/config.sh"

MY_NAME=${0##*/}
LOG_PATH=${MY_NAME}.log

# --- 設定 ---
TRAIL_NAME="${PRJ_PREFIX}-trail-010"
TRAIL_LOG_BKT_NAME="${PRJ_PREFIX}-bkt-cloudtrail-logs"

# ログファイルへのリダイレクト
exec >> "${LOG_PATH}" 2>&1

################################################################################
# 確認
################################################################################
confirm_trail() {
  echo "############################################################"
  echo "# CloudTrail [$TRAIL_NAME] の設定確認"
  echo "############################################################"
  
  echo "--- 1. 証跡の確認 ---"
  aws cloudtrail get-trail --name "$TRAIL_NAME" 2>/dev/null || \
    echo "証跡 [$TRAIL_NAME] は存在しません。"
  
  echo "--- 2. イベントセレクターの確認 ---"
  aws cloudtrail get-event-selectors --trail-name "$TRAIL_NAME" 2>/dev/null || \
    echo "イベントセレクターは設定されていません。"

  echo "--- 3. ログ用S3バケットの確認 ---"
  aws s3api head-bucket --bucket "$TRAIL_LOG_BKT_NAME" 2>/dev/null && \
    echo "ログ用S3バケット [$TRAIL_LOG_BKT_NAME] は存在します。" || \
    echo "ログ用S3バケット [$TRAIL_LOG_BKT_NAME] は存在しません。"
  echo
}

################################################################################
# 作成処理
################################################################################
make_trail() {
  echo "############################################################"
  echo "# CloudTrail [$TRAIL_NAME] の作成処理"
  echo "############################################################"

  # 1. 既存の証跡を削除
  if aws cloudtrail get-trail --name "$TRAIL_NAME" > /dev/null 2>&1; then
    echo "既存の証跡 [$TRAIL_NAME] を削除します。"
    aws cloudtrail delete-trail --name "$TRAIL_NAME"
    echo "証跡の削除が完了しました。"
  fi

  # 2. ログ用S3バケットの作成
  if ! aws s3api head-bucket --bucket "$TRAIL_LOG_BKT_NAME" > /dev/null 2>&1; then
    echo "ログ用S3バケット [$TRAIL_LOG_BKT_NAME] を作成します。"
    aws s3api create-bucket \
      --bucket "$TRAIL_LOG_BKT_NAME" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
    aws s3api put-bucket-tagging --bucket "$TRAIL_LOG_BKT_NAME" \
      --tagging "TagSet=[{Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}}]"

    # バケットポリシーの設定
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    POLICY_JSON=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailAclCheck",
            "Effect": "Allow",
            "Principal": {"Service": "cloudtrail.amazonaws.com"},
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::$TRAIL_LOG_BKT_NAME"
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": {"Service": "cloudtrail.amazonaws.com"},
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$TRAIL_LOG_BKT_NAME/AWSLogs/$ACCOUNT_ID/*",
            "Condition": {"StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}}
        }
    ]
}
EOF
)
    aws s3api put-bucket-policy --bucket "$TRAIL_LOG_BKT_NAME" --policy "$POLICY_JSON"
    echo "ログ用S3バケットのポリシーを設定しました。"
  else
    echo "ログ用S3バケット [$TRAIL_LOG_BKT_NAME] は既に存在します。"
  fi

  # 3. 証跡の作成
  echo "証跡 [$TRAIL_NAME] を作成しています..."
  aws cloudtrail create-trail \
    --name "$TRAIL_NAME" \
    --s3-bucket-name "$TRAIL_LOG_BKT_NAME" \
    --is-multi-region-trail \
    --include-global-service-events

  # 4. データイベントを記録するイベントセレクターを設定
  echo "データイベントを記録するようにイベントセレクターを設定します..."
  EVENT_SELECTOR_JSON='[{
    "ReadWriteType": "All",
    "IncludeManagementEvents": true,
    "DataResources": [{
      "Type": "AWS::S3::Object",
      "Values": ["arn:aws:s3:::" ]
    }]
  }]'
  aws cloudtrail put-event-selectors \
    --trail-name "$TRAIL_NAME" \
    --event-selectors "$EVENT_SELECTOR_JSON"

  # 5. 証跡にプロジェクトタグを付与
  TRAIL_ARN=$(aws cloudtrail get-trail --name "$TRAIL_NAME" --query 'Trail.TrailARN' --output text)
  aws cloudtrail add-tags --resource-id "$TRAIL_ARN" \
    --tags-list "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"
  echo "証跡 [$TRAIL_NAME] にプロジェクトタグを付けました。"

  # 6. 証跡のロギングを開始
  echo "証跡 [$TRAIL_NAME] のロギングを開始します..."
  aws cloudtrail start-logging --name "$TRAIL_NAME"

  echo "CloudTrail証跡の作成と設定が完了しました。"
  echo
}

################################################################################
# メイン処理
################################################################################
echo "実行開始: $(date)"
echo "------------------------------------------------------------"

confirm_trail
make_trail
confirm_trail

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
