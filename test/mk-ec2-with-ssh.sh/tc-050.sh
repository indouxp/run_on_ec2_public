#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# EC2インスタンスが存在しない状態から実行、正常処理（新規作成）
#
# 前提: 以下のリソースが存在すること
#   - ts-010-vpc-010 (VPC)
#   - ts-010-subnet-010 (Subnet)
#   - ts-010-sg-010 (SG)
#   - ts-010-keypair (Keypair)
#   - ts-010-role-ec2-010 (IAM Instance Profile)
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
# テスト前処理: EC2インスタンスを削除（クリーンな状態から）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

EXISTING=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${EC2_SSH_INSTANCE_NAME}" \
            "Name=instance-state-name,Values=running,stopped,pending" \
  --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "None")

if [[ "${EXISTING}" != "None" && -n "${EXISTING}" ]]; then
  aws ec2 terminate-instances --instance-ids "${EXISTING}"
  aws ec2 wait instance-terminated --instance-ids "${EXISTING}"
  echo "前処理: EC2インスタンス [${EC2_SSH_INSTANCE_NAME}] (${EXISTING}) を削除しました"
else
  echo "前処理: EC2インスタンス [${EC2_SSH_INSTANCE_NAME}] は存在しません"
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
