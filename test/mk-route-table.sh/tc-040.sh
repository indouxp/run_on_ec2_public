#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# 0.0.0.0/0 ルートが存在する状態から実行、正常処理（削除して再作成）
#
# 前提:
#   - mk-vpc.sh により VPC (VPC_NAME) が作成済みであること
#   - mk-igw.sh により IGW (IGW_NAME) が作成済みかつ VPC にアタッチ済みであること
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
# テスト前処理: VPC・IGWの存在確認 + 0.0.0.0/0 ルートを作成
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

# IGWの存在確認（前提条件）
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=${IGW_NAME}" \
  --query "InternetGateways[0].InternetGatewayId" --output text)
if [[ "${IGW_ID}" == "None" || -z "${IGW_ID}" ]]; then
  echo "前提条件エラー: IGW [${IGW_NAME}] が存在しません。mk-igw.sh を先に実行してください。"
  exit 1
fi
echo "前処理: IGW [${IGW_NAME}] (ID: ${IGW_ID}) の存在を確認しました"

# メインルートテーブルIDを取得
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "RouteTables[0].RouteTableId" --output text)
echo "前処理: ルートテーブル (ID: ${ROUTE_TABLE_ID}) を確認しました"

# 0.0.0.0/0 ルートが存在する場合は削除
EXISTING_ROUTE=$(aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].DestinationCidrBlock" \
  --output text)
if [[ -n "${EXISTING_ROUTE}" ]]; then
  aws ec2 delete-route \
    --route-table-id "${ROUTE_TABLE_ID}" \
    --destination-cidr-block "0.0.0.0/0"
  echo "前処理: 既存の 0.0.0.0/0 ルートを削除しました"
fi

# 0.0.0.0/0 ルートを作成（スクリプトが「ルートあり」の状態で実行されるようにする）
aws ec2 create-route \
  --route-table-id "${ROUTE_TABLE_ID}" \
  --destination-cidr-block "0.0.0.0/0" \
  --gateway-id "${IGW_ID}"
echo "前処理: 0.0.0.0/0 → ${IGW_ID} ルートを作成しました"

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
