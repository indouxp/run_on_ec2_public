#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# SNSトピックが存在しない状態から実行、正常処理（新規作成）
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
# テスト前処理: SNSトピックを削除
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

TOPIC_ARN=$(aws sns list-topics --query 'Topics[].TopicArn' --output text 2>/dev/null | tr '\t' '\n' | grep "${SNS_TOPIC_NAME}" || true)
if [[ -n "${TOPIC_ARN}" ]]; then
  aws sns delete-topic --topic-arn "${TOPIC_ARN}"
  echo "前処理: SNSトピック [${SNS_TOPIC_NAME}] を削除しました"
else
  echo "前処理: SNSトピック [${SNS_TOPIC_NAME}] は存在しません（削除不要）"
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
