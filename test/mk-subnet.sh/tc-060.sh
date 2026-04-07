#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 作成されたSubnetの設定検証
# mk-subnet.sh 実行後、以下を確認する
# - Subnetが作成されていること
# - SubnetにCIDR (10.0.1.0/24) が設定されていること
# - Subnetが対象VPC (VPC_NAME) に属していること
# - SubnetにNameタグが付いていること（SUBNET_NAME）
# - SubnetのStateが "available" であること
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
# テスト（mk-subnet.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（Subnet設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# Subnet設定検証: ${SUBNET_NAME}"

EXPECTED_CIDR="10.0.1.0/24"

# VPC IDを再取得
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" --output text)

# Subnet存在確認
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=${SUBNET_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[0].SubnetId" --output text)
if [[ "${SUBNET_ID}" == "None" || -z "${SUBNET_ID}" ]]; then
  echo "[NG] Subnet [${SUBNET_NAME}] が存在しません"
  exit 1
fi
echo "[OK] Subnet [${SUBNET_NAME}] (ID: ${SUBNET_ID}) が存在します"

# CIDRブロック確認
CIDR=$(aws ec2 describe-subnets \
  --subnet-ids "${SUBNET_ID}" \
  --query "Subnets[0].CidrBlock" --output text)
if [[ "${CIDR}" == "${EXPECTED_CIDR}" ]]; then
  echo "[OK] CIDRブロック: ${CIDR}"
else
  echo "[NG] CIDRブロックが想定外です: ${CIDR}（期待値: ${EXPECTED_CIDR}）"
  exit 1
fi

# VPC所属確認
SUBNET_VPC_ID=$(aws ec2 describe-subnets \
  --subnet-ids "${SUBNET_ID}" \
  --query "Subnets[0].VpcId" --output text)
if [[ "${SUBNET_VPC_ID}" == "${VPC_ID}" ]]; then
  echo "[OK] Subnet は VPC [${VPC_NAME}] (ID: ${VPC_ID}) に属しています"
else
  echo "[NG] SubnetのVPCが想定外です: ${SUBNET_VPC_ID}（期待値: ${VPC_ID}）"
  exit 1
fi

# Nameタグ確認
SUBNET_NAME_TAG=$(aws ec2 describe-subnets \
  --subnet-ids "${SUBNET_ID}" \
  --query "Subnets[0].Tags[?Key=='Name'].Value | [0]" --output text)
if [[ "${SUBNET_NAME_TAG}" == "${SUBNET_NAME}" ]]; then
  echo "[OK] Nameタグ: ${SUBNET_NAME_TAG}"
else
  echo "[NG] Nameタグが想定外です: ${SUBNET_NAME_TAG}（期待値: ${SUBNET_NAME}）"
  exit 1
fi

# State確認
SUBNET_STATE=$(aws ec2 describe-subnets \
  --subnet-ids "${SUBNET_ID}" \
  --query "Subnets[0].State" --output text)
if [[ "${SUBNET_STATE}" == "available" ]]; then
  echo "[OK] State: ${SUBNET_STATE}"
else
  echo "[NG] Stateが想定外です: ${SUBNET_STATE}（期待値: available）"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
