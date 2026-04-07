#!/usr/bin/env bash
################################################################################
#
# TC-050.sh
#
# バケットポリシーが存在しない状態から実行、正常処理（新規設定）
#
# 前提: ${BKT_IN} と ${BKT_OUT} が存在すること（mk-s3bkt.sh 実行済み）
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
# テスト前処理: バケット存在確認 + ポリシーを削除
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# バケットが存在しない場合は作成（前提条件を整える）
for BKT in "${S3_BKT_IN}" "${S3_BKT_OUT}"; do
  if ! aws s3api head-bucket --bucket "${BKT}" 2>/dev/null; then
    aws s3api create-bucket --bucket "${BKT}" \
      --region ap-northeast-1 \
      --create-bucket-configuration LocationConstraint=ap-northeast-1
    echo "前処理: バケット [${BKT}] を作成しました"
  else
    echo "前処理: バケット [${BKT}] は既に存在します"
  fi
done

# 既存ポリシーを削除（なければ無視）
for BKT in "${S3_BKT_IN}" "${S3_BKT_OUT}"; do
  aws s3api delete-bucket-policy --bucket "${BKT}" 2>/dev/null && \
    echo "前処理: ポリシーを削除しました [${BKT}]" || \
    echo "前処理: ポリシーなし（削除不要）[${BKT}]"
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
