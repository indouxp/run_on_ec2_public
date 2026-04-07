#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# Lambda関数が存在する状態から実行、正常処理（更新）
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
# テスト前処理: Lambda関数が存在することを確認（なければ作成）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# Lambda関数が存在することを確認（なければ作成）
if aws lambda get-function --function-name "${TERM_FUNC_NAME}" >/dev/null 2>&1; then
  echo "前処理: Lambda関数 [${TERM_FUNC_NAME}] は既に存在します"
else
  # mk-lambda-terminator.sh は自身でIAMロール作成まで行うため、先に一度実行
  ./${TARGET_SCRIPT}
  echo "前処理: Lambda関数 [${TERM_FUNC_NAME}] を作成しました"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log
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
