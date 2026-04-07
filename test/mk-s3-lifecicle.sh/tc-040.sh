#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# ライフサイクルルールが存在する状態から実行、正常処理（削除して再設定）
#
# 前提: ${BKT_IN} が存在すること（mk-s3bkt.sh 実行済み）
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
# テスト前処理: バケット存在確認 + ダミーライフサイクルルールを設定
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# 前提条件チェック
if ! aws s3api head-bucket --bucket "${TEST_BUCKET}" 2>/dev/null; then
  echo "前提条件エラー: バケット [${TEST_BUCKET}] が存在しません"
  echo "mk-s3bkt.sh を先に実行してください"
  exit 1
fi

# ダミーのライフサイクルルールを設定（ルールあり状態を作る）
DUMMY_CONFIG='{"Rules":[{"ID":"dummy-rule-for-test","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":999}}]}'
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${TEST_BUCKET}" \
  --lifecycle-configuration "${DUMMY_CONFIG}"
echo "前処理: ダミーライフサイクルルールを [${TEST_BUCKET}] に設定しました"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT} "${TEST_BUCKET}" "${TEST_EXPIRE_DAYS}"
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
