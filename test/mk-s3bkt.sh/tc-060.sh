#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# バケット設定検証
# mk-s3bkt.sh 実行後、以下を確認する
# - 入力バケット（${BKT_IN}）がAWS上に存在すること
# - 出力バケット（${BKT_OUT}）がAWS上に存在すること
# - 両バケットのパブリックアクセスブロックがすべて有効であること
# - 両バケットのサーバーサイド暗号化が AES256 であること
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
# テスト前処理: バケットを削除（あれば）して初期状態にする
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

ls -l config.sh

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
# テスト（mk-s3bkt.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（バケット設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# バケット設定検証"

for BKT in "${S3_BKT_IN}" "${S3_BKT_OUT}"; do
  echo ""
  echo "## バケット: ${BKT}"

  # バケット存在確認
  if aws s3api head-bucket --bucket "${BKT}" 2>/dev/null; then
    echo "[OK] バケット [${BKT}] がAWS上に存在します"
  else
    echo "[NG] バケット [${BKT}] がAWS上に存在しません"
    exit 1
  fi

  # パブリックアクセスブロック確認
  PAB=$(aws s3api get-public-access-block --bucket "${BKT}" \
    --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null || echo '{}')
  if echo "${PAB}" | grep -q '"BlockPublicAcls": true' && \
     echo "${PAB}" | grep -q '"BlockPublicPolicy": true'; then
    echo "[OK] パブリックアクセスブロック: 有効"
  else
    echo "[NG] パブリックアクセスブロックの設定が想定外です"
    echo "${PAB}"
    exit 1
  fi

  # 暗号化設定確認（AES256）
  ENC=$(aws s3api get-bucket-encryption --bucket "${BKT}" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text 2>/dev/null || echo "None")
  if [[ "${ENC}" == "AES256" ]]; then
    echo "[OK] サーバーサイド暗号化: AES256"
  else
    echo "[NG] サーバーサイド暗号化が想定外です: ${ENC}（期待値: AES256）"
    exit 1
  fi
done

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
