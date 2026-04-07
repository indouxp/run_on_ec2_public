#!/usr/bin/env bash
################################################################################
#
# TC-070.sh
#
# 権限のないプロファイルでの異常終了
# AWS_PROFILE=ts-usr-admin を無効なプロファイル名に書き換えて
# create-access-key が認証エラーで失敗することを確認
#
# Last updated: 2026-03-30 00:00:00
################################################################################
set -eEuo pipefail
. tc-cmn.sh

# テスト用スクリプト作成（プロファイル名を無効な名前に書き換え）
sed 's/AWS_PROFILE=ts-usr-admin/AWS_PROFILE=ts-notexist-profile/' \
  ${TARGET_SCRIPT}.org > ${TARGET_SCRIPT} && chmod +x ${TARGET_SCRIPT}

# AssumeRole・管理者認証情報をクリアしてデフォルト認証情報を使用
unset AWS_PROFILE
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN 2>/dev/null || true

exec > >(tee -a "${LOG_PATH}") 2>&1 # 以下ロギング

################################################################################
# 開始
echo "${HEADER}"
diff_target "${TARGET_SCRIPT}.org" "${TARGET_SCRIPT}"

################################################################################
# テスト前処理
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

rm -f ${TARGET_SCRIPT}.log

# 実行ユーザーの確認
aws sts get-caller-identity 2>&1 || true

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始

################################################################################
# テスト（プロファイル未存在で認証エラーを期待）
{ set +eE; set -x; } 2>/dev/null # エラートラップ停止

./${TARGET_SCRIPT}
RC=$?

{ set -eE; set +x; } 2>/dev/null # エラートラップ開始
echo "return code=${RC}"

################################################################################
# 終了
echo "${HL}"
echo "${FOOTER}"
