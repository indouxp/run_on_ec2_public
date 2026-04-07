#!/usr/bin/env bash
################################################################################
#
# TC-030.sh
#
# 親VPCが存在しない場合の異常終了
# mk-igw.sh は MY_SRC_DIR を持たないため、tc-030 では
# create_and_attach_igw() 内の VPC 検索失敗を検証する
#
# config.sh の VPC_NAME を存在しない名前に書き換えて実行する
#
# 前提: assume-role.sh により ts-010-role-build の権限で実行する
#
# Last updated: 2026-03-15 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成（変更なし）
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

# config.sh の VPC_NAME を存在しない名前に書き換える
sed 's/vpc-010/vpc-notexist/' config.sh.org > config.sh

. assume-role.sh

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
# 変更部表示
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"
diff_target "config.sh.org" "config.sh"

################################################################################
# テスト前処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

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

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
