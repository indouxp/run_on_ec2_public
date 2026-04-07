#!/bin/bash
#============================================================================
# スクリプト名 : get_log_groups.sh
# 説明         : AWS CloudWatch Logsのロググループ一覧を取得する
# 使用方法     : ./get_log_groups.sh [-p profile] [-r region] [-o output_file]
# 前提条件     : AWS CLIがインストール・設定済みであること
#============================================================================

#--- 変数定義 ---
AWS_PROFILE=""            # 使用するAWSプロファイル名
AWS_REGION=""             # 対象リージョン
OUTPUT_FILE=""            # 出力先ファイルパス（未指定時は標準出力）
NEXT_TOKEN=""             # ページネーション用トークン
LOG_GROUP_COUNT=0         # 取得したロググループの総数

#============================================================================
# 関数名 : usage
# 説明   : 使用方法を表示して終了する
# 引数   : なし
#============================================================================
usage() {
    echo "使用方法: $0 [-p profile] [-r region] [-o output_file]"
    echo ""
    echo "オプション:"
    echo "  -p profile      AWSプロファイル名（デフォルト: AWS CLI設定に従う）"
    echo "  -r region       AWSリージョン（デフォルト: AWS CLI設定に従う）"
    echo "  -o output_file  出力先ファイル（デフォルト: 標準出力）"
    echo "  -h              このヘルプを表示"
    exit 1
}

#============================================================================
# 関数名 : build_aws_cmd
# 説明   : AWS CLIコマンドの共通オプション部分を組み立てる
# 引数   : なし
# 戻り値 : AWS CLIの共通オプション文字列を標準出力に返す
#============================================================================
build_aws_cmd() {
    local cmd="aws logs describe-log-groups --output json"  # 基本コマンド（jq処理のためJSON固定）

    # プロファイル指定がある場合、オプションを追加
    if [ -n "${AWS_PROFILE}" ]; then
        cmd="${cmd} --profile ${AWS_PROFILE}"
    fi

    # リージョン指定がある場合、オプションを追加
    if [ -n "${AWS_REGION}" ]; then
        cmd="${cmd} --region ${AWS_REGION}"
    fi

    echo "${cmd}"
}

#============================================================================
# 関数名 : format_bytes
# 説明   : バイト数を人間が読みやすい単位（KB/MB/GB/TB）に変換する
# 引数   : $1 - bytes : 変換対象のバイト数
#============================================================================
format_bytes() {
    local bytes=$1  # 変換対象のバイト数

    if [ "${bytes}" -ge 1099511627776 ] 2>/dev/null; then
        echo "$(awk "BEGIN {printf \"%.2f TB\", ${bytes}/1099511627776}")"
    elif [ "${bytes}" -ge 1073741824 ] 2>/dev/null; then
        echo "$(awk "BEGIN {printf \"%.2f GB\", ${bytes}/1073741824}")"
    elif [ "${bytes}" -ge 1048576 ] 2>/dev/null; then
        echo "$(awk "BEGIN {printf \"%.2f MB\", ${bytes}/1048576}")"
    elif [ "${bytes}" -ge 1024 ] 2>/dev/null; then
        echo "$(awk "BEGIN {printf \"%.2f KB\", ${bytes}/1024}")"
    else
        echo "${bytes} B"
    fi
}

#============================================================================
# 関数名 : format_epoch_ms
# 説明   : エポックミリ秒をJST日時文字列に変換する
# 引数   : $1 - epoch_ms : エポックミリ秒
#============================================================================
format_epoch_ms() {
    local epoch_ms=$1   # エポックミリ秒
    local epoch_sec     # エポック秒（ミリ秒を秒に変換）

    epoch_sec=$((epoch_ms / 1000))
    date -d "@${epoch_sec}" '+%Y-%m-%d %H:%M:%S JST' 2>/dev/null || \
    date -r "${epoch_sec}" '+%Y-%m-%d %H:%M:%S JST' 2>/dev/null || \
    echo "${epoch_ms}"
}

#============================================================================
# 関数名 : fetch_log_groups
# 説明   : ロググループ一覧をページネーション対応で全件取得し表示する
# 引数   : なし
#============================================================================
fetch_log_groups() {
    local base_cmd        # AWS CLI基本コマンド
    local result          # APIレスポンス（JSON）
    local page_count=0    # 取得ページ数

    base_cmd=$(build_aws_cmd)

    # ヘッダー出力
    printf "%-60s %-20s %-15s %s\n" \
        "ロググループ名" "保持期間(日)" "サイズ" "作成日時"
    printf "%0.s-" {1..120}
    echo ""

    # ページネーションループ（全件取得するまで繰り返す）
    while true; do
        page_count=$((page_count + 1))

        # APIコール（トークンがある場合は付与）
        if [ -n "${NEXT_TOKEN}" ]; then
            result=$(${base_cmd} --starting-token "${NEXT_TOKEN}" 2>&1)
        else
            result=$(${base_cmd} 2>&1)
        fi

        # エラーチェック
        if [ $? -ne 0 ]; then
            echo "エラー: AWS API呼び出しに失敗しました" >&2
            echo "${result}" >&2
            return 1
        fi

        # 取得件数を加算
        local count
        count=$(echo "${result}" | jq '.logGroups | length')
        LOG_GROUP_COUNT=$((LOG_GROUP_COUNT + count))

        # 各ロググループの情報を整形して出力
        echo "${result}" | jq -r '.logGroups[] | [
            .logGroupName,
            (.retentionInDays // "無期限"),
            (.storedBytes // 0),
            (.creationTime // 0)
        ] | @tsv' | while IFS=$'\t' read -r name retention bytes creation; do
            local size_str       # 人間が読みやすいサイズ文字列
            local date_str       # フォーマット済み日時文字列

            size_str=$(format_bytes "${bytes}")
            date_str=$(format_epoch_ms "${creation}")

            printf "%-60s %-20s %-15s %s\n" \
                "${name}" "${retention}" "${size_str}" "${date_str}"
        done

        # 次ページのトークンを確認
        NEXT_TOKEN=$(echo "${result}" | jq -r '.nextToken // empty')

        # トークンがなければ全件取得完了
        if [ -z "${NEXT_TOKEN}" ]; then
            break
        fi
    done

    echo ""
    echo "=========================================="
    echo "取得ロググループ総数: ${LOG_GROUP_COUNT} 件"
    echo "=========================================="
}

#============================================================================
# メイン処理
#============================================================================

# オプション解析
while getopts "p:r:o:h" opt; do
    case ${opt} in
        p) AWS_PROFILE="${OPTARG}" ;;  # プロファイル名を設定
        r) AWS_REGION="${OPTARG}" ;;   # リージョンを設定
        o) OUTPUT_FILE="${OPTARG}" ;;  # 出力ファイルを設定
        h) usage ;;                    # ヘルプ表示
        *) usage ;;                    # 不正オプション時はヘルプ表示
    esac
done

# AWS CLIの存在確認
if ! command -v aws &>/dev/null; then
    echo "エラー: AWS CLIがインストールされていません" >&2
    exit 1
fi

# jqの存在確認
if ! command -v jq &>/dev/null; then
    echo "エラー: jqがインストールされていません" >&2
    exit 1
fi

echo "CloudWatch Logs ロググループ一覧取得を開始します..."
echo ""

# 出力先に応じて実行
if [ -n "${OUTPUT_FILE}" ]; then
    fetch_log_groups > "${OUTPUT_FILE}"
    echo "結果をファイルに出力しました: ${OUTPUT_FILE}"
else
    fetch_log_groups
fi

exit 0
