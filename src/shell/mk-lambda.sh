#!/bin/bash
################################################################################
# Lambda関数 作成・更新スクリプト
#
# - 関数名: ts-010-lmd-010
# - コード: ../lambda/lambda_function.py
# - IAMロール: ts-010-role-lambda-010
# Last updated: 2026-03-26 20:41:38
################################################################################
set -euo pipefail

MY_NAME=${0##*/}
LOG_PATH=${MY_NAME}.log

exec >> "${LOG_PATH}" 2>&1

# config.shから変数を読み込む
source "$(dirname "$0")/config.sh"

# --- 設定 ---
FUNC_NAME="$LAMBDA_FUNC_NAME"
ROLE_NAME="$IAM_ROLE_LAMBDA_NAME"
EC2_ROLE_NAME="$IAM_ROLE_EC2_NAME"
HANDLER="lambda_function.main_handler"
RUNTIME="python3.12"
ZIP_FILE="deployment.zip"
SRC_DIR="../lambda"

################################################################################
# 確認
################################################################################
confirm_lambda() {
  echo "############################################################"
  echo "# Lambda関数 [$FUNC_NAME] の設定確認"
  echo "############################################################"
  aws lambda get-function --function-name "$FUNC_NAME" 2>/dev/null || \
    echo "Lambda関数 [$FUNC_NAME] は存在しません。"
  echo
}

################################################################################
# 作成・更新処理
################################################################################
deploy_lambda() {
  echo "############################################################"
  echo "# Lambda関数 [$FUNC_NAME] のデプロイ処理"
  echo "############################################################"

  # 1. IAMインスタンスプロファイルの確認・作成
  echo "--- 1. IAM Instance Profile [$EC2_ROLE_NAME] の確認・作成 ---"
  if ! aws iam get-instance-profile --instance-profile-name "$EC2_ROLE_NAME" >/dev/null 2>&1; then
    echo "インスタンスプロファイル [$EC2_ROLE_NAME] が存在しないため、作成します。"
    aws iam create-instance-profile --instance-profile-name "$EC2_ROLE_NAME"
    aws iam add-role-to-instance-profile --instance-profile-name "$EC2_ROLE_NAME" --role-name "$EC2_ROLE_NAME"
    echo "インスタンスプロファイルの作成とロールの追加が完了しました。反映まで10秒待機します。"
    sleep 10
  else
    echo "インスタンスプロファイル [$EC2_ROLE_NAME] は既に存在します。"
  fi

  # 2. デプロイパッケージ (ZIP) の作成
  echo "--- 2. デプロイパッケージ [$ZIP_FILE] の作成 ---"
  echo "--- lambda_function.py の内容 (ZIP化前) ---"
  cat "$SRC_DIR/lambda_function.py"
  echo "---------------------------------------------------"
  (cd "$SRC_DIR" && zip -r "$OLDPWD/$ZIP_FILE" .)
  echo "ZIPファイルの作成が完了しました。"

  # 3. Lambda関数の作成（既存の場合は削除して再作成）
  echo "--- 3. Lambda関数 [$FUNC_NAME] の作成 ---"
  ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

  if aws lambda get-function --function-name "$FUNC_NAME" >/dev/null 2>&1; then
    echo "関数が既に存在します。削除して再作成します。"
    aws lambda delete-function --function-name "$FUNC_NAME"
    echo "Lambda関数 [$FUNC_NAME] を削除しました。"
  fi

  echo "関数を新規作成します。"
  aws lambda create-function --function-name "$FUNC_NAME" \
    --runtime "$RUNTIME" \
    --role "$ROLE_ARN" \
    --handler "$HANDLER" \
    --zip-file "fileb://$ZIP_FILE" \
    --description "S3 event trigger to run EC2 instance" \
    --timeout 300 \
    --memory-size 256 \
    --tags "${PRJ_TAG_KEY}=${PRJ_TAG_VALUE}"
  echo "関数の新規作成が完了しました。"
  
  echo
}



################################################################################
# S3トリガー再設定処理
#
# Lambda関数を削除→再作成すると、S3バケットからの呼び出し許可
#（リソースベースポリシー）が失われる。
# mk-s3-trigger.sh を続けて実行し、S3トリガーを必ず再設定する。
################################################################################
setup_s3_trigger() {
  echo "############################################################"
  echo "# S3トリガーの再設定"
  echo "############################################################"

  # mk-s3-trigger.sh のパス（このスクリプトと同じディレクトリ）
  local trigger_script
  trigger_script="$(dirname "$0")/mk-s3-trigger.sh"

  if [[ ! -f "$trigger_script" ]]; then
    echo "[ERROR] mk-s3-trigger.sh が見つかりません: $trigger_script"
    exit 1
  fi

  echo "mk-s3-trigger.sh を実行します: $trigger_script"
  bash "$trigger_script"
  echo "S3トリガーの再設定が完了しました。"
  echo
}

################################################################################
# メイン処理
################################################################################
echo "実行開始: $(date)"
echo "------------------------------------------------------------"

confirm_lambda
deploy_lambda
# Lambda 再作成後に S3トリガーを再設定する（リソースベースポリシーが消えるため）
setup_s3_trigger
confirm_lambda

echo "------------------------------------------------------------"

echo "実行終了: $(date)"

exit 0
