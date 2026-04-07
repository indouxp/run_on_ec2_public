#!/bin/bash
################################################################################
# S3バケット作成
#
# 新しいS3バケット構成対応:
# - 入力バケット: ${BKT_IN} (読み取り専用)
# - 出力バケット: ${BKT_OUT} (書き込み専用)
# Last updated: 2026-03-26 20:42:15
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
# 作成されたS3バケットの確認
################################################################################
confirm_s3bucket() {
  cat <<EOT
  # 1. S3バケット一覧確認（${PRJ_PREFIX}-プレフィックス）
EOT
  aws s3api list-buckets --query "Buckets[?starts_with(Name, '${PRJ_PREFIX}-bkt')].{Name:Name,CreationDate:CreationDate}"

  cat <<EOT
  # 2. 入力バケット詳細確認
EOT
  aws s3api head-bucket --bucket "$S3_BKT_IN_NAME" 2>/dev/null && \
    aws s3api get-bucket-location --bucket "$S3_BKT_IN_NAME" && \
    echo "入力バケット設定確認完了" || \
    echo "入力バケット $S3_BKT_IN_NAME は存在しません"

  cat <<EOT
  # 3. 出力バケット詳細確認
EOT
  aws s3api head-bucket --bucket "$S3_BKT_OUT_NAME" 2>/dev/null && \
    aws s3api get-bucket-location --bucket "$S3_BKT_OUT_NAME" && \
    echo "出力バケット設定確認完了" || \
    echo "出力バケット $S3_BKT_OUT_NAME は存在しません"
}

################################################################################
# S3バケット作成処理
################################################################################
make_s3bucket() {
  cat <<EOT
  # 1-1. 入力バケット処理（$S3_BKT_IN_NAME）
EOT
  if aws s3api head-bucket --bucket "$S3_BKT_IN_NAME" 2>/dev/null; then
    echo "  入力バケット $S3_BKT_IN_NAME が既に存在するため削除します"
    aws s3api put-bucket-versioning \
      --bucket "$S3_BKT_IN_NAME" \
      --versioning-configuration Status=Suspended 2>/dev/null || true
    aws s3 rm "s3://$S3_BKT_IN_NAME" --recursive 2>/dev/null || true
    _VDEL=$({ aws s3api list-object-versions --bucket "$S3_BKT_IN_NAME" --output json 2>/dev/null || echo '{}'; } | \
      jq -c '{"Objects": [(.Versions//[])[], (.DeleteMarkers//[])[]] | map({Key:.Key,VersionId:.VersionId})} | select(.Objects | length > 0)' 2>/dev/null || true)
    [[ -n "${_VDEL:-}" ]] && aws s3api delete-objects --bucket "$S3_BKT_IN_NAME" --delete "${_VDEL}" 2>/dev/null || true
    aws s3api delete-bucket --bucket "$S3_BKT_IN_NAME"
    echo "  入力バケット削除完了"
  fi
  aws s3api create-bucket \
    --bucket "$S3_BKT_IN_NAME" \
    --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
  aws s3api put-bucket-tagging --bucket "$S3_BKT_IN_NAME" \
    --tagging "TagSet=[{Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}}]"

  cat <<EOT
  # 1-2. 出力バケット処理（$S3_BKT_OUT_NAME）
EOT
  if aws s3api head-bucket --bucket "$S3_BKT_OUT_NAME" 2>/dev/null; then
    echo "  出力バケット $S3_BKT_OUT_NAME が既に存在するため削除します"
    aws s3api put-bucket-versioning \
      --bucket "$S3_BKT_OUT_NAME" \
      --versioning-configuration Status=Suspended 2>/dev/null || true
    aws s3 rm "s3://$S3_BKT_OUT_NAME" --recursive 2>/dev/null || true
    _VDEL=$({ aws s3api list-object-versions --bucket "$S3_BKT_OUT_NAME" --output json 2>/dev/null || echo '{}'; } | \
      jq -c '{"Objects": [(.Versions//[])[], (.DeleteMarkers//[])[]] | map({Key:.Key,VersionId:.VersionId})} | select(.Objects | length > 0)' 2>/dev/null || true)
    [[ -n "${_VDEL:-}" ]] && aws s3api delete-objects --bucket "$S3_BKT_OUT_NAME" --delete "${_VDEL}" 2>/dev/null || true
    aws s3api delete-bucket --bucket "$S3_BKT_OUT_NAME"
    echo "  出力バケット削除完了"
  fi
  aws s3api create-bucket \
    --bucket "$S3_BKT_OUT_NAME" \
    --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
  aws s3api put-bucket-tagging --bucket "$S3_BKT_OUT_NAME" \
    --tagging "TagSet=[{Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}}]"

  cat <<EOT
  # 1-3. 入力バケットのパブリックアクセス設定（セキュア）
EOT
  aws s3api put-public-access-block \
    --bucket "$S3_BKT_IN_NAME" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  cat <<EOT
  # 1-4. 出力バケットのパブリックアクセス設定（セキュア）
EOT
  aws s3api put-public-access-block \
    --bucket "$S3_BKT_OUT_NAME" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  cat <<EOT
  # 1-5. 入力バケット暗号化設定
EOT
  aws s3api put-bucket-encryption \
    --bucket "$S3_BKT_IN_NAME" \
    --server-side-encryption-configuration '{ "Rules": [ { "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" }, "BucketKeyEnabled": true } ] }'

  cat <<EOT
  # 1-6. 出力バケット暗号化設定
EOT
  aws s3api put-bucket-encryption \
    --bucket "$S3_BKT_OUT_NAME" \
    --server-side-encryption-configuration '{ "Rules": [ { "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" }, "BucketKeyEnabled": true } ] }'

  cat <<EOT
  # 1-7. 入力バケット通知設定（Lambda関数トリガー用）
  # 注意: この設定は Lambda関数作成後に実行してください
EOT
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  cat > ${MY_SRC_DIR}/s3-notification-config.json << EOF
{
  "LambdaFunctionConfigurations": [
    {
      "Id": "$S3_TRIGGER_ID",
      "LambdaFunctionArn": "arn:aws:lambda:$AWS_REGION:${ACCOUNT_ID}:function:$LAMBDA_FUNC_NAME",
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

  echo "  # Lambda関数作成後に以下のコマンドで通知設定を行ってください:"
  echo "  # aws s3api put-bucket-notification-configuration \\"
  echo "  #   --bucket $S3_BKT_IN_NAME \\"
  echo "  #   --notification-configuration file://${MY_SRC_DIR}/s3-notification-config.json"
}

################################################################################
# 後続スクリプトの自動実行処理
#
# S3バケットを削除→再作成すると、以下の設定がすべて失われる。
# - バケットポリシー         （mk-s3bktpolicy.sh が設定）
# - S3 → Lambda トリガー通知 （mk-s3-trigger.sh  が設定）
# - ライフサイクルルール      （mk-s3-lifecicle.sh が設定）
#
# バケットポリシーと S3トリガーはこの関数内で自動再設定する。
# ライフサイクルルールはバケット名・保持日数の引数が必要なため自動実行不可。
# 完了後に手動で mk-s3-lifecicle.sh を実行すること。
################################################################################
setup_dependent_resources() {
  echo "############################################################"
  echo "# 後続設定スクリプトの実行"
  echo "############################################################"

  # このスクリプトと同じディレクトリ（src/shell/ または infra/）
  local script_dir
  script_dir="$(dirname "$0")"

  # 1. バケットポリシーの再設定
  # S3バケット削除→再作成でバケットポリシーが失われるため、必ず再設定する
  echo "--- バケットポリシーの再設定（mk-s3bktpolicy.sh）---"
  local policy_script="${script_dir}/mk-s3bktpolicy.sh"
  if [[ ! -f "$policy_script" ]]; then
    echo "[ERROR] mk-s3bktpolicy.sh が見つかりません: $policy_script"
    exit 1
  fi
  bash "$policy_script"
  echo "バケットポリシーの再設定が完了しました。"
  echo

  # 2. S3トリガーの再設定
  # S3バケット削除→再作成でトリガー通知設定が失われるため再設定する。
  # Lambda 関数が存在しない場合（構築途中）はスキップし、警告を出力する
  echo "--- S3トリガーの再設定（mk-s3-trigger.sh）---"
  local trigger_script="${script_dir}/mk-s3-trigger.sh"
  if [[ ! -f "$trigger_script" ]]; then
    echo "[ERROR] mk-s3-trigger.sh が見つかりません: $trigger_script"
    exit 1
  fi
  if aws lambda get-function --function-name "$LAMBDA_FUNC_NAME" >/dev/null 2>&1; then
    bash "$trigger_script"
    echo "S3トリガーの再設定が完了しました。"
  else
    echo "[SKIP] Lambda関数 [$LAMBDA_FUNC_NAME] が存在しないため S3トリガーの設定をスキップします。"
    echo "       Lambda デプロイ後に mk-s3-trigger.sh を実行してください。"
  fi
  echo

  # 3. ライフサイクルルールは引数（バケット名・保持日数）が必要なため自動実行不可
  # 以下のコマンドを手動で実行すること
  echo "[WARN] ライフサイクルルールは自動再設定できません。"
  echo "       以下のコマンドを手動で実行してください:"
  echo "         mk-s3-lifecicle.sh $S3_BKT_IN_NAME  <日数>"
  echo "         mk-s3-lifecicle.sh $S3_BKT_OUT_NAME <日数>"
  echo
}

################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

# メイン処理実行
date
confirm_s3bucket
make_s3bucket
# S3バケット再作成後に依存設定（バケットポリシー・S3トリガー）を自動再設定する
setup_dependent_resources
confirm_s3bucket

exit 0

################################################################################
# 変更履歴:
# 2025-08-26: S3バケット作成スクリプト新規作成
#             - 分離バケット構成(${BKT_IN}/out)対応
#             - 既存バケット削除・再作成機能（バージョニング対応）
#             - セキュリティ設定（パブリックアクセスブロック、暗号化）
#             - Lambda通知設定準備
################################################################################
