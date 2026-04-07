#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 作成されたロールのポリシー内容検証
# mk-role-ec2-010.sh 実行後、以下を確認する
# - 管理ポリシー CloudWatchAgentServerPolicy がアタッチされていること
# - インラインポリシーに必須アクションが含まれていること
# - インスタンスプロファイルが作成されロールと関連付けられていること
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

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-role-ec2-010.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（ポリシー内容検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# ポリシー内容検証: ${IAM_ROLE_EC2_NAME}"

# 管理ポリシーのアタッチ確認
readonly MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
ATTACHED=$(aws iam list-attached-role-policies \
  --role-name "${IAM_ROLE_EC2_NAME}" \
  --query "AttachedPolicies[?PolicyArn=='${MANAGED_POLICY_ARN}'].PolicyArn" \
  --output text)
if [[ -n "${ATTACHED}" ]]; then
  echo "[OK] 管理ポリシー CloudWatchAgentServerPolicy がアタッチされています"
else
  echo "[NG] 管理ポリシー CloudWatchAgentServerPolicy がアタッチされていません"
  exit 1
fi

# インラインポリシーの内容確認
POLICY_FILE="${TARGET_SCRIPT}.src/policy-check.json"
aws iam get-role-policy \
  --role-name "${IAM_ROLE_EC2_NAME}" \
  --policy-name "${IAM_POLICY_EC2_NAME}" \
  --query 'PolicyDocument' \
  --output json > "${POLICY_FILE}"

python3 - "${POLICY_FILE}" << 'EOF'
import json, sys

with open(sys.argv[1]) as f:
    policy = json.load(f)

actions = []
for stmt in policy["Statement"]:
    a = stmt["Action"]
    actions.extend(a if isinstance(a, list) else [a])

required = [
    "s3:GetObject",           # 入力バケット読み取り
    "s3:PutObject",           # 出力バケット書き込み
    "sns:Publish",            # SNS通知
    "ses:SendEmail",          # SES通知
    "logs:CreateLogGroup",    # CloudWatch Logs
    "logs:PutLogEvents",      # CloudWatch Logs
    "ec2:TerminateInstances", # 自己削除
]

missing = [a for a in required if a not in actions]

if missing:
    print("[NG] 以下の必須アクションが不足しています:")
    for a in missing:
        print(f"     - {a}")
    sys.exit(1)

print("[OK] インラインポリシーの必須アクションがすべて存在します")
for a in required:
    print(f"     {a}")
EOF

# インスタンスプロファイルの確認
PROFILE=$(aws iam get-instance-profile \
  --instance-profile-name "${IAM_ROLE_EC2_NAME}" \
  --query 'InstanceProfile.Roles[0].RoleName' --output text 2>/dev/null || echo "")
if [[ "${PROFILE}" == "${IAM_ROLE_EC2_NAME}" ]]; then
  echo "[OK] インスタンスプロファイル [${IAM_ROLE_EC2_NAME}] にロールが関連付けられています"
else
  echo "[NG] インスタンスプロファイルのロール関連付けが確認できません"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
