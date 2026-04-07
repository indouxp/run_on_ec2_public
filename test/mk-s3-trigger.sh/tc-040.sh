#!/usr/bin/env bash
################################################################################
#
# TC-040.sh
#
# トリガーが設定済みの状態から実行、正常処理（削除して再設定）
#
# 前提: ${BKT_IN} と ts-010-lmd-010 が存在すること
# → Lambda 未作成の場合は前提条件エラーでスキップ
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
# テスト前処理: 前提条件チェック
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

rm -f ${TARGET_SCRIPT}.log

# Lambda 存在確認
if ! aws lambda get-function --function-name "${LAMBDA_FUNC}" 2>/dev/null; then
  echo "前提条件エラー: Lambda 関数 [${LAMBDA_FUNC}] が存在しません"
  echo "mk-lambda.sh を先に実行してください"
  echo "このテストをスキップします"
  exit 1
fi

# バケット存在確認
if ! aws s3api head-bucket --bucket "${S3_BKT_IN}" 2>/dev/null; then
  echo "前提条件エラー: バケット [${S3_BKT_IN}] が存在しません"
  echo "mk-s3bkt.sh を先に実行してください"
  exit 1
fi

echo "前提条件OK: Lambda=${LAMBDA_FUNC}, Bucket=${S3_BKT_IN}"

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
