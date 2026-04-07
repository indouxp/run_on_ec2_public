#!/bin/bash
################################################################################
# スクリプト名 : get-ts-010-user-key.sh
# 概要         : ts-010-user のアクセスキーを発行し ~/.aws/credentials [default] を更新する
#                tc-070.sh 実行前の前処理として使用する
# Created      : 2026-03-19
# Last updated : 2026-03-19
# Author       : Tsystem
# 更新履歴     :
#    2026-03-19: 初版
################################################################################
set -euo pipefail

# --- 設定値 ---
readonly PROFILE="ts-usr-admin"         # アクセスキー発行に使用する管理者プロファイル
readonly TARGET_USER="ts-010-user"      # アクセスキーを発行する対象IAMユーザー

################################################################################
# 関数名   : delete_existing_keys
# 概要     : 対象ユーザーの既存アクセスキーをすべて削除する（上限2件対策）
# 引数     : なし
# 戻り値   : なし
################################################################################
delete_existing_keys() {
  echo "--- 既存アクセスキーの確認・削除 ---"

  local key_ids
  key_ids=$(aws --profile "${PROFILE}" iam list-access-keys \
    --user-name "${TARGET_USER}" \
    --query 'AccessKeyMetadata[].AccessKeyId' \
    --output text)

  if [[ -z "${key_ids}" ]]; then
    echo "既存のアクセスキーはありません。"
    return
  fi

  for key_id in ${key_ids}; do
    echo "削除: ${key_id}"
    aws --profile "${PROFILE}" iam delete-access-key \
      --user-name "${TARGET_USER}" \
      --access-key-id "${key_id}"
  done
  echo "既存のアクセスキーを削除しました。"
}

################################################################################
# 関数名   : create_key
# 概要     : 対象ユーザーの新規アクセスキーを発行し ~/.aws/credentials [default] を更新する
# 引数     : なし
# 戻り値   : なし
################################################################################
create_key() {
  echo "--- アクセスキー発行 ---"

  # アクセスキーを発行
  local key_json
  key_json=$(aws --profile "${PROFILE}" iam create-access-key \
    --user-name "${TARGET_USER}" \
    --output json)

  local key_id secret_key
  key_id=$(echo "${key_json}"    | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
  secret_key=$(echo "${key_json}" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")

  echo "発行完了: AccessKeyId=${key_id}"

  # ~/.aws/credentials の [default] を更新
  echo "--- ~/.aws/credentials [default] を更新 ---"
  aws configure set aws_access_key_id     "${key_id}"
  aws configure set aws_secret_access_key "${secret_key}"

  echo "更新完了。"
}

################################################################################
# 関数名   : verify
# 概要     : 更新後の [default] プロファイルで認証情報を確認する
# 引数     : なし
# 戻り値   : なし
################################################################################
verify() {
  echo "--- 動作確認（[default] プロファイル）---"

  # AssumeRole 系の環境変数をクリアして default プロファイルを確実に使用
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE 2>/dev/null || true

  aws sts get-caller-identity
}

################################################################################
# メイン処理
################################################################################
echo "実行開始: $(date)"
echo "------------------------------------------------------------"

delete_existing_keys
create_key
verify

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
