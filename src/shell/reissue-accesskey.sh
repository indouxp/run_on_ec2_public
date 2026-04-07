#!/bin/bash
################################################################################
# スクリプト名 : reissue-accesskey.sh
# 概要         : ts-010-user のアクセスキーを再発行し、デフォルトプロファイルの
#                認証情報（aws_access_key_id / aws_secret_access_key）を更新する
# Created      : 2026-03-26
# Last updated : 2026-03-30 01:00:00
# Author       : Tsystem
# 更新履歴     :
#    2026-03-26: 初版作成
#    2026-03-30: ヘッダコメント追加・cut バグ修正・SecretAccessKey ':' 含有チェック追加
#               AssumeRole 環境変数クリア処理追加（get-caller-identity 前）
#    2026-03-30: IAM キー伝播待ち sleep 10 追加
################################################################################
set -euo pipefail

SCRIPT_NAME="${0##*/}"
TMP_NAME=${SCRIPT_NAME}.tmp
TMP_PATH=/tmp/${TMP_NAME}

term() {
  rm -f /tmp/${0##*/}.tmp
}
trap 'term' 0

# 既存アクセスキーをすべて削除（上限2本のため、作成前に削除が必要）
existing_keys=$(AWS_PROFILE=ts-usr-admin aws iam list-access-keys --user-name ts-010-user \
  --query 'AccessKeyMetadata[].AccessKeyId' --output text)
for key_id in ${existing_keys}; do
  echo "既存アクセスキーを削除します: ${key_id}"
  AWS_PROFILE=ts-usr-admin aws iam delete-access-key --user-name ts-010-user --access-key-id "${key_id}"
done

AWS_PROFILE=ts-usr-admin aws iam create-access-key --user-name ts-010-user |
awk '{printf("%s:%s\n", $2, $4);}' > "${TMP_PATH}"

# SecretAccessKey に ':' が含まれる場合、cut による分割が不正になるためエラー終了
if grep -q ':.*:' "${TMP_PATH}"; then
  echo "[ERROR] SecretAccessKey に ':' が含まれています。発行済みキーを削除し再実行してください。" >&2
  exit 1
fi

AccessKeyId=$(cut -d: -f1 "${TMP_PATH}")
SecretAccessKey=$(cut -d: -f2 "${TMP_PATH}")

aws configure set aws_access_key_id "${AccessKeyId}" --profile ts-010-user

aws configure set aws_secret_access_key "${SecretAccessKey}" --profile ts-010-user

# AssumeRole 環境変数をクリアして credentials ファイルの設定を有効にする
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# IAM アクセスキーの AWS 内伝播を待つ（新規キーは即時有効にならない場合がある）
sleep 10

aws sts get-caller-identity

