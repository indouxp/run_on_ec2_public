#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# バケットポリシー設定検証
# mk-s3bktpolicy.sh 実行後、以下を確認する
# - 入力バケット（${BKT_IN}）にポリシーが設定されていること
# - 出力バケット（${BKT_OUT}）にポリシーが設定されていること
# - 各ポリシーに AllowLambdaRoleAccess と AllowEC2RoleAccess の Statement が含まれること
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
# テスト前処理: バケット存在確認 + ポリシーを削除して初期状態にする
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

# 既存ポリシーを削除
for BKT in "${S3_BKT_IN}" "${S3_BKT_OUT}"; do
  aws s3api delete-bucket-policy --bucket "${BKT}" 2>/dev/null || true
  echo "前処理: ポリシーを削除（あれば）[${BKT}]"
done

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# テスト（mk-s3bktpolicy.sh 実行）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC="$?"

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理（ポリシー設定検証）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# バケットポリシー設定検証"

for BKT in "${S3_BKT_IN}" "${S3_BKT_OUT}"; do
  echo ""
  echo "## バケット: ${BKT}"

  POLICY=$(aws s3api get-bucket-policy --bucket "${BKT}" \
    --query 'Policy' --output text 2>/dev/null || echo "")

  if [[ -z "${POLICY}" ]]; then
    echo "[NG] バケット [${BKT}] にポリシーが設定されていません"
    exit 1
  fi
  echo "[OK] バケット [${BKT}] にポリシーが存在します"

  # AllowLambdaRoleAccess Statement 確認
  if echo "${POLICY}" | grep -q "AllowLambdaRoleAccess"; then
    echo "[OK] AllowLambdaRoleAccess Statement が存在します"
  else
    echo "[NG] AllowLambdaRoleAccess Statement が見つかりません"
    exit 1
  fi

  # AllowEC2RoleAccess Statement 確認
  if echo "${POLICY}" | grep -q "AllowEC2RoleAccess"; then
    echo "[OK] AllowEC2RoleAccess Statement が存在します"
  else
    echo "[NG] AllowEC2RoleAccess Statement が見つかりません"
    exit 1
  fi
done

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
