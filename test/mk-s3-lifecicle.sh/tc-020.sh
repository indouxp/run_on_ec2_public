#!/usr/bin/env bash
################################################################################
#
# TC-020.sh
#
# LOG_PATH が書き込み不可ディレクトリの場合の異常終了
# mk-s3-lifecicle.sh は引数バリデーションが exec >> LOG の前にあるため
# 引数を指定して実行する
#
# Last updated: 2026-03-19 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

# テスト用スクリプト作成（exec >> を書き込み不可パスに書き換え）
sed 's#exec >> "\${LOG_PATH}" 2>&1#exec >> /notexist/notexist.log 2>&1#' \
${TARGET_SCRIPT}.org > ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

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

rm -f ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（引数が必要: 引数バリデーションが exec >> の前にある）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT} "${TEST_BUCKET}" "${TEST_EXPIRE_DAYS}"
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
