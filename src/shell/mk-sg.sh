#!/bin/bash
################################################################################
# セキュリティグループ作成
#
# - 名前: ts-010-sg-010
# - 説明: S3イベント連携によるEC2自動処理用
# - ルール: インバウンドなし / アウトバウンドは全許可 (デフォルト)
# Last updated: 2026-03-26 20:42:24
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

# VPC_IDを自動で取得 (タグから検索)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)

################################################################################
# 設定されたセキュリティグループの確認
################################################################################
confirm_sg() {
  echo "############################################################"
  echo "# セキュリティグループ [$SG_NAME] の設定確認"
  echo "############################################################"
  aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --output json || \
    echo "セキュリティグループ [$SG_NAME] は存在しません。"
  echo
}

################################################################################
# セキュリティグループ作成処理
################################################################################
make_sg() {
  echo "############################################################"
  echo "# セキュリティグループ [$SG_NAME] の作成処理"
  echo "############################################################"

  # 既存のセキュリティグループを検索
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)

  # 既存のセキュリティグループを削除
  if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    echo "既存のセキュリティグループ [$SG_NAME] (ID: $SG_ID) を削除します。"
    aws ec2 delete-security-group --group-id "$SG_ID"
    echo "削除が完了しました。再作成します。"
    # AWSの反映待ち
    sleep 5
  else
    echo "セキュリティグループ [$SG_NAME] は存在しないため、新規作成します。"
  fi

  # 新規セキュリティグループ作成
  if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    echo "エラー: VPC [$VPC_NAME] が見つかりません。"
    exit 1
  fi
  echo "VPC ID: $VPC_ID (Name: $VPC_NAME) を使用します。"
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "For S3 trigger type shell script auto execution system" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)

  aws ec2 create-tags --resources "$SG_ID" --tags "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"
  echo "セキュリティグループ [$SG_NAME] の作成が完了しました。"
  echo "インバウンドルールは設定せず、アウトバウンドはデフォルト（全許可）です。"
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
confirm_sg

# 作成処理
make_sg

# 実行後確認
confirm_sg

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
