#!/bin/bash
################################################################################
# SSH接続可能なEC2インスタンス作成
#
# - 名前: ts-010-ec2-ssh-010
# - キーペア: ts-010-keypair
# - セキュリティグループ: ts-010-sg-010 (SSH用ルール追加済み)
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

# ログファイルへのリダイレクト
exec >> "${LOG_PATH}" 2>&1

EC2_INSTANCE_NAME="ts-010-ec2-ssh-010"
KEYPAIR_NAME="ts-010-keypair"
DEFAULT_AMI_ID="ami-09ed31f8f34719e20"

################################################################################
# 必要なリソースの確認
################################################################################
confirm_resources() {
  echo "############################################################"
  echo "# 必要なリソースの確認"
  echo "############################################################"
  
  # VPC確認
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
  if [ "$VPC_ID" == "None" ]; then
    echo "エラー: VPC [$VPC_NAME] が見つかりません。"
    exit 1
  fi
  echo "VPC: $VPC_NAME (ID: $VPC_ID) ✓"
  
  # Subnet確認
  SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$SUBNET_NAME" --query "Subnets[0].SubnetId" --output text)
  if [ "$SUBNET_ID" == "None" ]; then
    echo "エラー: Subnet [$SUBNET_NAME] が見つかりません。"
    exit 1
  fi
  echo "Subnet: $SUBNET_NAME (ID: $SUBNET_ID) ✓"
  
  # セキュリティグループ確認
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --query "SecurityGroups[0].GroupId" --output text)
  if [ "$SG_ID" == "None" ]; then
    echo "エラー: セキュリティグループ [$SG_NAME] が見つかりません。"
    exit 1
  fi
  echo "セキュリティグループ: $SG_NAME (ID: $SG_ID) ✓"
  
  # キーペア確認
  KEYPAIR_EXISTS=$(aws ec2 describe-key-pairs --key-names "$KEYPAIR_NAME" --query "KeyPairs[0].KeyName" --output text 2>/dev/null || echo "None")
  if [ "$KEYPAIR_EXISTS" == "None" ]; then
    echo "エラー: キーペア [$KEYPAIR_NAME] が見つかりません。"
    exit 1
  fi
  echo "キーペア: $KEYPAIR_NAME ✓"
  
  # IAMロール確認
  IAM_ROLE_NAME="ts-010-role-ec2-010"
  PROFILE_EXISTS=$(aws iam get-instance-profile --instance-profile-name "$IAM_ROLE_NAME" --query "InstanceProfile.InstanceProfileName" --output text 2>/dev/null || echo "None")
  if [ "$PROFILE_EXISTS" == "None" ]; then
    echo "エラー: IAM Instance Profile [$IAM_ROLE_NAME] が見つかりません。"
    exit 1
  fi
  PROFILE_ARN=$(aws iam get-instance-profile --instance-profile-name "$IAM_ROLE_NAME" --query "InstanceProfile.Arn" --output text)
  echo "IAMロール: $IAM_ROLE_NAME (ARN: $PROFILE_ARN) ✓"
  
  echo
}

################################################################################
# EC2インスタンス作成処理
################################################################################
create_ec2_instance() {
  echo "############################################################"
  echo "# EC2インスタンス [$EC2_INSTANCE_NAME] の作成処理"
  echo "############################################################"

  # 既存のインスタンスを確認
  EXISTING_INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$EC2_INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped,pending" --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "None")
  
  if [ "$EXISTING_INSTANCE" != "None" ]; then
    echo "既存のインスタンス [$EC2_INSTANCE_NAME] (ID: $EXISTING_INSTANCE) が見つかりました。"
    echo "既存インスタンスを削除してから新規作成します。"
    aws ec2 terminate-instances --instance-ids "$EXISTING_INSTANCE"
    echo "インスタンス削除中... 完了まで待機します。"
    aws ec2 wait instance-terminated --instance-ids "$EXISTING_INSTANCE"
    echo "既存インスタンスの削除が完了しました。"
  fi

  # 新規インスタンス作成
  echo "新しいEC2インスタンスを作成中..."
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$DEFAULT_AMI_ID" \
    --instance-type t3.micro \
    --key-name "$KEYPAIR_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$SUBNET_ID" \
    --iam-instance-profile Name="$IAM_ROLE_NAME" \
    --associate-public-ip-address \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2_INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)

  echo "EC2インスタンスが作成されました。ID: $INSTANCE_ID"
  echo "インスタンスの起動完了まで待機中..."
  
  # インスタンスの起動完了を待機
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
  echo "インスタンスの起動が完了しました。"
  
  # パブリックIPアドレスを取得
  PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
  echo "パブリックIPアドレス: $PUBLIC_IP"
  
  echo
  echo "############################################################"
  echo "# SSH接続情報"
  echo "############################################################"
  echo "インスタンスID: $INSTANCE_ID"
  echo "パブリックIP: $PUBLIC_IP"
  echo "キーファイル: ${PROJECT_ROOT}/${KEYPAIR_NAME}.pem"
  echo "SSH接続コマンド:"
  echo "  ssh -i ${PROJECT_ROOT}/${KEYPAIR_NAME}.pem ec2-user@$PUBLIC_IP"
  echo "############################################################"
  echo
}

################################################################################
# メイン処理
################################################################################
[ ! -d ${MY_SRC_DIR} ] && { mkdir -p ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

echo "実行開始: $(date)"
echo "------------------------------------------------------------"

# 必要なリソースの確認
confirm_resources

# EC2インスタンス作成処理
create_ec2_instance

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0