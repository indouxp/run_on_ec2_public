#!/usr/bin/env bash
################################################################################
# スクリプト名 : del-all.sh
# 概要         : このプロジェクトで作成した全AWSリソースを削除する
#                クリーン再構築・環境撤収時に使用する
# 使用方法     : AWS_PROFILE=ts-usr-admin ./del-all.sh
# 注意         : 削除は不可逆。実行前に内容を確認すること
# Created      : 2026-03-19
# Last updated : 2026-03-25 00:00:00
# Author       : Tsystem
# 更新履歴     :
#    2026-03-19: 初版
################################################################################
set -uo pipefail
# -e は付けない（リソース未存在時のエラーを || true で吸収するため）

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)  # スクリプト自身のディレクトリ
source "${SCRIPT_DIR}/config.sh"            # プロジェクト共通設定

MY_NAME=${0##*/}
LOG_PATH=./${MY_NAME}.log

exec >> "${LOG_PATH}" 2>&1

echo "============================================================"
echo "全リソース削除開始: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

################################################################################
# 1. EC2インスタンスの終了
################################################################################
echo ""
echo "--- 1. EC2インスタンス ---"

# ts-010-ec2-ssh-010（SSH接続用テストインスタンス）
EC2_SSH_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PRJ_PREFIX}-ec2-ssh-010" \
            "Name=instance-state-name,Values=running,stopped,pending,stopping" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text 2>/dev/null || true)
if [[ -n "${EC2_SSH_ID}" && "${EC2_SSH_ID}" != "None" ]]; then
  aws ec2 terminate-instances --instance-ids "${EC2_SSH_ID}" > /dev/null
  echo "EC2終了リクエスト: ${PRJ_PREFIX}-ec2-ssh-010 (${EC2_SSH_ID})"
  aws ec2 wait instance-terminated --instance-ids "${EC2_SSH_ID}"
  echo "EC2削除完了: ${PRJ_PREFIX}-ec2-ssh-010"
else
  echo "スキップ: ${PRJ_PREFIX}-ec2-ssh-010 は存在しません"
fi

# ts-010-ec2-010（通常実行インスタンス ── 処理中断時に残存する可能性）
EC2_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PRJ_PREFIX}-ec2-010" \
            "Name=instance-state-name,Values=running,stopped,pending,stopping" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text 2>/dev/null || true)
if [[ -n "${EC2_ID}" && "${EC2_ID}" != "None" ]]; then
  aws ec2 terminate-instances --instance-ids "${EC2_ID}" > /dev/null
  echo "EC2終了リクエスト: ${PRJ_PREFIX}-ec2-010 (${EC2_ID})"
  aws ec2 wait instance-terminated --instance-ids "${EC2_ID}"
  echo "EC2削除完了: ${PRJ_PREFIX}-ec2-010"
else
  echo "スキップ: ${PRJ_PREFIX}-ec2-010 は存在しません"
fi

################################################################################
# 2. EventBridgeルール
################################################################################
echo ""
echo "--- 2. EventBridge ---"

RULE_NAME="${PRJ_PREFIX}-rule-stop-ec2-trigger"  # EventBridgeルール名
if aws events describe-rule --name "${RULE_NAME}" > /dev/null 2>&1; then
  # ターゲットを先に削除（ターゲットがないとルール削除不可）
  TARGET_IDS=$(aws events list-targets-by-rule --rule "${RULE_NAME}" \
    --query 'Targets[].Id' --output text 2>/dev/null || true)
  if [[ -n "${TARGET_IDS}" && "${TARGET_IDS}" != "None" ]]; then
    aws events remove-targets --rule "${RULE_NAME}" --ids ${TARGET_IDS} > /dev/null || true
  fi
  aws events delete-rule --name "${RULE_NAME}" || true
  echo "EventBridgeルール削除: ${RULE_NAME}"
else
  echo "スキップ: ${RULE_NAME} は存在しません"
fi

################################################################################
# 3. Lambda関数
################################################################################
echo ""
echo "--- 3. Lambda ---"

for func_name in "${LAMBDA_FUNC_NAME}" "${PRJ_PREFIX}-lmd-020"; do
  if aws lambda get-function --function-name "${func_name}" > /dev/null 2>&1; then
    aws lambda delete-function --function-name "${func_name}" || true
    echo "Lambda削除: ${func_name}"
  else
    echo "スキップ: ${func_name} は存在しません"
  fi
done

################################################################################
# 4. S3トリガー（バケット通知設定のクリア）
################################################################################
echo ""
echo "--- 4. S3トリガー ---"

if aws s3api head-bucket --bucket "${S3_BKT_IN_NAME}" > /dev/null 2>&1; then
  aws s3api put-bucket-notification-configuration \
    --bucket "${S3_BKT_IN_NAME}" \
    --notification-configuration '{}' || true
  echo "S3トリガークリア: ${S3_BKT_IN_NAME}"
else
  echo "スキップ: ${S3_BKT_IN_NAME} は存在しません"
fi

################################################################################
# 5. SNSトピック・サブスクリプション
################################################################################
echo ""
echo "--- 5. SNS ---"

TOPIC_ARN=$(aws sns list-topics \
  --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
  --output text 2>/dev/null || true)
if [[ -n "${TOPIC_ARN}" && "${TOPIC_ARN}" != "None" ]]; then
  # サブスクリプションをすべて解除
  SUBS=$(aws sns list-subscriptions-by-topic --topic-arn "${TOPIC_ARN}" \
    --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null || true)
  for sub in ${SUBS}; do
    [[ "${sub}" == "PendingConfirmation" ]] && continue
    aws sns unsubscribe --subscription-arn "${sub}" || true
  done
  aws sns delete-topic --topic-arn "${TOPIC_ARN}" || true
  echo "SNSトピック削除: ${SNS_TOPIC_NAME}"
else
  echo "スキップ: ${SNS_TOPIC_NAME} は存在しません"
fi

################################################################################
# 6. CloudWatch ロググループ
################################################################################
echo ""
echo "--- 6. CloudWatch ロググループ ---"

for lg in "${CW_LOG_GROUP_LAMBDA_NAME}" "${CW_LOG_GROUP_EC2_NAME}" "${CW_LOG_GROUP_SYSTEM_NAME}"; do
  if aws logs describe-log-groups --log-group-name-prefix "${lg}" \
       --query "logGroups[?logGroupName=='${lg}']" --output text 2>/dev/null | grep -q .; then
    aws logs delete-log-group --log-group-name "${lg}" || true
    echo "ロググループ削除: ${lg}"
  else
    echo "スキップ: ${lg} は存在しません"
  fi
done

# Lambda 実行時に AWS が自動作成するロググループ（/aws/lambda/<関数名>）を削除
# mk-cloudwatch.sh の対象外だが、Lambda 関数削除後も残存するため明示的に削除する
for func in "${LAMBDA_FUNC_NAME}" "${PRJ_PREFIX}-lmd-020"; do
  local_lg="/aws/lambda/${func}"  # Lambda自動作成ロググループ名
  if aws logs describe-log-groups --log-group-name-prefix "${local_lg}" \
       --query "logGroups[?logGroupName=='${local_lg}']" --output text 2>/dev/null | grep -q .; then
    aws logs delete-log-group --log-group-name "${local_lg}" || true
    echo "ロググループ削除: ${local_lg}"
  else
    echo "スキップ: ${local_lg} は存在しません"
  fi
done

################################################################################
# 7. S3バケット（オブジェクト・バージョン・ポリシーごと削除）
################################################################################
echo ""
echo "--- 7. S3バケット ---"

_delete_bucket() {
  local bucket="$1"
  if ! aws s3api head-bucket --bucket "${bucket}" > /dev/null 2>&1; then
    echo "スキップ: ${bucket} は存在しません"
    return 0
  fi
  # バケットポリシー削除
  aws s3api delete-bucket-policy --bucket "${bucket}" 2>/dev/null || true
  # バージョン付きオブジェクトの一括削除
  for query in \
    'Versions[].{Key:Key,VersionId:VersionId}' \
    'DeleteMarkers[].{Key:Key,VersionId:VersionId}'
  do
    local objects
    objects=$(aws s3api list-object-versions --bucket "${bucket}" \
      --query "${query}" --output json 2>/dev/null || echo 'null')
    if [[ "${objects}" != "null" && "${objects}" != "[]" && -n "${objects}" ]]; then
      local delete_json
      delete_json=$(python3 -c "
import sys, json
objs = json.loads('''${objects}''')
if objs:
    print(json.dumps({'Objects': objs, 'Quiet': True}))
" 2>/dev/null || true)
      if [[ -n "${delete_json}" ]]; then
        aws s3api delete-objects --bucket "${bucket}" --delete "${delete_json}" > /dev/null || true
      fi
    fi
  done
  # 通常オブジェクト削除（バージョニング無効バケット用）
  aws s3 rm "s3://${bucket}" --recursive > /dev/null 2>&1 || true
  # バケット削除
  aws s3api delete-bucket --bucket "${bucket}" --region "${AWS_REGION}" || true
  echo "S3バケット削除: ${bucket}"
}

_delete_bucket "${S3_BKT_IN_NAME}"
_delete_bucket "${S3_BKT_OUT_NAME}"

################################################################################
# 8. CloudTrail（証跡削除 → ログバケット削除）
################################################################################
echo ""
echo "--- 8. CloudTrail ---"

TRAIL_NAME="${PRJ_PREFIX}-trail-010"                # CloudTrail証跡名
TRAIL_BKT_NAME="${PRJ_PREFIX}-bkt-cloudtrail-logs"  # CloudTrailログバケット名

# 証跡のロギング停止・削除
if aws cloudtrail get-trail --name "${TRAIL_NAME}" > /dev/null 2>&1; then
  aws cloudtrail stop-logging --name "${TRAIL_NAME}" || true
  aws cloudtrail delete-trail --name "${TRAIL_NAME}" || true
  echo "CloudTrail証跡削除: ${TRAIL_NAME}"
else
  echo "スキップ: ${TRAIL_NAME} は存在しません"
fi

# CloudTrailログバケット削除（証跡削除後に実施）
_delete_bucket "${TRAIL_BKT_NAME}"

################################################################################
# 9. キーペア
################################################################################
echo ""
echo "--- 9. キーペア ---"

KEYPAIR_NAME="${PRJ_PREFIX}-keypair"  # キーペア名
if aws ec2 describe-key-pairs --key-names "${KEYPAIR_NAME}" > /dev/null 2>&1; then
  aws ec2 delete-key-pair --key-name "${KEYPAIR_NAME}" || true
  echo "キーペア削除: ${KEYPAIR_NAME}"
else
  echo "スキップ: ${KEYPAIR_NAME} は存在しません"
fi

################################################################################
# 10. ネットワーク（SG → サブネット → ルートテーブル → IGW → VPC）
################################################################################
echo ""
echo "--- 10. ネットワーク ---"

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)

if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
  echo "スキップ: ${VPC_NAME} は存在しません"
else
  echo "対象VPC: ${VPC_NAME} (${VPC_ID})"

  # セキュリティグループ削除（デフォルトSG以外）
  SG_IDS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text 2>/dev/null || true)
  for sg_id in ${SG_IDS}; do
    aws ec2 delete-security-group --group-id "${sg_id}" > /dev/null 2>&1 || true
    echo "  SG削除: ${sg_id}"
  done

  # サブネット削除
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[].SubnetId' --output text 2>/dev/null || true)
  for subnet_id in ${SUBNET_IDS}; do
    aws ec2 delete-subnet --subnet-id "${subnet_id}" > /dev/null 2>&1 || true
    echo "  サブネット削除: ${subnet_id}"
  done

  # カスタムルートテーブルのルート削除 → ルートテーブル削除
  RT_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
    --output text 2>/dev/null || true)
  for rt_id in ${RT_IDS}; do
    aws ec2 delete-route-table --route-table-id "${rt_id}" > /dev/null 2>&1 || true
    echo "  ルートテーブル削除: ${rt_id}"
  done

  # メインルートテーブルのIGWルート削除
  MAIN_RT=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[?Associations[0].Main==`true`].RouteTableId' \
    --output text 2>/dev/null || true)
  if [[ -n "${MAIN_RT}" && "${MAIN_RT}" != "None" ]]; then
    aws ec2 delete-route \
      --route-table-id "${MAIN_RT}" \
      --destination-cidr-block 0.0.0.0/0 > /dev/null 2>&1 || true
    echo "  IGWルート削除: ${MAIN_RT}"
  fi

  # IGWデタッチ・削除
  IGW_IDS=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || true)
  for igw_id in ${IGW_IDS}; do
    aws ec2 detach-internet-gateway \
      --internet-gateway-id "${igw_id}" --vpc-id "${VPC_ID}" > /dev/null 2>&1 || true
    aws ec2 delete-internet-gateway --internet-gateway-id "${igw_id}" > /dev/null 2>&1 || true
    echo "  IGW削除: ${igw_id}"
  done

  # VPC削除
  aws ec2 delete-vpc --vpc-id "${VPC_ID}" || true
  echo "VPC削除: ${VPC_NAME} (${VPC_ID})"
fi

################################################################################
# 11. IAMロール・ユーザー
################################################################################
echo ""
echo "--- 11. IAM ---"

# 汎用: インラインポリシー・管理ポリシーをすべて外してロール削除
_delete_role() {
  local role_name="$1"
  if ! aws iam get-role --role-name "${role_name}" > /dev/null 2>&1; then
    echo "スキップ: IAMロール ${role_name} は存在しません"
    return 0
  fi
  # 管理ポリシーをデタッチ
  local attached
  attached=$(aws iam list-attached-role-policies --role-name "${role_name}" \
    --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
  for arn in ${attached}; do
    aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${arn}" || true
  done
  # インラインポリシーを削除
  local inline
  inline=$(aws iam list-role-policies --role-name "${role_name}" \
    --query 'PolicyNames[]' --output text 2>/dev/null || true)
  for pol in ${inline}; do
    aws iam delete-role-policy --role-name "${role_name}" --policy-name "${pol}" || true
  done
  aws iam delete-role --role-name "${role_name}" || true
  echo "IAMロール削除: ${role_name}"
}

# Lambda terminator ロール（インスタンスプロファイルなし）
_delete_role "${PRJ_PREFIX}-role-lambda-020"

# Lambda 起動ロール（インスタンスプロファイルなし）
_delete_role "${IAM_ROLE_LAMBDA_NAME}"

# EC2 ロール（インスタンスプロファイルあり）
if aws iam get-role --role-name "${IAM_ROLE_EC2_NAME}" > /dev/null 2>&1; then
  aws iam remove-role-from-instance-profile \
    --instance-profile-name "${IAM_ROLE_EC2_NAME}" \
    --role-name "${IAM_ROLE_EC2_NAME}" > /dev/null 2>&1 || true
  aws iam delete-instance-profile \
    --instance-profile-name "${IAM_ROLE_EC2_NAME}" > /dev/null 2>&1 || true
  _delete_role "${IAM_ROLE_EC2_NAME}"
else
  echo "スキップ: IAMロール ${IAM_ROLE_EC2_NAME} は存在しません"
fi

# Build・Exec ロール
_delete_role "${IAM_ROLE_BUILD_NAME}"
_delete_role "${IAM_ROLE_EXEC_NAME}"

# IAMユーザー
if aws iam get-user --user-name "${IAM_USER_NAME}" > /dev/null 2>&1; then
  # アクセスキーをすべて削除
  KEY_IDS=$(aws iam list-access-keys --user-name "${IAM_USER_NAME}" \
    --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || true)
  for key_id in ${KEY_IDS}; do
    aws iam delete-access-key --user-name "${IAM_USER_NAME}" --access-key-id "${key_id}" || true
  done
  # インラインポリシーを削除
  INLINE=$(aws iam list-user-policies --user-name "${IAM_USER_NAME}" \
    --query 'PolicyNames[]' --output text 2>/dev/null || true)
  for pol in ${INLINE}; do
    aws iam delete-user-policy --user-name "${IAM_USER_NAME}" --policy-name "${pol}" || true
  done
  aws iam delete-user --user-name "${IAM_USER_NAME}" || true
  echo "IAMユーザー削除: ${IAM_USER_NAME}"
else
  echo "スキップ: IAMユーザー ${IAM_USER_NAME} は存在しません"
fi

################################################################################
echo ""
echo "============================================================"
echo "全リソース削除完了: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo "注意: ~/.aws/credentials の [default] プロファイルは手動で更新してください"
