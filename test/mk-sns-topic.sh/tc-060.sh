#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# SNSトピック設定の検証
# トピックARNが正しい形式であることを確認
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
# テスト前処理: SNSトピックを削除（クリーンな状態から）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

TOPIC_ARN=$(aws sns list-topics --query 'Topics[].TopicArn' --output text 2>/dev/null | tr '\t' '\n' | grep "${SNS_TOPIC_NAME}" || true)
if [[ -n "${TOPIC_ARN}" ]]; then
  aws sns delete-topic --topic-arn "${TOPIC_ARN}"
  echo "前処理: SNSトピック [${SNS_TOPIC_NAME}] を削除しました"
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
# テスト後処理: SNSトピック設定検証
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# SNSトピック設定検証"

TOPIC_ARN=$(aws sns list-topics --query 'Topics[].TopicArn' --output text 2>/dev/null | tr '\t' '\n' | grep "${SNS_TOPIC_NAME}" || true)
if [[ -n "${TOPIC_ARN}" ]]; then
  echo "[OK] SNSトピック [${SNS_TOPIC_NAME}] が存在します: ${TOPIC_ARN}"
else
  echo "[NG] SNSトピック [${SNS_TOPIC_NAME}] が存在しません"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
