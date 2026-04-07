#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 作成されたVPCの設定検証
# mk-vpc.sh 実行後、以下を確認する
# - VPCが作成されていること
# - CIDRブロックが 10.0.0.0/16 であること
# - DNS ホスト名・DNS解決が有効であること
#
# Last updated: 2026-03-12 00:00:00
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

# VPCが存在する場合は削除
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" --output text)
if [[ "${VPC_ID}" != "None" && -n "${VPC_ID}" ]]; then
  echo "前処理: VPC [${VPC_NAME}] (ID: ${VPC_ID}) を削除します"
  aws ec2 delete-vpc --vpc-id "${VPC_ID}"
  echo "前処理: VPC [${VPC_NAME}] を削除しました"
else
  echo "前処理: VPC [${VPC_NAME}] は存在しません（削除不要）"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-vpc.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（VPC設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# VPC設定検証: ${VPC_NAME}"

# VPC存在確認
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" --output text)
if [[ "${VPC_ID}" == "None" || -z "${VPC_ID}" ]]; then
  echo "[NG] VPC [${VPC_NAME}] が存在しません"
  exit 1
fi
echo "[OK] VPC [${VPC_NAME}] (ID: ${VPC_ID}) が存在します"

# CIDRブロック確認
CIDR=$(aws ec2 describe-vpcs \
  --vpc-ids "${VPC_ID}" \
  --query "Vpcs[0].CidrBlock" --output text)
if [[ "${CIDR}" == "10.0.0.0/16" ]]; then
  echo "[OK] CIDRブロック: ${CIDR}"
else
  echo "[NG] CIDRブロックが想定外です: ${CIDR}（期待値: 10.0.0.0/16）"
  exit 1
fi

# DNS ホスト名有効確認
DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute \
  --vpc-id "${VPC_ID}" \
  --attribute enableDnsHostnames \
  --query "EnableDnsHostnames.Value" --output text)
if [[ "${DNS_HOSTNAMES}" == "True" ]]; then
  echo "[OK] DNS ホスト名: 有効"
else
  echo "[NG] DNS ホスト名が無効です"
  exit 1
fi

# DNS 解決有効確認
DNS_SUPPORT=$(aws ec2 describe-vpc-attribute \
  --vpc-id "${VPC_ID}" \
  --attribute enableDnsSupport \
  --query "EnableDnsSupport.Value" --output text)
if [[ "${DNS_SUPPORT}" == "True" ]]; then
  echo "[OK] DNS 解決: 有効"
else
  echo "[NG] DNS 解決が無効です"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
