#!/bin/bash
################################################################################
# S3ライフサイクルルール作成
# 引数1: バケット名（例: ${BKT_IN}）
# 引数2: オブジェクトを削除するまでの日数（整数）
################################################################################
set -euo pipefail

# スクリプト自身のディレクトリを取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)
# プロジェクトルート
PROJECT_ROOT=$(cd ${SCRIPT_DIR}/../../; pwd)

# 設定ファイル読み込み（AWSリージョン等を利用する場合）
source "${SCRIPT_DIR}/config.sh"

MY_NAME=${0##*/}
MY_SRC_DIR=./${MY_NAME}.src
LOG_PATH=${MY_NAME}.log

BUCKET_NAME=${1:-}
EXPIRE_DAYS=${2:-}

if [ -z "${BUCKET_NAME}" ] || [ -z "${EXPIRE_DAYS}" ]; then
  echo "Usage: ${MY_NAME} <bucket-name> <expire-days>"
  exit 1
fi

if ! [[ "${EXPIRE_DAYS}" =~ ^[0-9]+$ ]]; then
  echo "${MY_NAME}: expire-days は整数で指定してください"
  exit 1
fi

exec >> "${LOG_PATH}" 2>&1

[ ! -d ${MY_SRC_DIR} ] && { mkdir ${MY_SRC_DIR}; }
[ ! -d ${MY_SRC_DIR} ] && { echo "${MY_NAME}: not exist ${MY_SRC_DIR}"; exit 1; }

CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RULE_ID="${BUCKET_NAME}-expire-${EXPIRE_DAYS}d-created_at=${CREATED_AT}"

################################################################################
# ライフサイクルルール表示
################################################################################
show_lifecycle() {
  cat <<EOT
  # ライフサイクルルール確認（${BUCKET_NAME}）
EOT

  RULES_JSON=$(aws s3api get-bucket-lifecycle-configuration \
    --bucket "${BUCKET_NAME}" \
    --query 'Rules' \
    --output json 2>/dev/null || echo '[]')

  RULES_JSON="${RULES_JSON}" python - <<'PY'
import json
import os
import sys

rules_raw = os.environ.get("RULES_JSON", "[]")
try:
    rules = json.loads(rules_raw)
except Exception:
    rules = []

if not rules:
    print("  ルールは設定されていません")
    sys.exit(0)

print("  # ルール一覧（作成日時含む）")
for r in rules:
    rid = r.get("ID", "(no id)")
    created = "N/A"
    if "created_at=" in rid:
        created = rid.split("created_at=", 1)[1]
    exp = r.get("Expiration", {}) or {}
    days = exp.get("Days")
    if days is not None:
        exp_desc = f"{days}日後削除"
    else:
        exp_desc = json.dumps(exp, ensure_ascii=False) if exp else "N/A"
    print(f"  - ID={rid} | Status={r.get('Status')} | Expiration={exp_desc} | CreatedAt={created}")

print("\n  # ルール詳細(JSON)")
print(json.dumps({"Rules": rules}, indent=2, ensure_ascii=False))
PY
}

################################################################################
# ライフサイクルルール作成
################################################################################
create_lifecycle() {
  cat <<EOT
  # ライフサイクルルール作成（ID: ${RULE_ID}, 期限: ${EXPIRE_DAYS}日）
EOT

  # 既存のライフサイクル設定を削除して再作成
  if aws s3api get-bucket-lifecycle-configuration --bucket "${BUCKET_NAME}" >/dev/null 2>&1; then
    aws s3api delete-bucket-lifecycle --bucket "${BUCKET_NAME}"
    echo "  既存のライフサイクル設定を削除しました。"
  fi

  CONFIG_FILE=${MY_SRC_DIR}/lifecycle-${BUCKET_NAME}.json
  cat > "${CONFIG_FILE}" <<EOF
{"Rules":[{"ID":"${RULE_ID}","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":${EXPIRE_DAYS}}}]}
EOF

  aws s3api put-bucket-lifecycle-configuration \
    --bucket "${BUCKET_NAME}" \
    --lifecycle-configuration file://"${CONFIG_FILE}"

  echo "  ルールをバケットに適用しました (${CONFIG_FILE})"
}

################################################################################
# メイン処理
################################################################################
date
show_lifecycle
create_lifecycle
show_lifecycle

exit 0

################################################################################
# 変更履歴:
# 2025-09-08: S3ライフサイクルルール作成スクリプト新規作成
################################################################################
