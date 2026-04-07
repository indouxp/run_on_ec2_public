#!/usr/bin/env bash
################################################################################
#
# TC-030.sh
#
# Lambda関数が存在しない状態で実行 → ARN取得失敗で異常終了
# sed で LAMBDA_FUNC_NAME を存在しない関数名に書き換えて実行
#
# 注意: EventBridgeルール作成途中で失敗するため後処理でルールを削除する
#
# Last updated: 2026-03-19 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成（LAMBDA_FUNC_NAME を存在しない名前に書き換え）
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT}
sed -i 's/LAMBDA_FUNC_NAME="ts-010-lmd-020"/LAMBDA_FUNC_NAME="ts-010-lmd-notexist"/' ${TARGET_SCRIPT}
chmod +x ${TARGET_SCRIPT}

cp config.sh.org config.sh

. assume-role.sh

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
# 変更部表示
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理: 既存ルールを削除（クリーンな状態から）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

aws events remove-targets --rule "${RULE_NAME}" --ids "1" 2>/dev/null || true
aws events delete-rule --name "${RULE_NAME}" 2>/dev/null || true
echo "前処理: EventBridgeルール [${RULE_NAME}] を削除（あれば）"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理: 部分作成されたルールを削除
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

aws events remove-targets --rule "${RULE_NAME}" --ids "1" 2>/dev/null || true
aws events delete-rule --name "${RULE_NAME}" 2>/dev/null || true
echo "後処理: EventBridgeルール [${RULE_NAME}] を削除（あれば）"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
