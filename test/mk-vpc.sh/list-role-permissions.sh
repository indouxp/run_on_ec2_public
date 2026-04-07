#!/bin/bash
#===============================================================================
# スクリプト名: list_role_permissions.sh
# 説明:         指定したIAMロールに紐づく全ポリシー（マネージド・インライン）と
#               信頼ポリシー（AssumeRolePolicyDocument）を一括で取得・表示する
# 使い方:       ./list_role_permissions.sh [ロール名]
#               ロール名省略時は aws sts get-caller-identity から自動取得
#               （AssumeRoleしている場合のみ自動取得可能）
# Author: claude
# Last updated: 2026-03-11 16:07:16
#===============================================================================

set -euo pipefail

#--- 色定義（見やすさのため） ---
GREEN="\033[1;32m"   # セクション見出し用
CYAN="\033[1;36m"    # サブ項目用
YELLOW="\033[1;33m"  # 警告・注意用
RESET="\033[0m"      # 色リセット

#===============================================================================
# 関数: print_section
# 説明: セクション見出しを装飾付きで表示する
# 引数: $1 - 表示するセクションタイトル
#===============================================================================
print_section() {
    local title="$1"  # セクションタイトル
    echo ""
    echo -e "${GREEN}========================================${RESET}"
    echo -e "${GREEN}  ${title}${RESET}"
    echo -e "${GREEN}========================================${RESET}"
}

#===============================================================================
# 関数: print_subsection
# 説明: サブセクション見出しを表示する
# 引数: $1 - 表示するサブタイトル
#===============================================================================
print_subsection() {
    local subtitle="$1"  # サブセクションタイトル
    echo ""
    echo -e "${CYAN}--- ${subtitle} ---${RESET}"
}

#===============================================================================
# 関数: get_policy_document
# 説明: マネージドポリシーのARNからポリシー定義(JSON)を取得して表示する
# 引数: $1 - ポリシーARN
#===============================================================================
get_policy_document() {
    local policy_arn="$1"  # 取得対象のポリシーARN

    # ポリシーのデフォルトバージョンIDを取得
    local version_id
    version_id=$(aws iam get-policy \
                     --profile ts-usr-admin \
                     --policy-arn "${policy_arn}" \
                     --query 'Policy.DefaultVersionId' \
                     --output text 2>/dev/null)

    if [[ -z "${version_id}" || "${version_id}" == "None" ]]; then
        echo -e "${YELLOW}    ※ バージョンID取得失敗: ${policy_arn}${RESET}"
        return
    fi

    # ポリシー定義JSONを取得・表示
    echo "    ポリシーARN: ${policy_arn}"
    echo "    バージョン:  ${version_id}"
    aws iam get-policy-version \
        --profile ts-usr-admin \
        --policy-arn "${policy_arn}" \
        --version-id "${version_id}" \
        --query 'PolicyVersion.Document' \
        --output json 2>/dev/null | sed 's/^/    /'
    echo ""
}

#===============================================================================
# 関数: show_trust_policy
# 説明: ロールの信頼ポリシー（AssumeRolePolicyDocument）を表示する
#       誰がこのロールを引き受けられるかを定義する重要な情報
# 引数: $1 - IAMロール名
#===============================================================================
show_trust_policy() {
    local role_name="$1"  # 対象ロール名

    print_section "1. 信頼ポリシー（AssumeRolePolicyDocument）"

    # ロール情報から信頼ポリシーを抽出して表示
    local trust_policy
    trust_policy=$(aws iam get-role \
                       --profile ts-usr-admin \
                       --role-name "${role_name}" \
                       --query 'Role.AssumeRolePolicyDocument' \
                       --output json 2>/dev/null)

    if [[ -z "${trust_policy}" || "${trust_policy}" == "null" ]]; then
        echo "  (取得失敗)"
        return
    fi

    echo "  このロールを引き受け(AssumeRole)可能なエンティティ:"
    echo "${trust_policy}" | sed 's/^/    /'
    echo ""
}

#===============================================================================
# 関数: list_role_managed_policies
# 説明: ロールにアタッチされたマネージドポリシーを一覧・詳細表示する
# 引数: $1 - IAMロール名
#===============================================================================
list_role_managed_policies() {
    local role_name="$1"  # 対象ロール名

    print_section "2. ロールにアタッチされたマネージドポリシー"

    # アタッチされたポリシーARN一覧を取得
    local policy_arns
    policy_arns=$(aws iam list-attached-role-policies \
                      --profile ts-usr-admin \
                      --role-name "${role_name}" \
                      --query 'AttachedPolicies[].PolicyArn' \
                      --output text 2>/dev/null)

    if [[ -z "${policy_arns}" || "${policy_arns}" == "None" ]]; then
        echo "  (なし)"
        return
    fi

    # 各ポリシーの詳細を表示
    for arn in ${policy_arns}; do
        print_subsection "マネージドポリシー"
        get_policy_document "${arn}"
    done
}

#===============================================================================
# 関数: list_role_inline_policies
# 説明: ロールに直接設定されたインラインポリシーを一覧・詳細表示する
# 引数: $1 - IAMロール名
#===============================================================================
list_role_inline_policies() {
    local role_name="$1"  # 対象ロール名

    print_section "3. ロールのインラインポリシー"

    # インラインポリシー名一覧を取得
    local policy_names
    policy_names=$(aws iam list-role-policies \
                       --profile ts-usr-admin \
                       --role-name "${role_name}" \
                       --query 'PolicyNames[]' \
                       --output text 2>/dev/null)

    if [[ -z "${policy_names}" || "${policy_names}" == "None" ]]; then
        echo "  (なし)"
        return
    fi

    # 各インラインポリシーの定義を表示
    for pname in ${policy_names}; do
        print_subsection "インラインポリシー: ${pname}"
        aws iam get-role-policy \
            --profile ts-usr-admin \
            --role-name "${role_name}" \
            --policy-name "${pname}" \
            --query 'PolicyDocument' \
            --output json 2>/dev/null | sed 's/^/    /'
        echo ""
    done
}

#===============================================================================
# 関数: show_permissions_boundary
# 説明: ロールに設定されたPermissions Boundary（権限の上限）を表示する
# 引数: $1 - IAMロール名
#===============================================================================
show_permissions_boundary() {
    local role_name="$1"  # 対象ロール名

    print_section "4. Permissions Boundary（権限の上限）"

    # ロール情報からPermissions Boundaryを取得
    local boundary_arn
    boundary_arn=$(aws iam get-role \
                       --profile ts-usr-admin \
                       --role-name "${role_name}" \
                       --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' \
                       --output text 2>/dev/null)

    if [[ -z "${boundary_arn}" || "${boundary_arn}" == "None" ]]; then
        echo "  (設定なし)"
        return
    fi

    echo "  Permissions Boundary が設定されています:"
    get_policy_document "${boundary_arn}"
}

#===============================================================================
# メイン処理
#===============================================================================

# 対象ロール名の決定（引数 or 自動取得）
TARGET_ROLE="${1:-}"  # コマンドライン引数（省略可）

if [[ -z "${TARGET_ROLE}" ]]; then
    echo "ロール名未指定のため、現在の呼び出し元から自動取得を試みます..."

    # get-caller-identityのARNからロール名を抽出
    CALLER_ARN=$(aws sts get-caller-identity \
                     --query 'Arn' --output text 2>/dev/null)

    # assumed-role/ロール名/セッション名 の形式からロール名を取得
    if echo "${CALLER_ARN}" | grep -q "assumed-role"; then
        TARGET_ROLE=$(echo "${CALLER_ARN}" | awk -F'/' '{print $(NF-1)}')
    else
        echo -e "${YELLOW}エラー: 現在の呼び出し元はロールではありません${RESET}" >&2
        echo "  ARN: ${CALLER_ARN}" >&2
        echo "" >&2
        echo "使い方: $0 <IAMロール名>" >&2
        exit 1
    fi

    if [[ -z "${TARGET_ROLE}" ]]; then
        echo -e "${YELLOW}エラー: ロール名を取得できませんでした${RESET}" >&2
        echo "使い方: $0 <IAMロール名>" >&2
        exit 1
    fi
fi

echo ""
echo "============================================================"
echo "  対象ロール: ${TARGET_ROLE}"
echo "  実行日時:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# 各カテゴリのポリシーを順番に取得・表示
show_trust_policy "${TARGET_ROLE}"
list_role_managed_policies "${TARGET_ROLE}"
list_role_inline_policies "${TARGET_ROLE}"
show_permissions_boundary "${TARGET_ROLE}"

print_section "完了"
echo "  上記がロール [${TARGET_ROLE}] に紐づく全ポリシーです。"
echo "  ※ SCPやリソースベースポリシーは別途確認が必要です。"
echo ""
