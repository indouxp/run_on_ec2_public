#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# ts-010-user にキーが存在する状態からの正常実行
# 前処理でキーを1個の状態に揃え、スクリプトが新規発行・credentials 更新を
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
# テスト前処理：キーを1個の状態に揃える
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# 現在のキーを全て取得
ALL_KEYS=$(AWS_PROFILE=ts-usr-admin aws iam list-access-keys \
  --user-name ts-010-user \
  --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
KEY_COUNT=$(echo "${ALL_KEYS}" | wc -w)
echo "前処理: 現在のキー数=${KEY_COUNT} / IDs=${ALL_KEYS}"

if [[ ${KEY_COUNT} -ge 2 ]]; then
  # 2個以上の場合、最初の1個だけ残して残りを削除
  KEYS_ARRAY=(${ALL_KEYS})
  for KEY_ID in "${KEYS_ARRAY[@]:1}"; do
    echo "前処理: 余分なキーを削除します: ${KEY_ID}"
    AWS_PROFILE=ts-usr-admin aws iam delete-access-key \
      --user-name ts-010-user --access-key-id "${KEY_ID}"
  done
elif [[ ${KEY_COUNT} -eq 0 ]]; then
  # キーがない場合は1個作成する
  echo "前処理: キーが存在しないため1個作成します"
  AWS_PROFILE=ts-usr-admin aws iam create-access-key \
    --user-name ts-010-user > /dev/null
fi
echo "前処理: キーが1個の状態になりました"

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
