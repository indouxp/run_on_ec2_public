#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# VPCが存在する状態から実行、正常処理（削除して再作成）
#
# Last updated: 2026-03-11 17:06:31
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
# テスト前処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm ${TARGET_SCRIPT}.log

# VPCが存在しない場合は作成（スクリプト内で削除→再作成されることを確認するため）
# VPCが存在する場合は依存リソース（IGW・サブネット）を先にクリーンアップする
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" --output text)
if [[ "${VPC_ID}" != "None" && -n "${VPC_ID}" ]]; then
  echo "前処理: VPC [${VPC_NAME}] (ID: ${VPC_ID}) が存在します"

  # IGWをデタッチ・削除
  IGW_IDS=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[*].InternetGatewayId" --output text)
  for IGW_ID in ${IGW_IDS}; do
    echo "前処理: IGW [${IGW_ID}] をデタッチ・削除します"
    aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}"
    aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}"
    echo "前処理: IGW [${IGW_ID}] を削除しました"
  done

  # サブネットを削除
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[*].SubnetId" --output text)
  for SUBNET_ID in ${SUBNET_IDS}; do
    echo "前処理: サブネット [${SUBNET_ID}] を削除します"
    aws ec2 delete-subnet --subnet-id "${SUBNET_ID}"
    echo "前処理: サブネット [${SUBNET_ID}] を削除しました"
  done

  # 非デフォルトセキュリティグループを削除
  SG_IDS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for SG_ID in ${SG_IDS}; do
    echo "前処理: セキュリティグループ [${SG_ID}] を削除します"
    aws ec2 delete-security-group --group-id "${SG_ID}"
    echo "前処理: セキュリティグループ [${SG_ID}] を削除しました"
  done
else
  echo "前処理: VPC [${VPC_NAME}] が存在しないため作成します"
  VPC_ID=$(aws ec2 create-vpc --cidr-block "10.0.0.0/16" --query "Vpc.VpcId" --output text)
  aws ec2 create-tags --resources "${VPC_ID}" --tags "Key=Name,Value=${VPC_NAME}"
  echo "前処理: VPC [${VPC_NAME}] (ID: ${VPC_ID}) を作成しました"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
echo "return code=$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト後処理
# なし
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
