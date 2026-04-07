#!/bin/bash
# S3にアップロードしてシステムを起動するスクリプト
# Last updated: 2026-04-06 00:03:38
set -eu
MY_NAME=${0##*/}
MY_SRC_DIR=./${MY_NAME}.src
LOG_PATH=${MY_NAME}.log
exec > "${LOG_PATH}" 2>&1

# スクリプトが配置されているディレクトリ（work/ を想定）
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# 環境変数（AWS_ACCOUNT_ID 等）を読み込む
source "${SCRIPT_DIR}/.env"

# 以前の AssumeRole セッショントークンが残っていると AssumeRole が失敗するため事前にクリア
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
  $(aws sts assume-role \
      --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/ts-010-role-exec \
      --role-session-name MySession \
      --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
      --output text))

aws sts get-caller-identity

echo "$(date '+%Y-%m-%d %H:%M:%S') Uploading files to S3 bucket: ${BKT_IN}"

FILES=$(grep "exec" run.conf | sed 's#[",:]##g' | awk '{for(i=3; i<=NF; i++){print $i;}}')

for FILE in "$FILES"
do
  echo "Uploading files to S3 bucket:  ${FILE}"
  aws s3 cp ${FILE} s3://${BKT_IN}/
done

# 実行シェルをアップロード
aws s3 cp ./run.sh s3://${BKT_IN}/

# 定義ファイルをアップロードしてLambdaをトリガー
aws s3 cp ./run.conf s3://${BKT_IN}/

echo "$(date '+%Y-%m-%d %H:%M:%S') Upload complete. The system should now be triggered."
