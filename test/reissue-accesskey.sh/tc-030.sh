#!/usr/bin/env bash
################################################################################
#
# TC-030.sh
#
# SecretAccessKey に ':' が含まれる場合の異常終了
# aws iam create-access-key | awk パイプを echo に差し替えて
# ':' を含む出力を TMP_PATH に書き込み、エラー検知で exit 1 することを確認
#
# Last updated: 2026-03-30 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
# aws iam create-access-key の行を削除し、awk 行を ':' を含む echo に置換
sed \
  -e '/aws iam create-access-key/d' \
  -e 's|awk.*TMP_PATH.*|echo "AKIAXXXXXXXXXX:SecretWith:Colon" > "${TMP_PATH}"|' \
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
# テスト（':' 含有検知で exit 1 を期待）
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC=$?

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
