#!/bin/bash
################################################################################
# バケットよりオブジェクトをダウンロードし、
# ダウンロードに成功したオブジェクトはバケットから削除する
#
# Created     : 2025-09-16
# Last updated: 2025-12-04 00:03:20
#
MY_NAME=${0##*/}

# スクリプトが配置されているディレクトリ（work/ を想定）
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# 環境変数（AWS_ACCOUNT_ID 等）を読み込む
source "${SCRIPT_DIR}/.env"

# 以前の AssumeRole セッショントークンが残っていると AssumeRole が失敗するため事前にクリア
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# 対象バケット名
BUCKET_NAME="${BKT_OUT}"
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

# バケットが空の場合 Contents が null になるため、空配列にフォールバックして処理をスキップする
objects=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query "Contents[].{Key: Key, Size: Size}" --output json)
if [[ -z "$objects" || "$objects" == "null" ]]; then
  printf "INFO: No objects found in s3://%s. Nothing to do.\n" "$BUCKET_NAME"
  exit 0
fi

echo "$objects" | jq -c '.[]' | while read -r obj; do
    KEY=$(echo "$obj" | jq -r '.Key')
    SIZE=$(echo "$obj" | jq -r '.Size')

    DEST_PATH="$DEST_DIR/$KEY"
    DEST_DIRNAME=$(dirname "$DEST_PATH")

    # ローカルに保存するディレクトリを作成
    mkdir -p "$DEST_DIRNAME"

    printf "INFO: Downloading s3://%s/%s to %s ..." $BUCKET_NAME $KEY $DEST
    if aws s3 cp "s3://$BUCKET_NAME/$KEY" "$DEST_PATH"; then
        # ファイルサイズ確認
        LOCAL_SIZE=$(stat -c%s "$DEST_PATH")

        if [ "$LOCAL_SIZE" -eq "$SIZE" ]; then
            printf "OK: Download successful and size match. Deleting from S3...\n"
            aws s3 rm "s3://$BUCKET_NAME/$KEY"
        else
            printf "NG: Size mismatch! Local: %s, S3: %s. Skipping delete.\n" $LOCAL_SIZE $SIZE
        fi
    else
        printf "NG: Failed to download s3://%s/%s\n" $BUCKET_NAME $KEY
    fi
done
