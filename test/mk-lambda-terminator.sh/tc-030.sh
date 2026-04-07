#!/usr/bin/env bash
################################################################################
#
# TC-030.sh
#
# Lambdaソースファイルが存在しない場合の異常終了
# SRC_FILE を存在しないファイル名に書き換えて実行
# → zip コマンドが失敗して異常終了することを確認
#
# Last updated: 2026-03-19 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成（SRC_FILE を存在しないファイル名に書き換え）
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT}
sed -i 's/SRC_FILE="terminator_lambda_function.py"/SRC_FILE="terminator_lambda_function_notexist.py"/' ${TARGET_SCRIPT}
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
# テスト前処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

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

cat ${TARGET_SCRIPT}.log || true

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
