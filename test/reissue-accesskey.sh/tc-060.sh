#!/usr/bin/env bash
################################################################################
#
# TC-060.sh
#
# 実行後の credentials 検証
# スクリプト実行後、~/.aws/credentials [default] が ts-010-user の
# 有効なアクセスキーで更新されていることを確認する
#
# 検証内容:
#   - aws sts get-caller-identity が成功すること（RC=0）
#   - 返却された ARN に ts-010-user が含まれること
#
# Last updated: 2026-03-30 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成
cp ${TARGET_SCRIPT}.org ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# キーが上限に達している場合は1個削除して空きを作る
KEY_COUNT=$(AWS_PROFILE=ts-usr-admin aws iam list-access-keys \
  --user-name ts-010-user \
  --query 'length(AccessKeyMetadata)' --output text)
if [[ ${KEY_COUNT} -ge 2 ]]; then
  OLDEST_KEY=$(AWS_PROFILE=ts-usr-admin aws iam list-access-keys \
    --user-name ts-010-user \
    --query 'AccessKeyMetadata[0].AccessKeyId' --output text)
  echo "前処理: キー上限のため最初のキーを削除します: ${OLDEST_KEY}"
  AWS_PROFILE=ts-usr-admin aws iam delete-access-key \
    --user-name ts-010-user --access-key-id "${OLDEST_KEY}"
fi

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始

################################################################################
# テスト（スクリプト実行）
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC=$?

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# テスト後処理：credentials 内容を検証
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

echo "------------------------------------------------------------"
echo "# credentials 検証"

# デフォルトプロファイルで sts get-caller-identity を実行
unset AWS_PROFILE
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN 2>/dev/null || true
CALLER_IDENTITY=$(aws sts get-caller-identity --output text 2>&1)
echo "${CALLER_IDENTITY}"

# ARN に ts-010-user が含まれることを確認
if echo "${CALLER_IDENTITY}" | grep -q 'ts-010-user'; then
  echo "[OK] credentials が ts-010-user で正しく更新されています"
else
  echo "[NG] credentials が ts-010-user になっていません"
fi

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
