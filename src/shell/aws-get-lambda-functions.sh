#!/bin/bash
#============================================================================
# スクリプト名 : get_lambda_functions.sh
# 説明         : AWS Lambdaに登録されている関数一覧を取得・表示する
# 使用方法     : ./get_lambda_functions.sh [-p profile] [-r region] [-o output_file]
# 前提条件     : AWS CLI, jq がインストール・設定済みであること
#============================================================================

#--- 変数定義 ---
AWS_PROFILE=""            # 使用するAWSプロファイル名
AWS_REGION=""             # 対象リージョン
OUTPUT_FILE=""            # 出力先ファイルパス（未指定時は標準出力）
NEXT_MARKER=""            # ページネーション用マーカー
FUNC_COUNT=0              # 取得したLambda関数の総数

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
    local cmd="aws lambda list-functions --output json"  # 基本コマンド（jq処理のためJSON固定）

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
# 説明   : バイト数を人間が読みやすい単位（KB/MB/GB）に変換する
# 引数   : $1 - bytes : 変換対象のバイト数
#============================================================================
format_bytes() {
    local bytes=$1  # 変換対象のバイト数

    if [ "${bytes}" -ge 1073741824 ] 2>/dev/null; then
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
# 関数名 : format_epoch_str
# 説明   : ISO 8601形式の日時文字列をJST表示に変換する
# 引数   : $1 - datetime_str : ISO 8601形式の日時文字列
#============================================================================
format_epoch_str() {
    local datetime_str=$1  # ISO 8601形式の日時文字列

    # dateコマンドで変換（Linux / macOS対応）
    date -d "${datetime_str}" '+%Y-%m-%d %H:%M:%S JST' 2>/dev/null || \
    date -jf '%Y-%m-%dT%H:%M:%S' "${datetime_str%%.*}" '+%Y-%m-%d %H:%M:%S JST' 2>/dev/null || \
    echo "${datetime_str}"
}

#============================================================================
# 関数名 : fetch_lambda_functions
# 説明   : Lambda関数一覧をページネーション対応で全件取得し表示する
# 引数   : なし
#============================================================================
fetch_lambda_functions() {
    local base_cmd        # AWS CLI基本コマンド
    local result          # APIレスポンス（JSON）
    local page_count=0    # 取得ページ数

    base_cmd=$(build_aws_cmd)

    # ヘッダー出力
    printf "%-4s %-45s %-12s %-10s %-8s %-12s %s\n" \
        "No." "関数名" "ランタイム" "メモリ(MB)" "タイムアウト" "コードサイズ" "最終更新日時"
    printf "%0.s-" {1..140}
    echo ""

    # ページネーションループ（全件取得するまで繰り返す）
    while true; do
        page_count=$((page_count + 1))

        # APIコール（マーカーがある場合は付与）
        if [ -n "${NEXT_MARKER}" ]; then
            result=$(${base_cmd} --marker "${NEXT_MARKER}" 2>&1)
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
        count=$(echo "${result}" | jq '.Functions | length')

        # 各Lambda関数の情報を整形して出力
        echo "${result}" | jq -r '.Functions[] | [
            .FunctionName,
            (.Runtime // "コンテナ"),
            (.MemorySize // 0),
            (.Timeout // 0),
            (.CodeSize // 0),
            (.LastModified // "-"),
            (.Description // "")
        ] | @tsv' | sort | while IFS=$'\t' read -r name runtime memory timeout codesize lastmod description; do
            FUNC_COUNT=$((FUNC_COUNT + 1))

            local size_str       # 人間が読みやすいコードサイズ文字列
            local date_str       # フォーマット済み日時文字列
            local timeout_str    # タイムアウト表示文字列

            size_str=$(format_bytes "${codesize}")
            date_str=$(format_epoch_str "${lastmod}")
            timeout_str="${timeout}秒"

            printf "%-4s %-45s %-12s %-10s %-12s %-12s %s\n" \
                "${FUNC_COUNT}" "${name}" "${runtime}" "${memory}" "${timeout_str}" "${size_str}" "${date_str}"

            # 説明がある場合はインデント付きで表示
            if [ -n "${description}" ] && [ "${description}" != "" ]; then
                printf "     └─ 説明: %s\n" "${description}"
            fi
        done

        # サブシェル内のカウントを反映するため、外側でも加算
        FUNC_COUNT=$((FUNC_COUNT + count))

        # 次ページのマーカーを確認
        NEXT_MARKER=$(echo "${result}" | jq -r '.NextMarker // empty')

        # マーカーがなければ全件取得完了
        if [ -z "${NEXT_MARKER}" ]; then
            break
        fi
    done

    echo ""
    echo "=========================================="
    echo "登録Lambda関数 総数: ${FUNC_COUNT} 件"
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

echo "Lambda関数一覧の取得を開始します..."
echo ""

# 出力先に応じて実行
if [ -n "${OUTPUT_FILE}" ]; then
    fetch_lambda_functions > "${OUTPUT_FILE}"
    echo "結果をファイルに出力しました: ${OUTPUT_FILE}"
else
    fetch_lambda_functions
fi

exit 0
