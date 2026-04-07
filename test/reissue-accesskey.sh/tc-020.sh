#!/usr/bin/env bash
################################################################################
#
# TC-020.sh
#
# アクセスキーが上限（2個）に達した状態での異常終了
# 前処理でキーを2個に揃えてから実行し、LimitExceeded で失敗することを確認
# 後処理で前処理で追加したキーを削除する
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
# テスト前処理：アクセスキーを2個に揃える
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# 現在のキー一覧を取得
EXISTING_KEYS=$(AWS_PROFILE=ts-usr-admin aws iam list-access-keys \
  --user-name ts-010-user \
  --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
KEY_COUNT=$(echo "${EXISTING_KEYS}" | wc -w)
echo "前処理: 現在のキー数=${KEY_COUNT} / IDs=${EXISTING_KEYS}"

# 2個になるまで追加発行し、追加したキーIDを記録する
ADDED_KEYS=()
while [[ ${KEY_COUNT} -lt 2 ]]; do
  NEW_KEY=$(AWS_PROFILE=ts-usr-admin aws iam create-access-key \
    --user-name ts-010-user \
    --query 'AccessKey.AccessKeyId' --output text)
  ADDED_KEYS+=("${NEW_KEY}")
  KEY_COUNT=$((KEY_COUNT + 1))
  echo "前処理: キーを追加発行しました: ${NEW_KEY}"
done
echo "前処理: キーが2個の状態になりました"

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始

################################################################################
# テスト（3個目の発行を試みて LimitExceeded を期待）
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC=$?

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理：前処理で追加したキーを削除する
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

for KEY_ID in "${ADDED_KEYS[@]:-}"; do
  [[ -z "${KEY_ID}" ]] && continue
  echo "後処理: 追加キーを削除します: ${KEY_ID}"
  AWS_PROFILE=ts-usr-admin aws iam delete-access-key \
    --user-name ts-010-user \
    --access-key-id "${KEY_ID}"
done
echo "後処理: クリーンアップ完了"

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
