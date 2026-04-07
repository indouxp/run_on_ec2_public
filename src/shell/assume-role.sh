#!/bin/bash
################################################################################
# スクリプト名 : assume-role.sh
# 概要         : ts-010-role-build へ AssumeRole し、一時認証情報を環境変数に設定する
#                source で読み込んで使用する（直接実行不可）
# 使用方法     : source assume-role.sh [build|exec]
#                  build : ts-010-role-build（デフォルト）
#                  exec  : ts-010-role-exec
# Created      : 2026-03-11
# Last updated : 2026-03-11 17:00:00
# Author       : Tsystem
# 更新履歴     :
#    2026-03-11: 初版
################################################################################

# source されているかチェック（直接実行を禁止）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] このスクリプトは source で読み込んでください。" >&2
  echo "        使用方法: source ${0##*/} [build|exec]" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 設定ファイルの読み込み
# ------------------------------------------------------------------------------
# スクリプト自身のディレクトリを取得
_AR_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# config.sh を読み込む（未読み込みの場合のみ）
if [[ -z "${PRJ_PREFIX:-}" ]]; then
  source "${_AR_SCRIPT_DIR}/config.sh"
fi

# ------------------------------------------------------------------------------
# 変数定義
# ------------------------------------------------------------------------------
# AssumeRole対象ロール（引数で切り替え可能、デフォルトは build）
_AR_ROLE_TYPE="${1:-build}"

# ロール名を引数に応じて決定
case "${_AR_ROLE_TYPE}" in
  build) _AR_ROLE_NAME="${IAM_ROLE_BUILD_NAME}" ;;  # 構築用ロール
  exec)  _AR_ROLE_NAME="${IAM_ROLE_EXEC_NAME}"  ;;  # 実行用ロール
  *)
    echo "[ERROR] 不明なロールタイプ: ${_AR_ROLE_TYPE}（build または exec を指定してください）" >&2
    return 1
    ;;
esac

# AWSアカウントIDを取得
_AR_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [[ -z "${_AR_ACCOUNT_ID}" ]]; then
  echo "[ERROR] AWSアカウントIDの取得に失敗しました。認証情報を確認してください。" >&2
  return 1
fi

# AssumeRole対象のARN
_AR_ROLE_ARN="arn:aws:iam::${_AR_ACCOUNT_ID}:role/${_AR_ROLE_NAME}"

# セッション名（ユーザー名 + タイムスタンプ）
_AR_SESSION_NAME="${USER:-session}-$(date '+%Y%m%d%H%M%S')"

# ------------------------------------------------------------------------------
# AssumeRole 実行
# ------------------------------------------------------------------------------
echo "[INFO] AssumeRole: ${_AR_ROLE_ARN}"

# 一時認証情報を取得
_AR_CREDS=$(aws sts assume-role \
  --role-arn "${_AR_ROLE_ARN}" \
  --role-session-name "${_AR_SESSION_NAME}" \
  --output json 2>&1)

if [[ $? -ne 0 ]]; then
  echo "[ERROR] AssumeRole に失敗しました。" >&2
  echo "${_AR_CREDS}" >&2
  unset _AR_SCRIPT_DIR _AR_ROLE_TYPE _AR_ROLE_NAME _AR_ACCOUNT_ID _AR_ROLE_ARN _AR_SESSION_NAME _AR_CREDS
  return 1
fi

# 環境変数に一時認証情報を設定
export AWS_ACCESS_KEY_ID=$(echo "${_AR_CREDS}"     | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo "${_AR_CREDS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo "${_AR_CREDS}"     | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")

# 有効期限を表示
_AR_EXPIRATION=$(echo "${_AR_CREDS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['Expiration'])")

# ------------------------------------------------------------------------------
# 設定後の確認
# ------------------------------------------------------------------------------
echo "[INFO] AssumeRole 完了"
echo "[INFO] ロール  : ${_AR_ROLE_NAME}"
echo "[INFO] 有効期限: ${_AR_EXPIRATION}"
echo "[INFO] 現在のID:"
aws sts get-caller-identity

# 一時変数を削除（環境を汚染しない）
unset _AR_SCRIPT_DIR _AR_ROLE_TYPE _AR_ROLE_NAME _AR_ACCOUNT_ID _AR_ROLE_ARN _AR_SESSION_NAME _AR_CREDS _AR_EXPIRATION
