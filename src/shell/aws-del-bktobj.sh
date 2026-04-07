#!/bin/bash
################################################################################
# バケットから削除する
#
# Created     : 2025-09-16
# Last updated: 2025-12-04 00:03:20
#
MY_NAME=${0##*/}

# 対象バケット名
BUCKET_NAME="${BKT_IN}"
if [[ "$#" -ne "0" ]]; then
  BUCKET_NAME="$1"
fi

# 作業ディレクトリ（必要に応じて変更）
DEST_DIR="./downloaded_files"

# 保存先ディレクトリを作成
mkdir -p "$DEST_DIR" 2>/dev/null

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
         $(aws sts assume-role \
           --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/ts-010-role-exec \
           --role-session-name MySession \
           --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
           --output text))

aws sts get-caller-identity

# S3オブジェクトの一覧取得
printf "INFO: Listing all objects in s3://%s ...\n" $BUCKET_NAME
aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query "Contents[].{Key: Key, Size: Size}" --output json |
jq -c '.[]' | while read -r obj; do
    KEY=$(echo "$obj" | jq -r '.Key')
    SIZE=$(echo "$obj" | jq -r '.Size')

    printf "INFO: remove s3://%s/%s ..." $BUCKET_NAME $KEY
    aws s3 rm "s3://$BUCKET_NAME/$KEY"
done
