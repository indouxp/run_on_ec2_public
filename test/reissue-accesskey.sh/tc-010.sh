#!/usr/bin/env bash
################################################################################
#
# TC-010.sh
#
# ユーザーが存在しない場合の異常終了
# --user-name を架空名（ts-notexist-user）に書き換えて
# create-access-key が NoSuchEntity で失敗することを確認
#
# Last updated: 2026-03-30 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成（ユーザー名を架空名に書き換え）
sed 's/--user-name ts-010-user/--user-name ts-notexist-user/' \
  ${TARGET_SCRIPT}.org > ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC=$?

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
