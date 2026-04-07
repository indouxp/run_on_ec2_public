#!/bin/bash
################################################################################
# Subnet作成
#
# - 名前: ts-010-subnet-010
# - CIDR: 10.0.1.0/24
# - VPC: ts-010-vpc-010
# Last updated: 2026-03-26 20:42:29
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

SUBNET_CIDR="10.0.1.0/24"

################################################################################
# 設定されたSubnetの確認
################################################################################
confirm_subnet() {
  echo "############################################################"
  echo "# Subnet [$SUBNET_NAME] の設定確認"
  echo "############################################################"
  aws ec2 describe-subnets --filters "Name=tag:Name,Values=$SUBNET_NAME" --query "Subnets[*].{SubnetId:SubnetId, CidrBlock:CidrBlock, VpcId:VpcId, Tags:Tags}" --output json || \
    echo "Subnet [$SUBNET_NAME] は存在しません。"
  echo
}

################################################################################
# Subnet作成処理
################################################################################
make_subnet() {
  echo "############################################################"
  echo "# Subnet [$SUBNET_NAME] の作成処理"
  echo "############################################################"

  # 親となるVPCのIDを検索
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
  if [ "$VPC_ID" == "None" ]; then
    echo "エラー: 親となるVPC [$VPC_NAME] が見つかりません。"
    exit 1
  fi
  echo "親VPC ID: $VPC_ID を使用します。"

  # 既存のSubnetを検索
  EXISTING_SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$SUBNET_NAME" "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text)

  # 既存のSubnetを削除
  if [ "$EXISTING_SUBNET_ID" != "None" ]; then
    echo "既存のSubnet [$SUBNET_NAME] (ID: $EXISTING_SUBNET_ID) を削除します。"
    aws ec2 delete-subnet --subnet-id "$EXISTING_SUBNET_ID"
    echo "削除が完了しました。再作成します。"
    # AWSの反映待ち
    sleep 5
  else
    echo "Subnet [$SUBNET_NAME] は存在しないため、新規作成します。"
  fi

  # 新規Subnet作成
  SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR" --query "Subnet.SubnetId" --output text)
  echo "Subnetが作成されました。ID: $SUBNET_ID"

  # Subnetに名前タグを付ける
  aws ec2 create-tags --resources "$SUBNET_ID" --tags "Key=Name,Value=$SUBNET_NAME" "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"
  echo "Subnet [$SUBNET_NAME] に名前タグを付けました。"
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
confirm_subnet

# 作成処理
make_subnet

# 実行後確認
confirm_subnet

echo "------------------------------------------------------------"
  echo "実行終了: $(date)"

exit 0
