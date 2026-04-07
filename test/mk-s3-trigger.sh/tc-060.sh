#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# S3 トリガー設定検証
# mk-s3-trigger.sh 実行後、以下を確認する
# - S3 バケットに Lambda への通知設定が存在すること
# - Lambda 関数のリソースベースポリシーに S3 からの呼び出し権限があること
#
# 前提: ${BKT_IN} と ts-010-lmd-010 が存在すること
# → Lambda 未作成の場合は前提条件エラーでスキップ
#
# Last updated: 2026-03-19 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

cp config.sh.org config.sh

. assume-role.sh

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
# 変更部表示
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理: 前提条件チェック + トリガー設定をクリア
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# Lambda 存在確認
if ! aws lambda get-function --function-name "${LAMBDA_FUNC}" 2>/dev/null; then
  echo "前提条件エラー: Lambda 関数 [${LAMBDA_FUNC}] が存在しません"
  echo "mk-lambda.sh を先に実行してください"
  echo "このテストをスキップします"
  exit 1
fi

# バケット存在確認
if ! aws s3api head-bucket --bucket "${S3_BKT_IN}" 2>/dev/null; then
  echo "前提条件エラー: バケット [${S3_BKT_IN}] が存在しません"
  exit 1
fi

# 既存トリガーをクリア
aws s3api put-bucket-notification-configuration \
  --bucket "${S3_BKT_IN}" \
  --notification-configuration '{}' 2>/dev/null || true
aws lambda remove-permission \
  --function-name "${LAMBDA_FUNC}" \
  --statement-id "s3-trigger-for-${LAMBDA_FUNC}" 2>/dev/null || true
echo "前処理: 既存トリガー設定をクリアしました"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-s3-trigger.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（S3 トリガー設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# S3 トリガー設定検証"

# S3 バケット通知設定確認
NOTIF=$(aws s3api get-bucket-notification-configuration \
  --bucket "${S3_BKT_IN}" \
  --output json 2>/dev/null || echo '{}')

if echo "${NOTIF}" | grep -q "LambdaFunctionConfigurations"; then
  echo "[OK] S3バケット [${S3_BKT_IN}] に Lambda 通知設定が存在します"
else
  echo "[NG] S3バケット [${S3_BKT_IN}] に Lambda 通知設定が存在しません"
  exit 1
fi

# Lambda リソースベースポリシー確認
POLICY=$(aws lambda get-policy \
  --function-name "${LAMBDA_FUNC}" \
  --query 'Policy' --output text 2>/dev/null || echo "")

if echo "${POLICY}" | grep -q "s3.amazonaws.com"; then
  echo "[OK] Lambda 関数 [${LAMBDA_FUNC}] に S3 からの呼び出し権限が設定されています"
else
  echo "[NG] Lambda 関数 [${LAMBDA_FUNC}] に S3 からの呼び出し権限が設定されていません"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
