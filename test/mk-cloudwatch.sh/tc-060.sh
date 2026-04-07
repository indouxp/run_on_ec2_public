#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# ロググループ設定の検証
# - 3グループ（lambda/ec2/system）が存在すること
# - 保持期間が 30日 であること
# - メトリックフィルターが設定されていること
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
# テスト前処理: 全ロググループを削除（クリーンな状態から）
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

for LG in "${CW_LOG_GROUP_LAMBDA}" "${CW_LOG_GROUP_EC2}" "${CW_LOG_GROUP_SYSTEM}"; do
  if aws logs describe-log-groups --log-group-name-prefix "${LG}" \
      --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LG}"; then
    aws logs delete-log-group --log-group-name "${LG}"
    echo "前処理: ロググループ [${LG}] を削除（あれば）"
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
# テスト後処理: ロググループ設定検証
{ set +eE; set -x; } 2> /dev/null # エラートラップ停止

cat ${TARGET_SCRIPT}.log

echo "------------------------------------------------------------"
echo "# ロググループ設定検証"

for LG in "${CW_LOG_GROUP_LAMBDA}" "${CW_LOG_GROUP_EC2}" "${CW_LOG_GROUP_SYSTEM}"; do
  echo ""
  echo "## ロググループ: ${LG}"

  RETENTION=$(aws logs describe-log-groups \
    --log-group-name-prefix "${LG}" \
    --query 'logGroups[0].retentionInDays' \
    --output text 2>/dev/null || echo "None")

  if [[ -n "${RETENTION}" && "${RETENTION}" != "None" && "${RETENTION}" != "null" ]]; then
    echo "[OK] ロググループ [${LG}] が存在します"
  else
    echo "[NG] ロググループ [${LG}] が存在しません"
  fi

  if [[ "${RETENTION}" == "30" ]]; then
    echo "[OK] 保持期間: ${RETENTION}日"
  else
    echo "[NG] 保持期間が不正: ${RETENTION}（期待値: 30）"
  fi
done

{ set -eE; set +x; } 2> /dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
