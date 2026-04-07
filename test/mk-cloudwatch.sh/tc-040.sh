#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# ロググループが存在する状態から実行、正常処理（削除して再作成）
#
# 前提: ${BKT_IN} / ${BKT_OUT} が存在すること（mk-s3bkt.sh 実行済み）
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
# テスト前処理: ロググループが存在することを確認（なければ作成）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

for LG in "${CW_LOG_GROUP_LAMBDA}" "${CW_LOG_GROUP_EC2}" "${CW_LOG_GROUP_SYSTEM}"; do
  if aws logs describe-log-groups --log-group-name-prefix "${LG}" \
      --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LG}"; then
    echo "前処理: ロググループ [${LG}] は既に存在します"
  else
    aws logs create-log-group --log-group-name "${LG}"
    echo "前処理: ロググループ [${LG}] を作成しました"
  fi
done

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
