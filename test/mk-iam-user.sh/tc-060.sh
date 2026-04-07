#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 作成されたユーザーのポリシー内容検証
# mk-iam-user.sh 実行後、インラインポリシーに必須アクション・リソースが
# 含まれていることを確認する
#
# Last updated: 2026-03-11 22:30:00
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
# テスト（mk-iam-user.sh 実行）
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
echo "# ポリシー内容検証: ${IAM_USER_NAME}-policy"

# インラインポリシーをファイルに取得
POLICY_FILE="${TARGET_SCRIPT}.src/policy-check.json"
aws iam get-user-policy \
  --user-name "${IAM_USER_NAME}" \
  --policy-name "${IAM_USER_NAME}-policy" \
  --query 'PolicyDocument' \
  --output json > "${POLICY_FILE}"

# 必須アクション・リソースの存在確認
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
python3 - "${POLICY_FILE}" "${AWS_ACCOUNT_ID}" "${IAM_ROLE_BUILD_NAME}" "${IAM_ROLE_EXEC_NAME}" << 'EOF'
import json, sys

with open(sys.argv[1]) as f:
    policy = json.load(f)

account_id   = sys.argv[2]
role_build   = sys.argv[3]
role_exec    = sys.argv[4]

# ポリシー内の全アクション・リソースをステートメント別に確認
errors = []
assume_role_resources = []
log_actions = []

for stmt in policy["Statement"]:
    actions = stmt["Action"]
    if isinstance(actions, str):
        actions = [actions]
    resources = stmt.get("Resource", [])
    if isinstance(resources, str):
        resources = [resources]

    if "sts:AssumeRole" in actions:
        assume_role_resources.extend(resources)
    for a in actions:
        if a.startswith("logs:"):
            log_actions.append(a)

# AssumeRole 対象ロールの確認
required_roles = [
    f"arn:aws:iam::{account_id}:role/{role_build}",
    f"arn:aws:iam::{account_id}:role/{role_exec}",
]
for r in required_roles:
    if r not in assume_role_resources:
        errors.append(f"sts:AssumeRole のリソースに {r} がありません")

# logs アクションの確認
required_logs = [
    "logs:DescribeLogGroups",
    "logs:DescribeLogStreams",
    "logs:GetLogEvents",
    "logs:FilterLogEvents",
]
for a in required_logs:
    if a not in log_actions:
        errors.append(f"必須アクション {a} がありません")

if errors:
    print("[NG] ポリシー検証失敗:")
    for e in errors:
        print(f"     - {e}")
    sys.exit(1)

print("[OK] ポリシー内容が正しく設定されています")
print(f"     sts:AssumeRole -> {role_build}, {role_exec}")
for a in required_logs:
    print(f"     {a}")
EOF

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
