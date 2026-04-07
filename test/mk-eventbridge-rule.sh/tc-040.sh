#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# EventBridgeルールが存在する状態から実行、正常処理（削除して再作成）
#
# 前提: ts-010-lmd-020 が存在すること（mk-lambda-terminator.sh 実行済み）
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
# テスト前処理: Lambda存在確認 + ルールが存在することを確認（なければ作成）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# 前提条件チェック: Lambda存在確認
if ! aws lambda get-function --function-name "${EB_LAMBDA_FUNC_NAME}" >/dev/null 2>&1; then
  echo "前提条件エラー: Lambda関数 [${EB_LAMBDA_FUNC_NAME}] が存在しません"
  echo "先に mk-lambda-terminator.sh を実行してください"
  exit 1
fi
echo "前提条件OK: Lambda関数 [${EB_LAMBDA_FUNC_NAME}] が存在します"

# ルールが存在することを確認（なければダミールールを作成）
if aws events describe-rule --name "${RULE_NAME}" >/dev/null 2>&1; then
  echo "前処理: EventBridgeルール [${RULE_NAME}] は既に存在します"
else
  aws events put-rule \
    --name "${RULE_NAME}" \
    --event-pattern '{"source":["aws.ec2"],"detail-type":["EC2 Instance State-change Notification"],"detail":{"state":["stopped"]}}' \
    --state ENABLED \
    --description "Dummy rule for test"
  echo "前処理: ダミーEventBridgeルール [${RULE_NAME}] を作成しました"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
