#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# EC2インスタンス設定の検証
# - インスタンスが running 状態であること
# - 正しいキーペアが設定されていること
# - 正しいインスタンスタイプであること（t3.micro）
# - パブリックIPが割り当てられていること
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
  echo "前処理: EC2インスタンス [${EC2_SSH_INSTANCE_NAME}] を削除"
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
# テスト後処理: EC2インスタンス設定検証
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# EC2インスタンス設定検証"

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${EC2_SSH_INSTANCE_NAME}" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "None")

if [[ "${INSTANCE_ID}" != "None" && -n "${INSTANCE_ID}" ]]; then
  echo "[OK] EC2インスタンス [${EC2_SSH_INSTANCE_NAME}] (${INSTANCE_ID}) が running 状態です"
else
  echo "[NG] EC2インスタンス [${EC2_SSH_INSTANCE_NAME}] が running 状態ではありません"
fi

INSTANCE_TYPE=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${EC2_SSH_INSTANCE_NAME}" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceType" --output text 2>/dev/null || echo "")

if [[ "${INSTANCE_TYPE}" == "t3.micro" ]]; then
  echo "[OK] インスタンスタイプ: ${INSTANCE_TYPE}"
else
  echo "[NG] インスタンスタイプが不正: ${INSTANCE_TYPE}（期待値: t3.micro）"
fi

KEY_NAME=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${EC2_SSH_INSTANCE_NAME}" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].KeyName" --output text 2>/dev/null || echo "")

if [[ "${KEY_NAME}" == "ts-010-keypair" ]]; then
  echo "[OK] キーペア: ${KEY_NAME}"
else
  echo "[NG] キーペアが不正: ${KEY_NAME}（期待値: ts-010-keypair）"
fi

PUBLIC_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${EC2_SSH_INSTANCE_NAME}" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text 2>/dev/null || echo "")

if [[ -n "${PUBLIC_IP}" && "${PUBLIC_IP}" != "None" ]]; then
  echo "[OK] パブリックIP: ${PUBLIC_IP}"
else
  echo "[NG] パブリックIPが割り当てられていません"
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
