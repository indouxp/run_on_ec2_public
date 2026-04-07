#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# ロールが存在する状態から実行、正常処理（削除→再作成）
#
# Last updated: 2026-03-11 23:30:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

cp config.sh.org config.sh
. config.sh

export AWS_PROFILE=ts-usr-admin  # IAMスクリプトのテストは管理者プロファイルで実行

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

# ロールを make_role() が期待する既知の状態に整備する
# （意図しないポリシーが残っていると make_role() 内の delete-role が失敗するため）
ROLE_EXISTS=$(aws iam get-role \
  --role-name "${IAM_ROLE_EC2_NAME}" \
  --query 'Role.RoleName' --output text 2>/dev/null || echo "")
if [[ -n "${ROLE_EXISTS}" ]]; then
  echo "前処理: ロール [${IAM_ROLE_EC2_NAME}] を既知の状態に整備します"

  # インスタンスプロファイルのロール関連付け解除・削除
  aws iam remove-role-from-instance-profile \
    --instance-profile-name "${IAM_ROLE_EC2_NAME}" \
    --role-name "${IAM_ROLE_EC2_NAME}" 2>/dev/null || true
  aws iam delete-instance-profile \
    --instance-profile-name "${IAM_ROLE_EC2_NAME}" 2>/dev/null || true

  # インラインポリシーをすべて削除
  for POLICY in $(aws iam list-role-policies \
      --role-name "${IAM_ROLE_EC2_NAME}" \
      --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "${IAM_ROLE_EC2_NAME}" --policy-name "${POLICY}"
  done

  # アタッチ済み管理ポリシーをすべてデタッチ
  for POLICY_ARN in $(aws iam list-attached-role-policies \
      --role-name "${IAM_ROLE_EC2_NAME}" \
      --query 'AttachedPolicies[*].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "${IAM_ROLE_EC2_NAME}" --policy-arn "${POLICY_ARN}"
  done

  # ロール削除後、make_role() が処理できる既知の状態で再作成
  aws iam delete-role --role-name "${IAM_ROLE_EC2_NAME}"

  # 信頼ポリシー作成・ロール再作成
  cat > "${TARGET_SCRIPT}.src/trust-policy-ec2.json" << 'TRUSTEOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
TRUSTEOF
  aws iam create-role \
    --role-name "${IAM_ROLE_EC2_NAME}" \
    --assume-role-policy-document "file://${TARGET_SCRIPT}.src/trust-policy-ec2.json"
  aws iam attach-role-policy \
    --role-name "${IAM_ROLE_EC2_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
  aws iam put-role-policy \
    --role-name "${IAM_ROLE_EC2_NAME}" \
    --policy-name "${IAM_POLICY_EC2_NAME}" \
    --policy-document '{"Version":"2012-10-17","Statement":[]}'
  echo "前処理: ロール [${IAM_ROLE_EC2_NAME}] を既知の状態で準備しました（スクリプト内で再作成されます）"
else
  echo "前処理: ロール [${IAM_ROLE_EC2_NAME}] は存在しません（スクリプト内で新規作成されます）"
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
# なし
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
