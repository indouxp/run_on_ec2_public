#!/bin/bash
################################################################################
# セキュリティグループにSSH用ルール追加
#
# - 対象: ts-010-sg-010
# - ルール: SSH (ポート22) インバウンド許可
# - 許可IP: スクリプト実行元のグローバルIPアドレス
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

################################################################################
# セキュリティグループの現在設定確認
################################################################################
confirm_sg() {
  echo "############################################################"
  echo "# セキュリティグループ [$SG_NAME] の現在設定確認"
  echo "############################################################"
  
  # VPC_IDを取得
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
  
  aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].{GroupId:GroupId,IpPermissions:IpPermissions}" --output json || \
    echo "セキュリティグループ [$SG_NAME] は存在しません。"
  echo
}

################################################################################
# SSH用ルール追加処理
################################################################################
add_ssh_rule() {
  echo "############################################################"
  echo "# セキュリティグループ [$SG_NAME] にSSH用ルール追加"
  echo "############################################################"

  # VPC_IDを取得
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
  if [ "$VPC_ID" == "None" ]; then
    echo "エラー: VPC [$VPC_NAME] が見つかりません。"
    exit 1
  fi

  # セキュリティグループIDを取得
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text)
  if [ "$SG_ID" == "None" ]; then
    echo "エラー: セキュリティグループ [$SG_NAME] が見つかりません。"
    exit 1
  fi

  echo "対象セキュリティグループ: $SG_NAME (ID: $SG_ID)"

  # 現在のグローバルIPアドレスを取得
  MY_GLOBAL_IP=$(curl -s ifconfig.me)
  if [ -z "$MY_GLOBAL_IP" ]; then
    echo "エラー: グローバルIPアドレスの取得に失敗しました。"
    exit 1
  fi
  echo "取得したグローバルIPアドレス: $MY_GLOBAL_IP"

  # 既存のSSHルール(ポート22)を削除
  echo "既存のSSHルール(ポート22)を検索・削除します..."
  EXISTING_RULES_JSON=$(aws ec2 describe-security-groups --group-ids "$SG_ID" --output json | jq '[.SecurityGroups[0].IpPermissions[] | select(.FromPort==22 and .ToPort==22 and .IpProtocol=="tcp")]')

  if [ "$EXISTING_RULES_JSON" != "[]" ] && [ -n "$EXISTING_RULES_JSON" ]; then
    aws ec2 revoke-security-group-ingress --group-id "$SG_ID" --ip-permissions "$EXISTING_RULES_JSON"
    echo "既存のSSHルールを削除しました。"
  else
    echo "既存のSSHルールは見つかりませんでした。"
  fi

  # 新しいIPアドレスでSSH用ルールを追加
  echo "新しいIPアドレス [$MY_GLOBAL_IP/32] でSSH用ルール (ポート22) を追加中..."
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "$MY_GLOBAL_IP/32"

  echo "SSH用ルールの追加が完了しました。"
  echo "許可: TCP ポート22 $MY_GLOBAL_IP/32"
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

# SSH用ルール追加処理
add_ssh_rule

# 実行後確認
confirm_sg

echo "------------------------------------------------------------"
echo "実行終了: $(date)"

exit 0
