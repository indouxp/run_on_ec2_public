#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 作成されたIGWの設定検証
# mk-igw.sh 実行後、以下を確認する
# - IGWが作成されていること
# - IGWに正しいNameタグが付いていること（IGW_NAME）
# - IGWが対象VPC (VPC_NAME) にアタッチされていること
# - アタッチ状態が "available" であること
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
# テスト前処理: VPCの存在確認 + IGWを削除（あれば）
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

# IGWが存在する場合はデタッチ・削除
EXISTING_IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=${IGW_NAME}" \
  --query "InternetGateways[0].InternetGatewayId" --output text)
if [[ "${EXISTING_IGW_ID}" != "None" && -n "${EXISTING_IGW_ID}" ]]; then
  echo "前処理: IGW [${IGW_NAME}] (ID: ${EXISTING_IGW_ID}) を削除します"
  ATTACHED_VPC_ID=$(aws ec2 describe-internet-gateways \
    --internet-gateway-ids "${EXISTING_IGW_ID}" \
    --query "InternetGateways[0].Attachments[0].VpcId" --output text)
  if [[ "${ATTACHED_VPC_ID}" != "None" && -n "${ATTACHED_VPC_ID}" ]]; then
    echo "前処理: IGW [${EXISTING_IGW_ID}] を VPC [${ATTACHED_VPC_ID}] からデタッチします"
    aws ec2 detach-internet-gateway --internet-gateway-id "${EXISTING_IGW_ID}" --vpc-id "${ATTACHED_VPC_ID}"
  fi
  aws ec2 delete-internet-gateway --internet-gateway-id "${EXISTING_IGW_ID}"
  echo "前処理: IGW [${IGW_NAME}] を削除しました"
else
  echo "前処理: IGW [${IGW_NAME}] は存在しません（削除不要）"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-igw.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（IGW設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# IGW設定検証: ${IGW_NAME}"

# VPC IDを再取得
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" --output text)

# IGW存在確認
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=${IGW_NAME}" \
  --query "InternetGateways[0].InternetGatewayId" --output text)
if [[ "${IGW_ID}" == "None" || -z "${IGW_ID}" ]]; then
  echo "[NG] IGW [${IGW_NAME}] が存在しません"
  exit 1
fi
echo "[OK] IGW [${IGW_NAME}] (ID: ${IGW_ID}) が存在します"

# アタッチ先VPC確認
ATTACHED_VPC=$(aws ec2 describe-internet-gateways \
  --internet-gateway-ids "${IGW_ID}" \
  --query "InternetGateways[0].Attachments[0].VpcId" --output text)
if [[ "${ATTACHED_VPC}" == "${VPC_ID}" ]]; then
  echo "[OK] IGW は VPC [${VPC_NAME}] (ID: ${VPC_ID}) にアタッチされています"
else
  echo "[NG] IGW のアタッチ先が想定外です: ${ATTACHED_VPC}（期待値: ${VPC_ID}）"
  exit 1
fi

# アタッチ状態確認
ATTACH_STATE=$(aws ec2 describe-internet-gateways \
  --internet-gateway-ids "${IGW_ID}" \
  --query "InternetGateways[0].Attachments[0].State" --output text)
if [[ "${ATTACH_STATE}" == "available" ]]; then
  echo "[OK] アタッチ状態: ${ATTACH_STATE}"
else
  echo "[NG] アタッチ状態が想定外です: ${ATTACH_STATE}（期待値: available）"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
