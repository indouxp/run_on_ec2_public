#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# Subnetが存在しない状態から実行、正常処理（新規作成）
#
# 前提: mk-vpc.sh により VPC (VPC_NAME) が作成済みであること
#
# Last updated: 2026-03-19 00:00:00
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
# テスト前処理: VPCの存在確認 + Subnetを削除（あれば）
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

# Subnetが存在する場合は削除
EXISTING_SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=${SUBNET_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[0].SubnetId" --output text)
if [[ "${EXISTING_SUBNET_ID}" != "None" && -n "${EXISTING_SUBNET_ID}" ]]; then
  echo "前処理: Subnet [${SUBNET_NAME}] (ID: ${EXISTING_SUBNET_ID}) を削除します"
  aws ec2 delete-subnet --subnet-id "${EXISTING_SUBNET_ID}"
  echo "前処理: Subnet [${SUBNET_NAME}] を削除しました"
else
  echo "前処理: Subnet [${SUBNET_NAME}] は存在しません（削除不要）"
fi

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
