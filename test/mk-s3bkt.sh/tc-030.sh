#!/usr/bin/env bash
################################################################################
#
# TC-030.sh
#
# MY_SRC_DIR=./${MY_NAME}.src を作成できない（ファイルを置いておく）
# → mkdir が失敗して異常終了することを確認
#
# Last updated: 2026-03-19 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

cp config.sh.org config.sh

################################################################################
# 開始
echo "${HEADER}"
# 変更部表示
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm config.sh
cp config.sh.org config.sh
ls -l config.sh

rm -rf ./${TARGET_SCRIPT}.src
touch ./${TARGET_SCRIPT}.src
ls -l ./${TARGET_SCRIPT}.src

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

cat ${TARGET_SCRIPT}.log

rm -rf ./${TARGET_SCRIPT}.src

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
