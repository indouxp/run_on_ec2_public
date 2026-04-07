#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# キーペアの設定検証
# mk-keypair.sh 実行後、以下を確認する
# - AWS上にキーペアが存在すること (describe-key-pairs で確認)
# - .pem ファイルが PROJECT_ROOT に存在すること
# - .pem ファイルのパーミッションが 400 であること
#
# Last updated: 2026-03-19 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

cp config.sh.org config.sh

. assume-role.sh

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
# 変更部表示
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理: キーペアを削除（あれば）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# キーペアを削除（あれば）
EXISTING_KEYPAIR=$(aws ec2 describe-key-pairs --key-names "${KEYPAIR_NAME}" \
  --query "KeyPairs[0].KeyName" --output text 2>/dev/null || echo "None")
if [[ "${EXISTING_KEYPAIR}" != "None" && -n "${EXISTING_KEYPAIR}" ]]; then
  aws ec2 delete-key-pair --key-name "${KEYPAIR_NAME}"
  echo "前処理: キーペア [${KEYPAIR_NAME}] を削除しました"
else
  echo "前処理: キーペア [${KEYPAIR_NAME}] は存在しません（削除不要）"
fi
rm -f "${KEYPAIR_FILE}"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-keypair.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（キーペア設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# キーペア設定検証: ${KEYPAIR_NAME}"

# AWS上のキーペア存在確認
KP_NAME=$(aws ec2 describe-key-pairs --key-names "${KEYPAIR_NAME}" \
  --query "KeyPairs[0].KeyName" --output text 2>/dev/null || echo "None")
if [[ "${KP_NAME}" == "${KEYPAIR_NAME}" ]]; then
  echo "[OK] キーペア [${KEYPAIR_NAME}] がAWS上に存在します"
else
  echo "[NG] キーペア [${KEYPAIR_NAME}] がAWS上に存在しません"
  exit 1
fi

# .pem ファイル存在確認
if [[ -f "${KEYPAIR_FILE}" ]]; then
  echo "[OK] .pem ファイルが存在します: ${KEYPAIR_FILE}"
else
  echo "[NG] .pem ファイルが存在しません: ${KEYPAIR_FILE}"
  exit 1
fi

# .pem ファイルパーミッション確認（400）
PEM_PERMS=$(stat -c "%a" "${KEYPAIR_FILE}")
if [[ "${PEM_PERMS}" == "400" ]]; then
  echo "[OK] .pem ファイルのパーミッション: ${PEM_PERMS}"
else
  echo "[NG] .pem ファイルのパーミッションが想定外です: ${PEM_PERMS}（期待値: 400）"
  exit 1
fi

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
