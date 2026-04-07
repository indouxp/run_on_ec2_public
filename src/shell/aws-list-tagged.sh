#!/bin/bash
################################################################################
# スクリプト名 : aws-list-tagged.sh
# 概要         : 指定タグ（Key=Value）を持つ全 AWS リソースを ARN 一覧で表示する
#                Resource Groups Tagging API を使用してリージョン内を横断検索する
#                リソース種別ごとにグループ化して出力する
# 使用方法     : aws-list-tagged.sh [KEY=VALUE]
#                  例: aws-list-tagged.sh PRJ_NAME=ts-010
#                引数省略時はタグキーと値を対話的に入力する
# 注意         : tag:GetResources 権限が必要なため AWS_PROFILE=ts-usr-admin で実行すること
#                  例: AWS_PROFILE=ts-usr-admin aws-list-tagged.sh PRJ_NAME=ts-010
# Created      : 2026-03-26
# Last updated : 2026-03-26 17:00:00
# Author       : Tsystem
# 更新履歴     :
#    2026-03-26: 初版
################################################################################
set -uo pipefail

readonly SCRIPT_NAME=$(basename "$0")  # スクリプト自身のファイル名（エラーメッセージ用）

TAG_KEY=""    # 検索するタグキー（例: PRJ_NAME）
TAG_VALUE=""  # 検索するタグ値（例: ts-010）

# ------------------------------------------------------------------------------
# 関数名   : usage
# 概要     : 使い方を標準エラーに出力して終了する
# 引数     : なし
# 戻り値   : なし（exit 1 で終了）
# ------------------------------------------------------------------------------
usage() {
  echo "Usage: ${SCRIPT_NAME} [KEY=VALUE]" >&2
  echo "  例: ${SCRIPT_NAME} PRJ_NAME=ts-010" >&2
  exit 1
}

# ------------------------------------------------------------------------------
# 関数名   : log_error
# 概要     : エラーメッセージを標準エラー出力に書き出す
# 引数     : $1 - エラーメッセージ文字列
# 戻り値   : なし
# ------------------------------------------------------------------------------
log_error() {
  local message="$1"  # エラーメッセージ
  echo "[ERROR] ${message}" >&2
}

# ------------------------------------------------------------------------------
# 関数名   : parse_tag_arg
# 概要     : "KEY=VALUE" 形式の引数を解析して TAG_KEY / TAG_VALUE に設定する
# 引数     : $1 - "KEY=VALUE" 形式の文字列
# 戻り値   : なし
# ------------------------------------------------------------------------------
parse_tag_arg() {
  local arg="$1"  # 解析対象の引数文字列

  # = が含まれていない場合はフォーマットエラー
  if [[ "$arg" != *"="* ]]; then
    log_error "引数の形式が不正です。KEY=VALUE 形式で指定してください。"
    usage
  fi

  TAG_KEY="${arg%%=*}"   # = より前の部分をキーとして取得
  TAG_VALUE="${arg#*=}"  # = より後の部分を値として取得

  if [[ -z "$TAG_KEY" || -z "$TAG_VALUE" ]]; then
    log_error "タグキーまたは値が空です。"
    usage
  fi
}

# ------------------------------------------------------------------------------
# 関数名   : prompt_tag_input
# 概要     : タグキーと値を対話的に入力させ TAG_KEY / TAG_VALUE に設定する
# 引数     : なし
# 戻り値   : なし
# ------------------------------------------------------------------------------
prompt_tag_input() {
  echo "検索するタグを入力してください。"
  printf "タグキー (例: PRJ_NAME): "
  read -r TAG_KEY
  printf "タグ値   (例: ts-010) : "
  read -r TAG_VALUE

  if [[ -z "$TAG_KEY" || -z "$TAG_VALUE" ]]; then
    log_error "タグキーまたは値が空です。"
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# 関数名   : list_tagged_resources
# 概要     : Resource Groups Tagging API でタグ検索し、サービス別に ARN を表示する
# 引数     : $1 - タグキー / $2 - タグ値
# 戻り値   : なし
# ------------------------------------------------------------------------------
list_tagged_resources() {
  local tag_key="$1"    # 検索するタグキー
  local tag_value="$2"  # 検索するタグ値

  echo "============================================================"
  echo " タグ検索: ${tag_key}=${tag_value}"
  echo "============================================================"

  # Resource Groups Tagging API でリソースの ARN 一覧を取得
  local arns
  arns=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=${tag_key},Values=${tag_value}" \
    --query 'ResourceTagMappingList[*].ResourceARN' \
    --output text 2>&1) || {
    log_error "リソース取得に失敗しました: ${arns}"
    exit 1
  }

  # 結果が空の場合（None または空文字）
  if [[ -z "$arns" || "$arns" == "None" ]]; then
    echo "該当するリソースは見つかりませんでした。"
    exit 0
  fi

  local count=0         # リソース合計数カウンター
  local prev_service="" # 直前のサービス名（グループヘッダー出力の判定用）

  # ARN をサービス別にグループ化して表示
  while IFS= read -r arn; do
    [[ -z "$arn" ]] && continue

    # ARN からサービス名を抽出（arn:aws:SERVICE:REGION:ACCOUNT:...）
    local service
    service=$(echo "$arn" | cut -d: -f3)

    # サービスが切り替わったらグループヘッダーを出力
    if [[ "$service" != "$prev_service" ]]; then
      echo ""
      echo "[ ${service} ]"
      prev_service="$service"
    fi

    echo "  ${arn}"
    count=$((count + 1))
  done <<< "$(echo "$arns" | tr '\t' '\n' | sort)"

  echo ""
  echo "------------------------------------------------------------"
  printf " 合計: %d リソース\n" "$count"
  echo "------------------------------------------------------------"
}

################################################################################
# メイン処理
################################################################################

# 引数の数に応じてタグキー・値を取得
if [[ $# -eq 0 ]]; then
  # 引数なし → 対話的に入力
  prompt_tag_input
elif [[ $# -eq 1 ]]; then
  # 引数あり → KEY=VALUE 形式を解析
  parse_tag_arg "$1"
else
  # 引数が多すぎる場合
  log_error "引数が多すぎます。"
  usage
fi

# リソース検索・表示
list_tagged_resources "$TAG_KEY" "$TAG_VALUE"

exit 0
