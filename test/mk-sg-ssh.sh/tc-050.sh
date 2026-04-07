#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# SSHルール（ポート22）が存在しない状態から実行、正常処理（新規追加）
#
# 前提:
#   - mk-vpc.sh により VPC (VPC_NAME) が作成済みであること
#   - mk-sg.sh により SG (SG_NAME) が作成済みであること
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
# テスト前処理: VPC・SGの存在確認 + SSHルールを削除（あれば）
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

# SGの存在確認（前提条件）
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" --output text)
if [[ "${SG_ID}" == "None" || -z "${SG_ID}" ]]; then
  echo "前提条件エラー: SG [${SG_NAME}] が存在しません。mk-sg.sh を先に実行してください。"
  exit 1
fi
echo "前処理: SG [${SG_NAME}] (ID: ${SG_ID}) の存在を確認しました"

# 既存のSSHルール(ポート22)を削除（あれば）
EXISTING_RULES_JSON=$(aws ec2 describe-security-groups --group-ids "${SG_ID}" --output json | \
  jq '[.SecurityGroups[0].IpPermissions[] | select(.FromPort==22 and .ToPort==22 and .IpProtocol=="tcp")]')
if [[ "${EXISTING_RULES_JSON}" != "[]" && -n "${EXISTING_RULES_JSON}" ]]; then
  aws ec2 revoke-security-group-ingress --group-id "${SG_ID}" --ip-permissions "${EXISTING_RULES_JSON}"
  echo "前処理: 既存のSSHルールを削除しました"
else
  echo "前処理: SSHルールは存在しません（削除不要）"
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
