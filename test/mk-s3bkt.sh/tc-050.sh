#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# バケットが存在しない状態から実行、正常処理（新規作成）
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
# テスト前処理: バケットを削除（あれば）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# 入力バケット削除（あれば）
if aws s3api head-bucket --bucket "${S3_BKT_IN}" 2>/dev/null; then
  aws s3api put-bucket-versioning \
    --bucket "${S3_BKT_IN}" \
    --versioning-configuration Status=Suspended 2>/dev/null || true
  aws s3 rm "s3://${S3_BKT_IN}" --recursive 2>/dev/null || true
  aws s3api delete-bucket --bucket "${S3_BKT_IN}"
  echo "前処理: バケット [${S3_BKT_IN}] を削除しました"
else
  echo "前処理: バケット [${S3_BKT_IN}] は存在しません（削除不要）"
fi

# 出力バケット削除（あれば）
if aws s3api head-bucket --bucket "${S3_BKT_OUT}" 2>/dev/null; then
  aws s3api put-bucket-versioning \
    --bucket "${S3_BKT_OUT}" \
    --versioning-configuration Status=Suspended 2>/dev/null || true
  aws s3 rm "s3://${S3_BKT_OUT}" --recursive 2>/dev/null || true
  aws s3api delete-bucket --bucket "${S3_BKT_OUT}"
  echo "前処理: バケット [${S3_BKT_OUT}] を削除しました"
else
  echo "前処理: バケット [${S3_BKT_OUT}] は存在しません（削除不要）"
fi

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
