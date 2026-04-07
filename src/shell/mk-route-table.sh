#!/bin/bash
################################################################################
# ルートテーブル設定
#
# - インターネットゲートウェイへのルートを追加
# - パブリックサブネットからインターネットへのアクセスを可能にします
# Last updated: 2026-03-26 20:41:54
################################################################################
set -euo pipefail

# スクリプト自身のディレクトリを取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)
# プロジェクトルートを取得
PROJECT_ROOT=$(cd ${SCRIPT_DIR}/../../; pwd)

# 設定ファイルを読み込みます
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

################################################################################
# 現在のルートテーブル設定確認
################################################################################
confirm_route_table() {
  echo "############################################################"
  echo "# ルートテーブルの現在設定確認"
  echo "############################################################"
  
  # VPC_IDを取得
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
  
  # ルートテーブルを取得
  ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[0].RouteTableId" --output text)
  
  echo "VPC: $VPC_NAME (ID: $VPC_ID)"
  echo "ルートテーブルID: $ROUTE_TABLE_ID"
  
  # 現在のルートを表示
  aws ec2 describe-route-tables --route-table-ids "$ROUTE_TABLE_ID" --query "RouteTables[0].Routes" --output json
  echo
}

################################################################################
# インターネットゲートウェイへのルート追加
################################################################################
add_igw_route() {
  echo "############################################################"
  echo "# インターネットゲートウェイへのルート追加"
  echo "############################################################"

  # VPC_IDを取得
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
  
  # ルートテーブルIDを取得
  ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[0].RouteTableId" --output text)
  
  # インターネットゲートウェイIDを取得
  IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$IGW_NAME" --query "InternetGateways[0].InternetGatewayId" --output text)
  
  if [ "$IGW_ID" == "None" ]; then
    echo "エラー: インターネットゲートウェイ [$IGW_NAME] が見つかりません。"
    exit 1
  fi
  
  echo "VPC: $VPC_NAME (ID: $VPC_ID)"
  echo "ルートテーブル: $ROUTE_TABLE_ID"
  echo "インターネットゲートウェイ: $IGW_NAME (ID: $IGW_ID)"
  
  # 既存の 0.0.0.0/0 ルートを確認・削除（再作成のため）
  EXISTING_ROUTE=$(aws ec2 describe-route-tables \
    --route-table-ids "$ROUTE_TABLE_ID" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].DestinationCidrBlock" \
    --output text)
  if [ -n "$EXISTING_ROUTE" ]; then
    echo "既存の 0.0.0.0/0 ルートを削除します。"
    aws ec2 delete-route \
      --route-table-id "$ROUTE_TABLE_ID" \
      --destination-cidr-block "0.0.0.0/0"
    echo "既存ルートの削除が完了しました。再作成します。"
  else
    echo "0.0.0.0/0 ルートは存在しないため、新規追加します。"
  fi

  # インターネットゲートウェイへのルートを追加
  echo "インターネットゲートウェイへのルート (0.0.0.0/0) を追加中..."
  aws ec2 create-route \
    --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "$IGW_ID"

  echo "ルートの追加が完了しました。"
  echo "許可: 0.0.0.0/0 → $IGW_NAME (インターネットゲートウェイ)"

  # ルートテーブルにプロジェクトタグを付与
  aws ec2 create-tags --resources "$ROUTE_TABLE_ID" --tags "Key=Name,Value=${ROUTE_TABLE_NAME}" "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"
  echo "ルートテーブル [$ROUTE_TABLE_ID] に Name タグ・プロジェクトタグを付けました。"
  echo
}

################################################################################
# メイン処理
################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

echo "実行開始: $(date)"
echo "------------------------------------------------------------"

# 現在のルートテーブル設定確認
confirm_route_table

# インターネットゲートウェイへのルート追加
add_igw_route

# 実行後確認
confirm_route_table

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
