#!/bin/bash
################################################################################
# SSH接続用キーペア作成
#
# - 名前: ts-010-keypair
# - 用途: EC2インスタンスへのSSH接続
# Last updated: 2026-03-26 20:41:31
################################################################################
set -euo pipefail

# スクリプト自身のディレクトリを取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)
# プロジェクトルートを取得
PROJECT_ROOT=$(cd ${SCRIPT_DIR}/../../; pwd)

# 設定ファイルを読み込む
source "${SCRIPT_DIR}/config.sh"

MY_NAME=${0##*/}
MY_SRC_DIR=./${MY_NAME}.src
LOG_PATH=${MY_NAME}.log

################################################################################
# MY_SRC_DIRの削除
################################################################################
term() {
  rm -rf "${MY_SRC_DIR:?}"
}
trap 'term; exit 1' ERR INT TERM
trap 'term' EXIT

################################################################################
# 以降ログ
################################################################################
exec >> "${LOG_PATH}" 2>&1

KEYPAIR_NAME="ts-010-keypair"
KEYPAIR_FILE="${PROJECT_ROOT}/${KEYPAIR_NAME}.pem"

################################################################################
# 設定されたキーペアの確認
################################################################################
confirm_keypair() {
  echo "############################################################"
  echo "# キーペア [$KEYPAIR_NAME] の設定確認"
  echo "############################################################"
  aws ec2 describe-key-pairs --key-names "$KEYPAIR_NAME" --query "KeyPairs[*].{KeyName:KeyName,KeyFingerprint:KeyFingerprint}" --output json 2>/dev/null || \
    echo "キーペア [$KEYPAIR_NAME] は存在しません。"
  echo
}

################################################################################
# キーペア作成処理
################################################################################
make_keypair() {
  echo "############################################################"
  echo "# キーペア [$KEYPAIR_NAME] の作成処理"
  echo "############################################################"

  # 既存のキーペアを検索
  EXISTING_KEYPAIR=$(aws ec2 describe-key-pairs --key-names "$KEYPAIR_NAME" --query "KeyPairs[0].KeyName" --output text 2>/dev/null || echo "None")

  # 既存のキーペアを削除
  if [ "$EXISTING_KEYPAIR" != "None" ]; then
    echo "既存のキーペア [$KEYPAIR_NAME] を削除します。"
    aws ec2 delete-key-pair --key-name "$KEYPAIR_NAME"
    echo "削除が完了しました。再作成します。"
  else
    echo "キーペア [$KEYPAIR_NAME] は存在しないため、新規作成します。"
  fi

  # 既存のキーファイルを削除
  if [ -f "$KEYPAIR_FILE" ]; then
    echo "既存のキーファイル [$KEYPAIR_FILE] を削除します。"
    rm -f "$KEYPAIR_FILE"
  fi

  # 新規キーペア作成
  echo "キーペア [$KEYPAIR_NAME] を作成中..."
  aws ec2 create-key-pair --key-name "$KEYPAIR_NAME" \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}}]" \
    --query "KeyMaterial" --output text > "$KEYPAIR_FILE"
  
  # キーファイルの権限設定
  chmod 400 "$KEYPAIR_FILE"
  
  echo "キーペア [$KEYPAIR_NAME] の作成が完了しました。"
  echo "キーファイル: $KEYPAIR_FILE"
  echo "権限: 400 (所有者のみ読み取り可能)"
  echo
}

################################################################################
# メイン処理
################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

echo "実行開始: $(date)"
echo "------------------------------------------------------------"

# 実行前確認
confirm_keypair

# 作成処理
make_keypair

# 実行後確認
confirm_keypair

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
