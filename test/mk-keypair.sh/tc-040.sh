#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# キーペアが存在する状態から実行、正常処理（削除して再作成）
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
# テスト前処理: キーペアを作成（キーペアあり状態を作る）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# 既存キーペアを削除（あれば）
EXISTING_KEYPAIR=$(aws ec2 describe-key-pairs --key-names "${KEYPAIR_NAME}" \
  --query "KeyPairs[0].KeyName" --output text 2>/dev/null || echo "None")
if [[ "${EXISTING_KEYPAIR}" != "None" && -n "${EXISTING_KEYPAIR}" ]]; then
  aws ec2 delete-key-pair --key-name "${KEYPAIR_NAME}"
  echo "前処理: 既存キーペア [${KEYPAIR_NAME}] を削除しました"
fi
rm -f "${KEYPAIR_FILE}"

# キーペアを新規作成（スクリプトが「キーペアあり」の状態で実行されるようにする）
aws ec2 create-key-pair --key-name "${KEYPAIR_NAME}" --query "KeyMaterial" --output text > "${KEYPAIR_FILE}"
chmod 400 "${KEYPAIR_FILE}"
echo "前処理: キーペア [${KEYPAIR_NAME}] を作成しました (.pem: ${KEYPAIR_FILE})"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
