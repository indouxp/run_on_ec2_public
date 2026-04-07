#!/bin/bash
################################################################################
# 目的    : run.conf を対話的に作成する
# 概要    : 各要素の値をターミナルから取得し、JSON 形式で run.conf を出力する
# 作成者  : Codex Agent
# 日付    : 2025-11-16
# Last updated: 2026-03-26 20:41:57
################################################################################

set -u
set -o pipefail

readonly RUN_CONF_PATH="run.conf"
readonly RUN_CONF_SKEL_PATH="run.conf.skl"
readonly FIELD_KEYS=(
  "exec"
  "log"
  "result"
  "mail"
  "sms"
  "ec2_role_name"
  "subnet_name"
  "sg_name"
  "ec2_instance_name_tag"
  "output_bucket"
  "default_ami_id"
  "instance_type"
  "ses_from_email"
  "key_name"
  "prj_prefix"
  "ebs_size"
)
readonly FIELD_MESSAGES=(
  "実行コマンド(exec) を入力してください"
  "ログファイル名(log) を入力してください"
  "結果ファイル(result) を入力してください"
  "通知メールアドレス(mail) を入力してください"
  "SMS 送信先(sms) を入力してください"
  "EC2 ロール名(ec2_role_name) を入力してください"
  "サブネット名(subnet_name) を入力してください"
  "セキュリティグループ名(sg_name) を入力してください"
  "EC2 インスタンスタグ(ec2_instance_name_tag) を入力してください"
  "出力バケット名(output_bucket) を入力してください"
  "デフォルト AMI ID(default_ami_id) を入力してください"
  "インスタンスタイプ(instance_type) を入力してください"
  "SES 送信元メール(ses_from_email) を入力してください"
  "キーペア名(key_name) を入力してください"
  "プロジェクト接頭辞(prj_prefix) を入力してください"
  "EBS サイズ(ebs_size) を入力してください"
)

declare -A FIELD_VALUES=()
declare -A DEFAULT_VALUES=()

cleanup() {
  :
}

handle_signal() {
  local signal_name="$1"

  printf "シグナル(%s)を受信したため処理を中断します\n" "${signal_name}" >&2
}

trap 'cleanup' EXIT
trap 'handle_signal "SIGINT"; exit 130' SIGINT
trap 'handle_signal "SIGTERM"; exit 143' SIGTERM

# 文字列の前後空白を除去する
trim_whitespace() {
  local raw_value="$1"
  local trimmed_value

  trimmed_value="${raw_value#"${raw_value%%[![:space:]]*}"}"
  trimmed_value="${trimmed_value%"${trimmed_value##*[![:space:]]}"}"
  printf "%s" "${trimmed_value}"
}

# JSON 文字列に利用できるようエスケープする
json_escape() {
  local raw_value="$1"
  local escaped_value

  escaped_value="${raw_value//\\/\\\\}"
  escaped_value="${escaped_value//\"/\\\"}"
  escaped_value="${escaped_value//$'\n'/\\n}"
  escaped_value="${escaped_value//$'\r'/\\r}"
  escaped_value="${escaped_value//$'\t'/\\t}"

  printf "%s" "${escaped_value}"
}

# run.conf.skl からデフォルト値を読み込む
load_default_values() {
  local skeleton_path="$1"
  local parse_output
  local key
  local value

  if [[ ! -f "${skeleton_path}" ]]; then
    printf "デフォルトファイルが見つかりません: %s\n" "${skeleton_path}" >&2
    return 1
  fi

  if ! parse_output="$(
    python - "${skeleton_path}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception as exc:
    sys.stderr.write(f"run.conf.skl 読み込みに失敗しました: {exc}\n")
    sys.exit(1)

for key, value in data.items():
    print(f"{key}\t{value}")
PY
  )"; then
    printf "デフォルト値を読み込めませんでした\n" >&2
    return 1
  fi

  if [[ -z "${parse_output}" ]]; then
    printf "デフォルト値の読み込み結果が空です\n" >&2
    return 1
  fi

  while IFS=$'\t' read -r key value
  do
    if [[ -n "${key}" ]]; then
      DEFAULT_VALUES["${key}"]="${value}"
    fi
  done <<< "${parse_output}"

  return 0
}

# 単一フィールドの入力を取得する
prompt_for_field() {
  local field_key="$1"
  local message="$2"
  local default_value="$3"
  local input_value
  local trimmed_value
  local prompt_message
  local selected_value

  prompt_message="${message}"
  if [[ -n "${default_value}" ]]; then
    prompt_message="${prompt_message} [default: ${default_value}]"
  fi

  while true
  do
    printf "%s: " "${prompt_message}"
    if ! IFS= read -r input_value; then
      printf "入力を読み取れませんでした\n" >&2
      return 1
    fi

    trimmed_value="$(trim_whitespace "${input_value}")"
    if [[ -z "${trimmed_value}" ]]; then
      if [[ -n "${default_value}" ]]; then
        selected_value="${default_value}"
      else
        printf "値が空です。再入力してください\n" >&2
        continue
      fi
    else
      selected_value="${trimmed_value}"
    fi

    FIELD_VALUES["${field_key}"]="${selected_value}"
    break
  done

  return 0
}

# run.conf を作成する
write_run_conf() {
  local output_path="$1"
  local total_fields="${#FIELD_KEYS[@]}"
  local index=0
  local field_key
  local separator
  local escaped_value

  if [[ "${total_fields}" -eq 0 ]]; then
    printf "出力する項目がありません\n" >&2
    return 1
  fi

  if ! cleanup_before_write "${output_path}"; then
    return 1
  fi

  {
    printf "{\n"
    for field_key in "${FIELD_KEYS[@]}"
    do
      index=$((index + 1))
      separator=","
      if [[ "${index}" -eq "${total_fields}" ]]; then
        separator=""
      fi

      escaped_value="$(json_escape "${FIELD_VALUES["${field_key}"]}")"
      printf "  \"%s\": \"%s\"%s\n" "${field_key}" "${escaped_value}" "${separator}"
    done
    printf "}\n"
  } > "${output_path}"

  return 0
}

# 出力先の事前チェックを行う
cleanup_before_write() {
  local output_path="$1"
  local output_dir

  output_dir="$(dirname "${output_path}")"
  if [[ -n "${output_dir}" && ! -d "${output_dir}" ]]; then
    if ! mkdir -p "${output_dir}"; then
      printf "ディレクトリを作成できませんでした: %s\n" "${output_dir}" >&2
      return 1
    fi
  fi

  return 0
}

main() {
  local i=0
  local total="${#FIELD_KEYS[@]}"
  local default_value=""

  if ! load_default_values "${RUN_CONF_SKEL_PATH}"; then
    return 1
  fi

  while [[ "${i}" -lt "${total}" ]]
  do
    default_value=""
    if [[ -n "${DEFAULT_VALUES["${FIELD_KEYS[${i}]}"]+exists}" ]]; then
      default_value="$(trim_whitespace "${DEFAULT_VALUES["${FIELD_KEYS[${i}]}"]}")"
    fi

    if ! prompt_for_field "${FIELD_KEYS[${i}]}" "${FIELD_MESSAGES[${i}]}" "${default_value}"; then
      return 1
    fi
    i=$((i + 1))
  done

  if ! write_run_conf "${RUN_CONF_PATH}"; then
    return 1
  fi

  printf "run.conf を作成しました: %s\n" "${RUN_CONF_PATH}"

  return 0
}

main "$@"
