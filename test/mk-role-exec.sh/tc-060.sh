#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 作成されたロールのポリシー内容検証
# mk-role-exec.sh 実行後、インラインポリシーに必須アクション・リソースが
# 含まれていることを確認する
#
# Last updated: 2026-03-11 23:00:00
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
# テスト（mk-role-exec.sh 実行）
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
echo "# ポリシー内容検証: ${IAM_ROLE_EXEC_NAME}-policy"

# インラインポリシーをファイルに取得
POLICY_FILE="${TARGET_SCRIPT}.src/policy-check.json"
aws iam get-role-policy \
  --role-name "${IAM_ROLE_EXEC_NAME}" \
  --policy-name "${IAM_ROLE_EXEC_NAME}-policy" \
  --query 'PolicyDocument' \
  --output json > "${POLICY_FILE}"

# 必須アクション・リソースの存在確認
python3 - "${POLICY_FILE}" << 'EOF'
import json, sys

with open(sys.argv[1]) as f:
    policy = json.load(f)

# ポリシー内の全アクションをフラット化
actions = []
for stmt in policy["Statement"]:
    a = stmt["Action"]
    actions.extend(a if isinstance(a, list) else [a])

# 検証対象（各 Sid の代表アクション）
required = [
    "s3:GetObject",           # S3Access
    "s3:PutObject",           # S3Access
    "ec2:RunInstances",       # EC2Operation
    "ec2:DescribeInstances",  # EC2Operation
    "ec2:TerminateInstances", # EC2SelfTermination
    "iam:PassRole",           # IAMPassRole
    "sns:Publish",            # Notifications
    "logs:CreateLogGroup",    # Logging
    "logs:PutLogEvents",      # Logging
]

missing = [a for a in required if a not in actions]

if missing:
    print("[NG] 以下の必須アクションが不足しています:")
    for a in missing:
        print(f"     - {a}")
    sys.exit(1)

print("[OK] 必須アクションがすべて存在します")
for a in required:
    print(f"     {a}")
EOF

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
