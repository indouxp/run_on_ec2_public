#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# バケットが存在する状態から実行、正常処理（削除して再作成）
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
# テスト前処理: バケットを作成（なければ新規作成）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# 入力バケット作成（なければ）
if ! aws s3api head-bucket --bucket "${S3_BKT_IN}" 2>/dev/null; then
  aws s3api create-bucket --bucket "${S3_BKT_IN}" \
    --region ap-northeast-1 \
    --create-bucket-configuration LocationConstraint=ap-northeast-1
  echo "前処理: バケット [${S3_BKT_IN}] を作成しました"
else
  echo "前処理: バケット [${S3_BKT_IN}] は既に存在します"
fi

# 出力バケット作成（なければ）
if ! aws s3api head-bucket --bucket "${S3_BKT_OUT}" 2>/dev/null; then
  aws s3api create-bucket --bucket "${S3_BKT_OUT}" \
    --region ap-northeast-1 \
    --create-bucket-configuration LocationConstraint=ap-northeast-1
  echo "前処理: バケット [${S3_BKT_OUT}] を作成しました"
else
  echo "前処理: バケット [${S3_BKT_OUT}] は既に存在します"
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
