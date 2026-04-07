#!/bin/bash
################################################################################
# EventBridgeルール作成スクリプト
#
# - ルール: EC2インスタンスが停止したらLambdaをトリガーします
# - ターゲット: ts-010-lmd-020 (EC2削除用Lambda)
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

RULE_NAME="ts-010-rule-stop-ec2-trigger"
LAMBDA_FUNC_NAME="ts-010-lmd-020"

# ログファイルへのリダイレクト
exec >> "${LOG_PATH}" 2>&1

################################################################################
# EventBridgeルール作成
################################################################################
make_rule() {
    # 既存ルールを削除して再作成
    if aws events describe-rule --name "$RULE_NAME" >/dev/null 2>&1; then
        echo "--- 0. EventBridgeルール [$RULE_NAME] の削除 ---"
        aws events remove-targets --rule "$RULE_NAME" --ids "1" || true
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNC_NAME" \
            --statement-id "EventBridgeInvoke-${RULE_NAME}" 2>/dev/null || true
        aws events delete-rule --name "$RULE_NAME"
        echo "EventBridgeルール [$RULE_NAME] を削除しました。"
    fi

    echo "--- 1. EventBridgeルール [$RULE_NAME] の作成 ---"

    # イベントパターン
    EVENT_PATTERN=$(cat <<EOF
{
    "source": ["aws.ec2"],
    "detail-type": ["EC2 Instance State-change Notification"],
    "detail": {
        "state": ["stopped"]
    }
}
EOF
)

    # ルールを作成（または更新）
    aws events put-rule \
        --name "$RULE_NAME" \
        --event-pattern "$EVENT_PATTERN" \
        --state ENABLED \
        --description "Triggers a Lambda function to terminate EC2 instances when they are stopped."
    echo "EventBridgeルール [$RULE_NAME] を作成・更新しました。"

    # Lambda関数のARNを取得
    LAMBDA_ARN=$(aws lambda get-function --function-name "$LAMBDA_FUNC_NAME" --query 'Configuration.FunctionArn' --output text)
    if [ -z "$LAMBDA_ARN" ]; then
        echo "エラー: Lambda関数 [$LAMBDA_FUNC_NAME] が見つかりません。先にデプロイしてください。"
        exit 1
    fi

    # LambdaにEventBridgeからの呼び出し許可を追加
    echo "--- 2. Lambda関数にアクセス許可を追加 ---"
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNC_NAME" \
        --statement-id "EventBridgeInvoke-${RULE_NAME}" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "$(aws events describe-rule --name "$RULE_NAME" --query 'Arn' --output text)" > /dev/null 2>&1 || echo "アクセス許可は既に存在します。"
    echo "Lambda関数へのアクセス許可を設定しました。"

    # ルールにターゲット（Lambda関数）を設定
    echo "--- 3. ルールにターゲットを設定 ---"
    aws events put-targets \
        --rule "$RULE_NAME" \
        --targets "Id"="1","Arn"="$LAMBDA_ARN"
    echo "ルール [$RULE_NAME] にターゲット [$LAMBDA_FUNC_NAME] を設定しました。"
}

################################################################################
# メイン処理
################################################################################
echo "実行開始: $(date)"
echo "------------------------------------------------------------"

make_rule

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
