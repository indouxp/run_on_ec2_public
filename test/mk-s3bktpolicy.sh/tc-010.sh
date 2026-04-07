#!/usr/bin/env bash
################################################################################
#
# TC-010.sh
#
# バケットが存在しない状態で実行した場合の異常終了
# mk-s3bktpolicy.sh は config.sh を使用しないため、
# tc-010 は「バケットなし → put-bucket-policy で NoSuchBucket → 異常終了」とする
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

rm -f ${TARGET_SCRIPT}.log

for BKT in "${S3_BKT_IN}" "${S3_BKT_OUT}"; do
  if aws s3api head-bucket --bucket "${BKT}" 2>/dev/null; then
    aws s3api put-bucket-versioning \
      --bucket "${BKT}" \
      --versioning-configuration Status=Suspended 2>/dev/null || true
    aws s3 rm "s3://${BKT}" --recursive 2>/dev/null || true
    aws s3api delete-bucket --bucket "${BKT}"
    echo "前処理: バケット [${BKT}] を削除しました"
  else
    echo "前処理: バケット [${BKT}] は存在しません（削除不要）"
  fi
done

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
