#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 作成されたセキュリティグループの設定検証
# mk-sg.sh 実行後、以下を確認する
# - SGが作成されていること
# - SGに正しいNameタグが付いていること（SG_NAME）
# - SGが対象VPC (VPC_NAME) に属していること
# - インバウンドルールが空であること
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
# テスト前処理: VPCの存在確認 + SGを削除（あれば）
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

# SGが存在する場合は削除
EXISTING_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" --output text)
if [[ "${EXISTING_SG_ID}" != "None" && -n "${EXISTING_SG_ID}" ]]; then
  echo "前処理: SG [${SG_NAME}] (ID: ${EXISTING_SG_ID}) を削除します"
  aws ec2 delete-security-group --group-id "${EXISTING_SG_ID}"
  echo "前処理: SG [${SG_NAME}] を削除しました"
else
  echo "前処理: SG [${SG_NAME}] は存在しません（削除不要）"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-sg.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（SG設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# SG設定検証: ${SG_NAME}"

# IDを再取得
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" --output text)

# SG存在確認
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" --output text)
if [[ "${SG_ID}" == "None" || -z "${SG_ID}" ]]; then
  echo "[NG] SG [${SG_NAME}] が存在しません"
  exit 1
fi
echo "[OK] SG [${SG_NAME}] (ID: ${SG_ID}) が存在します"

# VPC所属確認
SG_VPC_ID=$(aws ec2 describe-security-groups \
  --group-ids "${SG_ID}" \
  --query "SecurityGroups[0].VpcId" --output text)
if [[ "${SG_VPC_ID}" == "${VPC_ID}" ]]; then
  echo "[OK] SG は VPC [${VPC_NAME}] (ID: ${VPC_ID}) に属しています"
else
  echo "[NG] SGのVPCが想定外です: ${SG_VPC_ID}（期待値: ${VPC_ID}）"
  exit 1
fi

# インバウンドルール確認（空であること）
INGRESS_COUNT=$(aws ec2 describe-security-groups \
  --group-ids "${SG_ID}" \
  --query "length(SecurityGroups[0].IpPermissions)" --output text)
if [[ "${INGRESS_COUNT}" == "0" ]]; then
  echo "[OK] インバウンドルール: 空（インバウンド拒否）"
else
  echo "[NG] インバウンドルールが存在します: ${INGRESS_COUNT} 件（期待値: 0）"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
