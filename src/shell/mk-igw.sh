#!/bin/bash
################################################################################
# インターネットゲートウェイ (IGW) 作成・アタッチスクリプト
#
# - 対象VPC: ts-010-vpc-010
# Last updated: 2026-03-26 20:41:18
################################################################################
set -euo pipefail

# スクリプト自身のディレクトリを取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)
# プロジェクトルートを取得
PROJECT_ROOT=$(cd ${SCRIPT_DIR}/../../; pwd)

# 設定ファイルを読み込む
source "${SCRIPT_DIR}/config.sh"

MY_NAME=${0##*/}
LOG_PATH=./${MY_NAME}.log

exec >> "${LOG_PATH}" 2>&1

################################################################################
# 確認
################################################################################
confirm_igw() {
  echo "############################################################"
  echo "# インターネットゲートウェイ [$IGW_NAME] の設定確認"
  echo "############################################################"
  
  aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$IGW_NAME" --query "InternetGateways[*].{InternetGatewayId:InternetGatewayId,Attachments:Attachments}" --output json || \
    echo "インターネットゲートウェイ [$IGW_NAME] は存在しません。"
  echo
}

################################################################################
# 作成・アタッチ処理
################################################################################
create_and_attach_igw() {
  echo "############################################################"
  echo "# インターネットゲートウェイ [$IGW_NAME] の作成・アタッチ処理"
  echo "############################################################"

  # 親となるVPCのIDを検索
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
  if [ "$VPC_ID" == "None" ]; then
    echo "エラー: 親となるVPC [$VPC_NAME] が見つかりません。"
    exit 1
  fi
  echo "親VPC ID: $VPC_ID を使用します。"

  # 既存のIGWを検索
  EXISTING_IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$IGW_NAME" --query "InternetGateways[0].InternetGatewayId" --output text)

  # 既存のIGWをデタッチ・削除
  if [ "$EXISTING_IGW_ID" != "None" ]; then
    echo "既存のIGW [$IGW_NAME] (ID: $EXISTING_IGW_ID) をデタッチ・削除します。"
    # アタッチされているVPCがあればデタッチ
    ATTACHED_VPC_ID=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$EXISTING_IGW_ID" --query "InternetGateways[0].Attachments[0].VpcId" --output text)
    if [ "$ATTACHED_VPC_ID" != "None" ]; then
      echo "VPC [$ATTACHED_VPC_ID] からIGWをデタッチ中..."
      aws ec2 detach-internet-gateway --internet-gateway-id "$EXISTING_IGW_ID" --vpc-id "$ATTACHED_VPC_ID"
      sleep 5 # 反映待ち
    fi
    aws ec2 delete-internet-gateway --internet-gateway-id "$EXISTING_IGW_ID"
    echo "既存IGWの削除が完了しました。再作成します。"
    sleep 5 # 反映待ち
  else
    echo "IGW [$IGW_NAME] は存在しないため、新規作成します。"
  fi

  # 新規IGW作成
  IGW_ID=$(aws ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)
  echo "IGWが作成されました。ID: $IGW_ID"

  # IGWに名前タグを付ける
  aws ec2 create-tags --resources "$IGW_ID" --tags "Key=Name,Value=$IGW_NAME" "Key=${PRJ_TAG_KEY},Value=${PRJ_TAG_VALUE}"
  echo "IGW [$IGW_NAME] に名前タグを付けました。"

  # IGWをVPCにアタッチ
  echo "IGW [$IGW_ID] をVPC [$VPC_ID] にアタッチします。"
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
  echo "IGWのアタッチが完了しました。"
  echo
}

################################################################################
# メイン処理
################################################################################
echo "実行開始: $(date)"
echo "------------------------------------------------------------"

confirm_igw
create_and_attach_igw
confirm_igw

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
