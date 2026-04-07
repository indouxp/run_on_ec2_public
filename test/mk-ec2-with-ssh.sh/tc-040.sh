#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# EC2インスタンスが存在する状態から実行、正常処理（終了・再作成）
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
# テスト前処理: 必要リソース確認 + EC2インスタンスが存在することを確認
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# 前提条件チェック
. config.sh
for CHECK_NAME in "${VPC_NAME}" "${SUBNET_NAME}" "${SG_NAME}"; do
  echo "前提条件確認: ${CHECK_NAME}"
done

# キーペア存在確認
if ! aws ec2 describe-key-pairs --key-names "ts-010-keypair" >/dev/null 2>&1; then
  echo "前提条件エラー: キーペア [ts-010-keypair] が存在しません"
  echo "先に mk-keypair.sh を実行してください"
  exit 1
fi
echo "前提条件OK: キーペア [ts-010-keypair] が存在します"

# IAM Instance Profile確認
if ! aws iam get-instance-profile --instance-profile-name "ts-010-role-ec2-010" >/dev/null 2>&1; then
  echo "前提条件エラー: IAM Instance Profile [ts-010-role-ec2-010] が存在しません"
  echo "先に mk-role-ec2-010.sh と mk-lambda.sh を実行してください"
  exit 1
fi
echo "前提条件OK: IAM Instance Profile [ts-010-role-ec2-010] が存在します"

# EC2インスタンスが存在することを確認（なければ作成）
EXISTING=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${EC2_SSH_INSTANCE_NAME}" \
            "Name=instance-state-name,Values=running,stopped,pending" \
  --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "None")

if [[ "${EXISTING}" != "None" && -n "${EXISTING}" ]]; then
  echo "前処理: EC2インスタンス [${EC2_SSH_INSTANCE_NAME}] (${EXISTING}) は既に存在します"
else
  echo "前処理: EC2インスタンス [${EC2_SSH_INSTANCE_NAME}] が存在しないため作成します"
  ./${TARGET_SCRIPT}
  echo "前処理: EC2インスタンス [${EC2_SSH_INSTANCE_NAME}] を作成しました"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log
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
