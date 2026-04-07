#!/bin/bash
################################################################################
# 目的  : AWSに登録されているLambdaデプロイパッケージ内の
#         user_data_template.shの内容を確認します
# 概要  : Lambda関数の構成を取得し、コードをダウンロードして展開後、
#         user_data_template.shを表示します
# 作成者: Codex (AI assistant)
# 作成日: 2025-11-20
################################################################################

set -u
set -o pipefail

MY_NAME=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="${SCRIPT_DIR}/${MY_NAME}.log"
WORK_DIR=""
DOWNLOADED_ZIP=""

exec > >(tee -a "$LOG_FILE") 2>&1

################################################################################
# ログ出力の補助関数
################################################################################
log_info() {
  local message="$1"
  printf '[INFO] %s\n' "$message"
}

log_error() {
  local message="$1"
  printf '[ERROR] %s\n' "$message" >&2
}

################################################################################
# シグナル・終了時処理
################################################################################
cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

on_exit() {
  cleanup
}

on_signal() {
  local signal_name="$1"
  log_error "シグナル(${signal_name})を受信したため処理を中断します。"
  exit 1
}

trap on_exit EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

################################################################################
# 依存コマンド確認
################################################################################
ensure_dependencies() {
  local missing=0
  local dependencies=(aws curl unzip)

  for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "コマンド '$cmd' が見つかりません。インストールしてください。"
      missing=1
    fi
  done

  if [[ $missing -ne 0 ]]; then
    return 1
  fi
  return 0
}

################################################################################
# 設定ファイル読み込み
################################################################################
load_config() {
  local config_path="${SCRIPT_DIR}/config.sh"

  if [[ ! -f "$config_path" ]]; then
    log_error "設定ファイルが見つかりません: $config_path"
    return 1
  fi

  # shellcheck source=/dev/null
  if ! source "$config_path"; then
    log_error "設定ファイルの読み込みに失敗しました: $config_path"
    return 1
  fi

  if [[ -z "${LAMBDA_FUNC_NAME:-}" ]]; then
    log_error "config.sh内にLAMBDA_FUNC_NAMEが定義されていません。"
    return 1
  fi

  return 0
}

################################################################################
# 作業用ディレクトリ作成
################################################################################
create_workdir() {
  WORK_DIR="$(mktemp -d "/tmp/${MY_NAME}.XXXXXX")"
  if [[ -z "$WORK_DIR" ]]; then
    log_error "作業用ディレクトリの作成に失敗しました。"
    return 1
  fi

  log_info "作業用ディレクトリ: $WORK_DIR"
  return 0
}

################################################################################
# Lambda構成情報表示
################################################################################
show_lambda_configuration() {
  log_info "Lambda関数 [$LAMBDA_FUNC_NAME] の構成情報を取得します。"
  if ! aws lambda get-function \
      --function-name "$LAMBDA_FUNC_NAME" \
      --query 'Configuration.{FunctionName:FunctionName,Version:Version,LastModified:LastModified,Runtime:Runtime,RevisionId:RevisionId,CodeSize:CodeSize,Role:Role}' \
      --output table; then
    log_error "Lambda構成の取得に失敗しました。AWS CLIの認証情報やリージョンを確認してください。"
    return 1
  fi
  return 0
}

################################################################################
# Lambdaコードのダウンロード
################################################################################
download_lambda_package() {
  local code_url
  DOWNLOADED_ZIP="$WORK_DIR/lambda_package.zip"

  code_url=$(aws lambda get-function --function-name "$LAMBDA_FUNC_NAME" --query 'Code.Location' --output text)
  if [[ -z "$code_url" || "$code_url" == "None" ]]; then
    log_error "Lambdaコードの取得URLを取得できませんでした。"
    return 1
  fi

  log_info "Lambdaコードをダウンロード中..."
  if ! curl -sS -L "$code_url" -o "$DOWNLOADED_ZIP"; then
    log_error "Lambdaコードのダウンロードに失敗しました。"
    return 1
  fi

  log_info "Lambdaコードを保存しました: $DOWNLOADED_ZIP"
  return 0
}

################################################################################
# 展開してuser_data_template.shを表示
################################################################################
show_user_data_template() {
  local extract_dir template_files template_path
  extract_dir="$WORK_DIR/extracted"

  if ! mkdir -p "$extract_dir"; then
    log_error "展開先ディレクトリを作成できません: $extract_dir"
    return 1
  fi

  if ! unzip -q "$DOWNLOADED_ZIP" -d "$extract_dir"; then
    log_error "Lambdaコードの展開に失敗しました。"
    return 1
  fi

  mapfile -t template_files < <(find "$extract_dir" -type f -name 'user_data_template.sh' | sort)

  if [[ ${#template_files[@]} -eq 0 ]]; then
    log_error "展開内容からuser_data_template.shを見つけられませんでした。"
    return 1
  fi

  log_info "展開されたuser_data_template.shの内容を表示します。"
  for template_path in "${template_files[@]}"; do
    printf '%s\n' "----- ${template_path} -----"
    cat "$template_path"
    printf '%s\n' "----- end of ${template_path} -----"
  done
  return 0
}

################################################################################
# メイン処理
################################################################################
main() {
  log_info "AWS上のuser_data_template.sh確認処理を開始します。"

  if ! ensure_dependencies; then
    return 1
  fi

  if ! load_config; then
    return 1
  fi

  if ! create_workdir; then
    return 1
  fi

  if ! show_lambda_configuration; then
    return 1
  fi

  if ! download_lambda_package; then
    return 1
  fi

  if ! show_user_data_template; then
    return 1
  fi

  log_info "処理が完了しました。"
  return 0
}

main "$@"
exit $?

