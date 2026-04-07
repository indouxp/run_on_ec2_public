#!/bin/bash
################################################################################
# VPC作成
#
# - 名前: ts-010-vpc-010
# - CIDR: 10.0.0.0/16
#
# 更新履歴:
#   2026-03-11: PROJECT_ROOTは不要
#
# Last updated: 2026-03-26 20:42:32
################################################################################
set -euo pipefail

# スクリプト自身のディレクトリを取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)

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

VPC_CIDR="10.0.0.0/16"

################################################################################
# 設定されたVPCの確認
################################################################################
confirm_vpc() {
  echo "############################################################"
  echo "# VPC [$VPC_NAME] の設定確認"
  echo "############################################################"
  aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[*].{VpcId:VpcId, CidrBlock:CidrBlock, Tags:Tags}" --output json || \
    echo "VPC [$VPC_NAME] は存在しません。"
  echo
}

################################################################################
# VPC作成処理
################################################################################
make_vpc() {
  echo "############################################################"
  echo "# VPC [$VPC_NAME] の作成処理"
  echo "############################################################"

  # 既存のVPCを検索
  EXISTING_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)

  # 既存のVPCが存在する場合は削除
  if [ "$EXISTING_VPC_ID" != "None" ]; then
    echo "既存のVPC [$VPC_NAME] (ID: $EXISTING_VPC_ID) を削除します。"
    aws ec2 delete-vpc --vpc-id "$EXISTING_VPC_ID"
    echo "既存VPCの削除が完了しました。再作成します。"
  else
    echo "VPC [$VPC_NAME] は存在しないため、新規作成します。"
  fi

  # 新規VPC作成
  VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --query "Vpc.VpcId" --output text)
  echo "VPCが作成されました。ID: $VPC_ID"

  # VPCに名前タグを付ける
  aws ec2 create-tags --resources "$VPC_ID" --tags "Key=Name,Value=$VPC_NAME" "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"
  echo "VPC [$VPC_NAME] に名前タグを付けました。"

  # DNSホスト名とDNS解決を有効化
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames "{\"Value\":true}"
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support "{\"Value\":true}"
  echo "VPC [$VPC_NAME] のDNS設定を有効化しました。"
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
confirm_vpc

# 作成処理
make_vpc

# 実行後確認
confirm_vpc

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
