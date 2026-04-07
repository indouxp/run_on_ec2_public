#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 作成されたロールのポリシー内容検証
# mk-role-lambda-010.sh 実行後、以下を確認する
# - 管理ポリシー AWSLambdaBasicExecutionRole がアタッチされていること
# - インラインポリシーに必須アクションが含まれていること
#
# Last updated: 2026-03-11 23:20:00
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
# テスト（mk-role-lambda-010.sh 実行）
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
echo "# ポリシー内容検証: ${IAM_ROLE_LAMBDA_NAME}"

# 管理ポリシーのアタッチ確認
readonly MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
ATTACHED=$(aws iam list-attached-role-policies \
  --role-name "${IAM_ROLE_LAMBDA_NAME}" \
  --query "AttachedPolicies[?PolicyArn=='${MANAGED_POLICY_ARN}'].PolicyArn" \
  --output text)
if [[ -n "${ATTACHED}" ]]; then
  echo "[OK] 管理ポリシー AWSLambdaBasicExecutionRole がアタッチされています"
else
  echo "[NG] 管理ポリシー AWSLambdaBasicExecutionRole がアタッチされていません"
  exit 1
fi

# インラインポリシーの内容確認
POLICY_FILE="${TARGET_SCRIPT}.src/policy-check.json"
aws iam get-role-policy \
  --role-name "${IAM_ROLE_LAMBDA_NAME}" \
  --policy-name "${IAM_POLICY_LAMBDA_NAME}" \
  --query 'PolicyDocument' \
  --output json > "${POLICY_FILE}"

python3 - "${POLICY_FILE}" << 'EOF'
import json, sys

with open(sys.argv[1]) as f:
    policy = json.load(f)

# ポリシー内の全アクションをフラット化
actions = []
for stmt in policy["Statement"]:
    a = stmt["Action"]
    actions.extend(a if isinstance(a, list) else [a])

# 検証対象
required = [
    "s3:GetObject",       # 入力バケット読み取り
    "s3:PutObject",       # 出力バケット書き込み
    "ec2:RunInstances",   # EC2起動
    "iam:PassRole",       # EC2ロールのPassRole
    "sns:Publish",        # SNS通知
    "ses:SendEmail",      # SES通知
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

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
