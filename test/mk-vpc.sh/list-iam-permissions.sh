#!/bin/bash
#===============================================================================
# スクリプト名: list_iam_permissions.sh
# 説明:         指定したIAMユーザーに紐づく全ポリシー（直接アタッチ・インライン・
#               グループ経由）を一括で取得・表示するスクリプト
# 使い方:       ./list_iam_permissions.sh [ユーザー名]
#               ユーザー名省略時は aws sts get-caller-identity から自動取得
#
# Author: claude
# Last updated: 2026-03-11 16:07:14
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
                     --output text 2>/dev/null) \

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
# 関数: list_user_direct_policies
# 説明: ユーザーに直接アタッチされたマネージドポリシーを一覧・詳細表示する
# 引数: $1 - IAMユーザー名
#===============================================================================
list_user_direct_policies() {
    local user_name="$1"  # 対象ユーザー名

    print_section "1. ユーザー直接アタッチ - マネージドポリシー"

    # アタッチされたポリシーARN一覧を取得
    local policy_arns
    policy_arns=$(aws iam list-attached-user-policies \
                      --profile ts-usr-admin \
                      --user-name "${user_name}" \
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
# 関数: list_user_inline_policies
# 説明: ユーザーに直接設定されたインラインポリシーを一覧・詳細表示する
# 引数: $1 - IAMユーザー名
#===============================================================================
list_user_inline_policies() {
    local user_name="$1"  # 対象ユーザー名

    print_section "2. ユーザー直接アタッチ - インラインポリシー"

    # インラインポリシー名一覧を取得
    local policy_names
    policy_names=$(aws iam list-user-policies \
                       --profile ts-usr-admin \
                       --user-name "${user_name}" \
                       --query 'PolicyNames[]' \
                       --output text 2>/dev/null)

    if [[ -z "${policy_names}" || "${policy_names}" == "None" ]]; then
        echo "  (なし)"
        return
    fi

    # 各インラインポリシーの定義を表示
    for pname in ${policy_names}; do
        print_subsection "インラインポリシー: ${pname}"
        aws iam get-user-policy \
            --profile ts-usr-admin \
            --user-name "${user_name}" \
            --policy-name "${pname}" \
            --query 'PolicyDocument' \
            --output json 2>/dev/null | sed 's/^/    /'
        echo ""
    done
}

#===============================================================================
# 関数: list_group_policies
# 説明: ユーザーが所属する全グループのポリシー（マネージド＋インライン）を表示する
# 引数: $1 - IAMユーザー名
#===============================================================================
list_group_policies() {
    local user_name="$1"  # 対象ユーザー名

    print_section "3. グループ経由のポリシー"

    # ユーザーが所属するグループ名一覧を取得
    local group_names
    group_names=$(aws iam list-groups-for-user \
                      --profile ts-usr-admin \
                      --user-name "${user_name}" \
                      --query 'Groups[].GroupName' \
                      --output text 2>/dev/null)

    if [[ -z "${group_names}" || "${group_names}" == "None" ]]; then
        echo "  (所属グループなし)"
        return
    fi

    # 各グループについてポリシーを列挙
    for group in ${group_names}; do
        echo ""
        echo -e "${CYAN}  ▶ グループ: ${group}${RESET}"

        #--- グループのマネージドポリシー ---
        print_subsection "  [${group}] マネージドポリシー"
        local g_policy_arns
        g_policy_arns=$(aws iam list-attached-group-policies \
                            --profile ts-usr-admin \
                            --group-name "${group}" \
                            --query 'AttachedPolicies[].PolicyArn' \
                            --output text 2>/dev/null)

        if [[ -z "${g_policy_arns}" || "${g_policy_arns}" == "None" ]]; then
            echo "    (なし)"
        else
            for arn in ${g_policy_arns}; do
                get_policy_document "${arn}"
            done
        fi

        #--- グループのインラインポリシー ---
        print_subsection "  [${group}] インラインポリシー"
        local g_inline_names
        g_inline_names=$(aws iam list-group-policies \
                             --profile ts-usr-admin \
                             --group-name "${group}" \
                             --query 'PolicyNames[]' \
                             --output text 2>/dev/null)

        if [[ -z "${g_inline_names}" || "${g_inline_names}" == "None" ]]; then
            echo "    (なし)"
        else
            for pname in ${g_inline_names}; do
                echo "    ポリシー名: ${pname}"
                aws iam get-group-policy \
                    --profile ts-usr-admin \
                    --group-name "${group}" \
                    --policy-name "${pname}" \
                    --query 'PolicyDocument' \
                    --output json 2>/dev/null | sed 's/^/    /'
                echo ""
            done
        fi
    done
}

#===============================================================================
# メイン処理
#===============================================================================

# 対象ユーザー名の決定（引数 or 自動取得）
TARGET_USER="${1:-}"  # コマンドライン引数（省略可）

if [[ -z "${TARGET_USER}" ]]; then
    echo "ユーザー名未指定のため、現在の呼び出し元から自動取得します..."
    # get-caller-identityのARNからユーザー名を抽出
    CALLER_ARN=$(aws sts get-caller-identity \
                     --query 'Arn' --output text 2>/dev/null)
    TARGET_USER=$(echo "${CALLER_ARN}" | awk -F'/' '{print $NF}')

    if [[ -z "${TARGET_USER}" ]]; then
        echo -e "${YELLOW}エラー: ユーザー名を取得できませんでした${RESET}" >&2
        echo "使い方: $0 <IAMユーザー名>" >&2
        exit 1
    fi
fi

echo ""
echo "============================================================"
echo "  対象ユーザー: ${TARGET_USER}"
echo "  実行日時:     $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# 各カテゴリのポリシーを順番に取得・表示
list_user_direct_policies "${TARGET_USER}"
list_user_inline_policies "${TARGET_USER}"
list_group_policies "${TARGET_USER}"

print_section "完了"
echo "  上記がユーザー [${TARGET_USER}] に紐づく全ポリシーです。"
echo "  ※ SCPやPermissions Boundaryは別途確認が必要です。"
echo ""
