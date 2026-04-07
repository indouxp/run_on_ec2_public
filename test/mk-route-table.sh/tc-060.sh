#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 設定されたルートの検証
# mk-route-table.sh 実行後、以下を確認する
# - 0.0.0.0/0 ルートが存在すること
# - ルートのゲートウェイが IGW_NAME の ID と一致すること
# - ルートの状態が "active" であること
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
# テスト前処理: VPC・IGWの存在確認 + 0.0.0.0/0 ルートを削除（あれば）
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
  echo "前処理: 0.0.0.0/0 ルートを削除しました"
else
  echo "前処理: 0.0.0.0/0 ルートは存在しません（削除不要）"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-route-table.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（ルート設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# ルート設定検証: ${VPC_NAME} のルートテーブル"

# IDを再取得
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" --output text)
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=${IGW_NAME}" \
  --query "InternetGateways[0].InternetGatewayId" --output text)
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "RouteTables[0].RouteTableId" --output text)

# 0.0.0.0/0 ルート存在確認
ROUTE_GW=$(aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" \
  --output text)
if [[ "${ROUTE_GW}" == "None" || -z "${ROUTE_GW}" ]]; then
  echo "[NG] 0.0.0.0/0 ルートが存在しません"
  exit 1
fi
echo "[OK] 0.0.0.0/0 ルートが存在します (GatewayId: ${ROUTE_GW})"

# ゲートウェイIDがIGWと一致するか確認
if [[ "${ROUTE_GW}" == "${IGW_ID}" ]]; then
  echo "[OK] ゲートウェイIDが IGW [${IGW_NAME}] (ID: ${IGW_ID}) と一致しています"
else
  echo "[NG] ゲートウェイIDが想定外です: ${ROUTE_GW}（期待値: ${IGW_ID}）"
  exit 1
fi

# ルート状態確認
ROUTE_STATE=$(aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].State | [0]" \
  --output text)
if [[ "${ROUTE_STATE}" == "active" ]]; then
  echo "[OK] ルート状態: ${ROUTE_STATE}"
else
  echo "[NG] ルート状態が想定外です: ${ROUTE_STATE}（期待値: active）"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
