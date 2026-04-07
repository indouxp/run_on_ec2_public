#!/bin/bash
################################################################################
# EC2削除用Lambda関数作成スクリプト
#
# - 関数名: ts-010-lmd-020
# - トリガー: EventBridge (EC2停止イベント)
# - 処理: 対象のEC2インスタンスを削除します
# Last updated: 2026-03-26 20:41:34
################################################################################
set -euo pipefail

# スクリプト自身のディレクトリを取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)
# プロジェクトルートを取得
PROJECT_ROOT=$(cd ${SCRIPT_DIR}/../../; pwd)

# 設定ファイルを読み込みます
source "${SCRIPT_DIR}/config.sh"

MY_NAME=${0##*/}
MY_SRC_DIR=./${MY_NAME}.src
LOG_PATH=${MY_NAME}.log

LAMBDA_FUNC_NAME="ts-010-lmd-020"
IAM_ROLE_NAME="ts-010-role-lambda-020"
POLICY_NAME="ts-010-policy-lambda-020"
SRC_FILE="terminator_lambda_function.py"
ZIP_FILE="terminator_lambda_function.zip"

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
# IAMロール作成
################################################################################
make_iam_role() {
    echo "--- 1. IAMロール [$IAM_ROLE_NAME] の作成 ---"

    # 既存ロールの削除
    aws iam detach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole > /dev/null 2>&1 || true
    aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$POLICY_NAME" > /dev/null 2>&1 || true
    aws iam delete-role --role-name "$IAM_ROLE_NAME" > /dev/null 2>&1 || true
    echo "既存のIAMロールをクリーンアップしました。"

    # 信頼ポリシー
    TRUST_POLICY_JSON=$(cat <<EOF
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
)

    # ロール作成
    aws iam create-role --role-name "$IAM_ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY_JSON" \
      --tags "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"
    echo "IAMロール [$IAM_ROLE_NAME] を作成しました。"

    # AWS管理ポリシーをアタッチ (CloudWatch Logs用)
    aws iam attach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    echo "管理ポリシー [AWSLambdaBasicExecutionRole] をアタッチしました。"

    # カスタムポリシー作成 (EC2削除用)
    CUSTOM_POLICY_JSON=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:TerminateInstances"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    aws iam put-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$POLICY_NAME" --policy-document "$CUSTOM_POLICY_JSON"
    echo "カスタムポリシー [$POLICY_NAME] をアタッチしました。"

    # IAMロールの反映待ち
    echo "IAMロールの反映を待っています..."
    sleep 10
}

################################################################################
# Lambda関数デプロイ
################################################################################
_deploy_lambda() {
    echo "--- 2. Lambda関数 [$LAMBDA_FUNC_NAME] のデプロイ ---"

    # ソースコードをzip化
    cd "$SCRIPT_DIR/../lambda"
    zip -r "$ZIP_FILE" "$SRC_FILE"
    cd "$SCRIPT_DIR"
    echo "ソースコードをzip化しました: $ZIP_FILE"

    # IAMロールのARNを取得
    ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query 'Role.Arn' --output text)

    # Lambda関数を作成または更新
    if aws lambda get-function --function-name "$LAMBDA_FUNC_NAME" > /dev/null 2>&1; then
        echo "Lambda関数 [$LAMBDA_FUNC_NAME] は存在するため、更新します。"
        aws lambda update-function-code --function-name "$LAMBDA_FUNC_NAME" --zip-file fileb://$SCRIPT_DIR/../lambda/$ZIP_FILE
        echo "コードの更新完了を待機中..."
        aws lambda wait function-updated --function-name "$LAMBDA_FUNC_NAME"
        aws lambda update-function-configuration --function-name "$LAMBDA_FUNC_NAME" --role "$ROLE_ARN" --handler "${SRC_FILE%.*}.handler"
        echo "設定の更新完了を待機中..."
        aws lambda wait function-updated --function-name "$LAMBDA_FUNC_NAME"
    else
        echo "Lambda関数 [$LAMBDA_FUNC_NAME] は存在しないため、新規作成します。"
        aws lambda create-function \
            --function-name "$LAMBDA_FUNC_NAME" \
            --runtime python3.12 \
            --role "$ROLE_ARN" \
            --handler "${SRC_FILE%.*}.handler" \
            --zip-file fileb://$SCRIPT_DIR/../lambda/$ZIP_FILE \
            --timeout 30 \
            --memory-size 128 \
            --tags "${PRJ_TAG_KEY}=${PRJ_TAG_VALUE}"
    fi

    echo "Lambda関数のデプロイが完了しました。"
}

################################################################################
# メイン処理
################################################################################
echo "実行開始: $(date)"
echo "------------------------------------------------------------"

make_iam_role
_deploy_lambda

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
