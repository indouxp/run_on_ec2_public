#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# ts-010-user にキーが存在しない状態からの正常実行
# 前処理で全キーを削除し、スクリプトが新規発行・credentials 更新を
# 正常に完了することを確認
#
# Last updated: 2026-03-30 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理：全キーを削除する
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

for KEY_ID in $(AWS_PROFILE=ts-usr-admin aws iam list-access-keys \
    --user-name ts-010-user \
    --query 'AccessKeyMetadata[*].AccessKeyId' --output text); do
  echo "前処理: キーを削除します: ${KEY_ID}"
  AWS_PROFILE=ts-usr-admin aws iam delete-access-key \
    --user-name ts-010-user --access-key-id "${KEY_ID}"
done
echo "前処理: キーが0個の状態になりました"

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
