#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# IGWが存在する状態から実行、正常処理（デタッチ・削除して再作成）
#
# 前提: mk-vpc.sh により VPC (VPC_NAME) が作成済みであること
#
# Last updated: 2026-03-15 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

cp config.sh.org config.sh

. assume-role.sh

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
# 変更部表示
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理: VPCの存在確認 + IGWを作成してアタッチ
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# VPCの存在確認（前提条件）
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" --output text)
if [[ "${VPC_ID}" == "None" || -z "${VPC_ID}" ]]; then
  echo "前提条件エラー: VPC [${VPC_NAME}] が存在しません。mk-vpc.sh を先に実行してください。"
  exit 1
fi
echo "前処理: VPC [${VPC_NAME}] (ID: ${VPC_ID}) の存在を確認しました"

# IGWが存在する場合はデタッチ・削除してから再作成
EXISTING_IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=${IGW_NAME}" \
  --query "InternetGateways[0].InternetGatewayId" --output text)
if [[ "${EXISTING_IGW_ID}" != "None" && -n "${EXISTING_IGW_ID}" ]]; then
  echo "前処理: IGW [${IGW_NAME}] (ID: ${EXISTING_IGW_ID}) が存在します"
  ATTACHED_VPC_ID=$(aws ec2 describe-internet-gateways \
    --internet-gateway-ids "${EXISTING_IGW_ID}" \
    --query "InternetGateways[0].Attachments[0].VpcId" --output text)
  if [[ "${ATTACHED_VPC_ID}" != "None" && -n "${ATTACHED_VPC_ID}" ]]; then
    echo "前処理: IGW [${EXISTING_IGW_ID}] を VPC [${ATTACHED_VPC_ID}] からデタッチします"
    aws ec2 detach-internet-gateway --internet-gateway-id "${EXISTING_IGW_ID}" --vpc-id "${ATTACHED_VPC_ID}"
  fi
  aws ec2 delete-internet-gateway --internet-gateway-id "${EXISTING_IGW_ID}"
  echo "前処理: 既存IGW [${IGW_NAME}] を削除しました"
fi

# IGWを新規作成してアタッチ（スクリプトが「IGWあり」の状態で実行されるようにする）
PRE_IGW_ID=$(aws ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 create-tags --resources "${PRE_IGW_ID}" --tags "Key=Name,Value=${IGW_NAME}"
aws ec2 attach-internet-gateway --internet-gateway-id "${PRE_IGW_ID}" --vpc-id "${VPC_ID}"
echo "前処理: IGW [${IGW_NAME}] (ID: ${PRE_IGW_ID}) を作成してVPCにアタッチしました"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
