#!/usr/bin/env bash
################################################################################
# スクリプト名: info-all.sh
# 概要        : このプロジェクト（ts-010）で作成した全AWSリソースの情報を出力する
#                同一インフラの証明・削除前バックアップ・構築確認チェックリストの補助として使用する
#                再構築後に本スクリプトの出力を比較することで、インフラの同一性を確認できる
# 使用方法    : AWS_PROFILE=ts-usr-admin ./info-all.sh [--save]
#               --save : 結果をファイルにも保存する（info-all.sh.YYYYMMDD_HHMMSS.log）
# 注意        : ts-usr-admin プロファイル、または assume-role.sh source 後に実行すること
# Created     : 2026-03-24
# Last updated: 2026-03-25 00:00:00
# Author      : Tsystem
# 更新履歴    :
#    2026-03-24: 初版
#    2026-03-24: 同一インフラ証明用に不足情報を追記
#                （VPC DNS設定、サブネットPublicIP設定、ルートテーブル関連付け、
#                  SG egress/ingressルール詳細、S3暗号化・バージョニング、
#                  Lambdaコードハッシュ・環境変数、IAM信頼ポリシー・インラインポリシー内容、
#                  IAMインスタンスプロファイル、CloudWatchメトリクスフィルタ、CloudTrail）
#    2026-03-25: リソース未存在と取得失敗のエラー切り分けを改善（_aws_run/_aws_json 追加）
################################################################################
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)  # スクリプト自身のディレクトリ
source "${SCRIPT_DIR}/config.sh"            # プロジェクト共通設定

readonly SAVE_FLAG="${1:-}"                                             # --save オプション
readonly TIMESTAMP=$(date '+%Y%m%d_%H%M%S')                           # 実行日時
readonly LOG_FILE="${SCRIPT_DIR}/info-all.sh.${TIMESTAMP}.log"        # 保存先ログファイル

# --save オプション時はファイルにも出力
if [[ "${SAVE_FLAG}" == "--save" ]]; then
  exec > >(tee "${LOG_FILE}") 2>&1
  echo "出力先: ${LOG_FILE}"
fi

# ------------------------------------------------------------------------------
# 関数名   : section
# 概要     : セクション区切り見出しを出力する
# 引数     : $1 - セクション番号と名称
# 戻り値   : なし
# ------------------------------------------------------------------------------
section() {
  local title="$1"  # セクションタイトル
  echo ""
  echo "############################################################"
  echo "# ${title}"
  echo "############################################################"
}

# ------------------------------------------------------------------------------
# 関数名   : subsection
# 概要     : サブセクション区切り見出しを出力する
# 引数     : $1 - サブセクション名称
# 戻り値   : なし
# ------------------------------------------------------------------------------
subsection() {
  local title="$1"  # サブセクションタイトル
  echo ""
  echo "--- ${title} ---"
}

# リソース未存在と判定するAWS CLIエラーパターン
readonly _NOT_FOUND_PAT='NoSuchBucket|NoSuchEntity|NoSuchKey|ResourceNotFoundException|NotFoundException|NotFound|does not exist|NonExistentQueue|InvalidKeyPair\.NotFound|InvalidGroup\.NotFound|InvalidVpcID\.NotFound|InvalidSubnetID\.NotFound|InvalidRouteTableID\.NotFound|InvalidInternetGatewayID\.NotFound'

# ------------------------------------------------------------------------------
# 関数名   : _aws_run
# 概要     : AWS CLI コマンドを実行し、正常取得・未存在・取得失敗を切り分けて出力する
#            リソース未存在と取得失敗（権限不足・ネットワークエラー等）を区別するために使用する
# 引数     : $@ - aws コマンドに渡す引数（"aws" は含まない）
# 出力     : 正常取得時       → AWS CLI の出力をそのまま表示
#            リソース未存在時 → "（未存在）"
#            取得失敗時       → "（取得失敗: <エラーコード>）"
# 戻り値   : 0（常に）
# ------------------------------------------------------------------------------
_aws_run() {
  local _err_file _out _rc _err _brief
  _err_file=$(mktemp)                        # stderr 受け取り用一時ファイル
  _out=$(aws "$@" 2>"${_err_file}")          # AWS CLI 実行
  _rc=$?
  _err=$(<"${_err_file}")
  rm -f "${_err_file}"

  if [[ ${_rc} -eq 0 ]]; then
    echo "${_out}"                           # 正常取得
    return 0
  fi

  # エラーメッセージからリソース未存在かどうかを判定
  if echo "${_err}" | grep -qiE "${_NOT_FOUND_PAT}"; then
    echo "（未存在）"
  else
    # エラーコード部分（括弧内）を抽出して簡潔に表示
    _brief=$(echo "${_err}" | grep -oP '\(\K[^)]+' | head -1 || true)
    [[ -z "${_brief}" ]] && _brief=$(echo "${_err}" | tr -s '\n' ' ' | cut -c1-120)
    echo "（取得失敗: ${_brief}）"
  fi
  return 0
}

# ------------------------------------------------------------------------------
# 関数名   : _aws_json
# 概要     : _aws_run を実行し、正常取得時は JSON 整形して出力する
#            エラー時（未存在・取得失敗）は _aws_run と同じメッセージをそのまま表示する
# 引数     : $@ - aws コマンドに渡す引数（"aws" と "--output json" は含まない）
# 出力     : 正常取得時       → python3 で整形した JSON
#            リソース未存在時 → "（未存在）"
#            取得失敗時       → "（取得失敗: <エラーコード>）"
# 戻り値   : 0（常に）
# ------------------------------------------------------------------------------
_aws_json() {
  local _result
  _result=$(_aws_run "$@" --output json)
  # 全角括弧始まりはエラーメッセージ → そのまま出力
  if [[ "${_result}" == （* ]]; then
    echo "${_result}"
  else
    echo "${_result}" | python3 -m json.tool 2>/dev/null || echo "${_result}"
  fi
  return 0
}

# ------------------------------------------------------------------------------
# 関数名   : info_iam_role
# 概要     : 指定IAMロールの全ポリシー情報（信頼ポリシー・管理ポリシー・インラインポリシー内容）を出力する
#            同一インフラ証明において最重要。ポリシー内容が一致することで権限設定の同一性を確認できる
# 引数     : $1 - IAMロール名
# 戻り値   : なし
# ------------------------------------------------------------------------------
info_iam_role() {
  local role="$1"  # 対象IAMロール名

  # ロールの存在確認（未存在と取得失敗を区別）
  local _chk
  _chk=$(_aws_run iam get-role --role-name "${role}" \
    --query 'Role.RoleName' --output text)
  if [[ "${_chk}" == （* ]]; then
    echo "  ${_chk}"
    return 0
  fi

  # 信頼ポリシー（AssumeRolePolicyDocument）
  # どのサービス・アカウントがこのロールを引き受けられるかを定義する
  echo "  [信頼ポリシー（AssumeRolePolicyDocument）]"
  _aws_json iam get-role --role-name "${role}" \
    --query 'Role.AssumeRolePolicyDocument'

  # 管理ポリシー一覧（AWSマネージドポリシーのアタッチ状況）
  echo "  [管理ポリシー（AttachedPolicies）]"
  _aws_run iam list-attached-role-policies --role-name "${role}" \
    --query 'AttachedPolicies[].{PolicyName:PolicyName,PolicyArn:PolicyArn}' \
    --output table

  # インラインポリシー内容（カスタム権限の詳細）
  # mk-role-*.sh で定義した具体的な Allow/Deny 権限が記載されている
  echo "  [インラインポリシー内容（PolicyDocument）]"
  local policy_names
  policy_names=$(_aws_run iam list-role-policies --role-name "${role}" \
    --query 'PolicyNames[]' --output text)

  if [[ "${policy_names}" == （* ]]; then
    echo "  ${policy_names}"
  elif [[ -z "${policy_names}" || "${policy_names}" == "None" ]]; then
    echo "  （インラインポリシーなし）"
  else
    for pol_name in ${policy_names}; do
      echo "  ポリシー名: ${pol_name}"
      _aws_json iam get-role-policy \
        --role-name "${role}" \
        --policy-name "${pol_name}" \
        --query 'PolicyDocument'
    done
  fi
}

echo "============================================================"
echo "リソース情報出力開始: $(date '+%Y-%m-%d %H:%M:%S')"
echo "プロジェクト: ${PRJ_PREFIX}  リージョン: ${AWS_REGION}"
echo "============================================================"

################################################################################
# 1. EC2
# EC2インスタンスの起動設定・状態を確認する
# mk-ec2-with-ssh.sh が作成するSSH接続用テストインスタンスが対象
################################################################################
section "1. EC2"

# インスタンス一覧と基本情報
# 同一性確認ポイント: インスタンスタイプ・AZ・AMI・タグ名
subsection "インスタンス（起動状態・インスタンスタイプ・AZ・AMI・IPアドレス）"
_aws_run ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PRJ_PREFIX}-*" \
  --query 'Reservations[].Instances[].{
    Name:Tags[?Key==`Name`].Value|[0],
    InstanceId:InstanceId,
    State:State.Name,
    Type:InstanceType,
    AZ:Placement.AvailabilityZone,
    PublicIP:PublicIpAddress,
    PrivateIP:PrivateIpAddress,
    ImageId:ImageId,
    LaunchTime:LaunchTime
  }' \
  --output table

# 自作AMI（存在する場合のみ）
subsection "AMI（自作のみ）"
_aws_run ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=${PRJ_PREFIX}-*" \
  --query 'Images[].{Name:Name,ImageId:ImageId,State:State,CreationDate:CreationDate}' \
  --output table

# キーペア
# 同一性確認ポイント: キー名・タイプ（rsa/ed25519）
# 注意: 秘密鍵は作成時にしか取得できないため、KeyPairIdとTypeのみ比較可能
subsection "キーペア（キー名・キータイプ・作成日時）"
_aws_run ec2 describe-key-pairs \
  --filters "Name=key-name,Values=${PRJ_PREFIX}-*" \
  --query 'KeyPairs[].{Name:KeyName,KeyPairId:KeyPairId,Type:KeyType,CreatedDate:CreateTime}' \
  --output table

################################################################################
# 2. ネットワーク
# VPC・IGW・サブネット・ルートテーブル・SGの構成を確認する
# mk-vpc.sh / mk-igw.sh / mk-subnet.sh / mk-route-table.sh / mk-sg.sh / mk-sg-ssh.sh が対象
################################################################################
section "2. ネットワーク"

# VPC基本情報とDNS設定
# 同一性確認ポイント: CIDRブロック・DNS設定（mk-vpc.sh が EnableDnsHostnames/Support を有効化）
subsection "VPC（CIDRブロック・状態）"
_aws_run ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PRJ_PREFIX}-*" \
  --query 'Vpcs[].{
    Name:Tags[?Key==`Name`].Value|[0],
    VpcId:VpcId,
    CidrBlock:CidrBlock,
    State:State
  }' \
  --output table

# VPC DNS設定（mk-vpc.sh が有効化する設定）
# enableDnsHostnames: EC2にパブリックDNSホスト名を付与するか
# enableDnsSupport  : AmazonのDNSサーバーを使用するか
VPC_ID=$(_aws_run ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query 'Vpcs[0].VpcId' --output text)

if [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" && "${VPC_ID}" != （* ]]; then
  subsection "VPC DNS設定（enableDnsHostnames / enableDnsSupport）"
  echo "  enableDnsHostnames（EC2パブリックDNSホスト名付与）:"
  _aws_run ec2 describe-vpc-attribute \
    --vpc-id "${VPC_ID}" \
    --attribute enableDnsHostnames \
    --query 'EnableDnsHostnames' \
    --output table
  echo "  enableDnsSupport（AmazonDNSサーバー使用）:"
  _aws_run ec2 describe-vpc-attribute \
    --vpc-id "${VPC_ID}" \
    --attribute enableDnsSupport \
    --query 'EnableDnsSupport' \
    --output table
elif [[ "${VPC_ID}" == （* ]]; then
  subsection "VPC DNS設定（enableDnsHostnames / enableDnsSupport）"
  echo "  ${VPC_ID}"
fi

# インターネットゲートウェイ
# 同一性確認ポイント: VPCへのアタッチ状態
subsection "インターネットゲートウェイ（IGW ID・VPCアタッチ状態）"
_aws_run ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=${PRJ_PREFIX}-*" \
  --query 'InternetGateways[].{
    Name:Tags[?Key==`Name`].Value|[0],
    IgwId:InternetGatewayId,
    VpcId:Attachments[0].VpcId,
    State:Attachments[0].State
  }' \
  --output table

# サブネット
# 同一性確認ポイント: CIDRブロック・AZ・MapPublicIpOnLaunch（mk-subnet.sh が有効化）
# MapPublicIpOnLaunch: EC2起動時にパブリックIPを自動割り当てするか
subsection "サブネット（CIDRブロック・AZ・パブリックIP自動割当設定）"
_aws_run ec2 describe-subnets \
  --filters "Name=tag:Name,Values=${PRJ_PREFIX}-*" \
  --query 'Subnets[].{
    Name:Tags[?Key==`Name`].Value|[0],
    SubnetId:SubnetId,
    CidrBlock:CidrBlock,
    AZ:AvailabilityZone,
    State:State,
    MapPublicIpOnLaunch:MapPublicIpOnLaunch,
    AvailableIPs:AvailableIpAddressCount
  }' \
  --output table

# ルートテーブル
# 同一性確認ポイント: ルートエントリ（宛先CIDR・ターゲットIGW）・サブネット関連付け
subsection "ルートテーブル（ルートエントリ・サブネット関連付け）"
if [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" && "${VPC_ID}" != （* ]]; then
  # ルートテーブル基本情報
  _aws_run ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[].{
      RouteTableId:RouteTableId,
      VpcId:VpcId,
      Name:Tags[?Key==`Name`].Value|[0]
    }' \
    --output table

  # ルートエントリ詳細（0.0.0.0/0 → IGW のルートが存在することを確認）
  echo "  [ルートエントリ（宛先CIDR・ターゲット・状態）]"
  _aws_run ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[].Routes[].{
      Destination:DestinationCidrBlock,
      Target:GatewayId,
      State:State
    }' \
    --output table

  # サブネット関連付け（mk-route-table.sh が関連付けを行う）
  echo "  [サブネット関連付け（RouteTableId・SubnetId・Main）]"
  _aws_run ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[].Associations[].{
      RouteTableId:RouteTableId,
      SubnetId:SubnetId,
      Main:Main,
      AssociationId:RouteTableAssociationId
    }' \
    --output table
else
  echo "  （VPC未存在のためスキップ）"
fi

# セキュリティグループ
# 同一性確認ポイント: ingress/egress の全ルール（プロトコル・ポート・CIDR）
# mk-sg.sh がアウトバウンドルールを設定、mk-sg-ssh.sh がSSHインバウンドを追加
subsection "セキュリティグループ（グループ情報・ルール件数）"
_aws_run ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PRJ_PREFIX}-*" \
  --query 'SecurityGroups[].{
    Name:GroupName,
    GroupId:GroupId,
    VpcId:VpcId,
    Description:Description,
    IngressRules:length(IpPermissions),
    EgressRules:length(IpPermissionsEgress)
  }' \
  --output table

# SGルール詳細（inbound/outbound 両方）
SG_ID=$(_aws_run ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [[ -n "${SG_ID}" && "${SG_ID}" != "None" && "${SG_ID}" != （* ]]; then
  # インバウンドルール詳細（mk-sg-ssh.sh が追加するSSHルール等）
  echo "  [インバウンドルール詳細（プロトコル・ポート範囲・CIDR）]"
  _aws_run ec2 describe-security-groups \
    --group-ids "${SG_ID}" \
    --query 'SecurityGroups[0].IpPermissions[].{
      Protocol:IpProtocol,
      FromPort:FromPort,
      ToPort:ToPort,
      CIDR:IpRanges[0].CidrIp,
      Description:IpRanges[0].Description
    }' \
    --output table

  # アウトバウンドルール詳細（mk-sg.sh が設定するルール）
  echo "  [アウトバウンドルール詳細（プロトコル・ポート範囲・CIDR）]"
  _aws_run ec2 describe-security-groups \
    --group-ids "${SG_ID}" \
    --query 'SecurityGroups[0].IpPermissionsEgress[].{
      Protocol:IpProtocol,
      FromPort:FromPort,
      ToPort:ToPort,
      CIDR:IpRanges[0].CidrIp,
      Description:IpRanges[0].Description
    }' \
    --output table
elif [[ "${SG_ID}" == （* ]]; then
  echo "  ${SG_ID}"
fi

################################################################################
# 3. S3
# バケットの設定・ポリシー・ライフサイクル・暗号化を確認する
# mk-s3bkt.sh / mk-s3bktpolicy.sh / mk-s3-lifecicle.sh / mk-s3-trigger.sh が対象
################################################################################
section "3. S3"

# バケット一覧
subsection "バケット一覧（バケット名・作成日時）"
_aws_run s3api list-buckets \
  --query 'Buckets[?starts_with(Name,`ts-010`)].{Name:Name,CreationDate:CreationDate}' \
  --output table

# 各バケットの詳細情報
# ${BKT_IN} / ${BKT_OUT} : mk-s3bkt.sh が作成するメインバケット
# ${BKT_CLOUDTRAIL}     : set-cloud-trail.sh が使用するCloudTrailログバケット
for bucket in "${S3_BKT_IN_NAME}" "${S3_BKT_OUT_NAME}" "${PRJ_PREFIX}-bkt-cloudtrail-logs"; do
  subsection "バケット詳細: ${bucket}"

  # バケットの存在確認（未存在と取得失敗を区別）
  local_chk=$(_aws_run s3api head-bucket --bucket "${bucket}")
  if [[ "${local_chk}" == （* ]]; then
    echo "  ${local_chk}"
    continue
  fi

  # オブジェクト数・サイズ（参考情報）
  echo "  [オブジェクト数・サイズ（参考）]"
  local_ls=$(_aws_run s3 ls "s3://${bucket}" --recursive --human-readable --summarize)
  if [[ "${local_ls}" == （* ]]; then
    echo "  ${local_ls}"
  else
    echo "${local_ls}" | tail -2 || echo "  （オブジェクトなし）"
  fi

  # バージョニング設定（mk-s3bkt.sh が有効化する場合の確認）
  # Enabled: バージョン管理有効 / Suspended: 一時停止 / （空白）: 未設定
  echo "  [バージョニング設定（Enabled / Suspended / 未設定）]"
  _aws_json s3api get-bucket-versioning \
    --bucket "${bucket}"

  # サーバーサイド暗号化設定（mk-s3bkt.sh が SSE-S3 または SSE-KMS を設定）
  # 同一性確認ポイント: 暗号化アルゴリズム・KMSキーARN
  echo "  [サーバーサイド暗号化設定（SSEアルゴリズム）]"
  _aws_run s3api get-bucket-encryption \
    --bucket "${bucket}" \
    --query 'ServerSideEncryptionConfiguration.Rules[].ApplyServerSideEncryptionByDefault.{Algorithm:SSEAlgorithm,KMSKeyId:KMSMasterKeyID}' \
    --output table

  # パブリックアクセスブロック設定（mk-s3bkt.sh が全ブロックを有効化）
  # 同一性確認ポイント: 4項目すべて true であること
  echo "  [パブリックアクセスブロック設定（全項目 true が期待値）]"
  _aws_run s3api get-public-access-block \
    --bucket "${bucket}" \
    --query 'PublicAccessBlockConfiguration' \
    --output table

  # ライフサイクルルール（mk-s3-lifecicle.sh が設定する有効期限）
  # 同一性確認ポイント: 有効期限日数・ルールID・Status
  echo "  [ライフサイクルルール（有効期限日数・Status）]"
  _aws_run s3api get-bucket-lifecycle-configuration \
    --bucket "${bucket}" \
    --query 'Rules[].{Id:ID,Status:Status,ExpirationDays:Expiration.Days,Prefix:Filter.Prefix}' \
    --output table

  # バケットポリシー（mk-s3bktpolicy.sh が設定するアクセス制御）
  # 同一性確認ポイント: Principal（IAMロール）・Action・Resource・Effect
  echo "  [バケットポリシー（Principal・Action・Effect）]"
  local_policy=$(_aws_run s3api get-bucket-policy \
    --bucket "${bucket}" \
    --query 'Policy' --output text)
  if [[ "${local_policy}" == （* ]]; then
    echo "  ${local_policy}"
  else
    echo "${local_policy}" | python3 -m json.tool 2>/dev/null || echo "${local_policy}"
  fi

  # S3トリガー設定（mk-s3-trigger.sh が設定するLambda通知）
  # 同一性確認ポイント: Lambda ARN・トリガーイベント種別
  echo "  [S3イベント通知設定（Lambda ARN・トリガーイベント）]"
  _aws_run s3api get-bucket-notification-configuration \
    --bucket "${bucket}" \
    --query 'LambdaFunctionConfigurations[].{LambdaArn:LambdaFunctionArn,Events:Events,FilterRules:Filter.Key.FilterRules}' \
    --output table
done

################################################################################
# 4. Lambda
# Lambda関数の設定・コード同一性・トリガーを確認する
# mk-lambda.sh / mk-lambda-terminator.sh / mk-role-lambda-010.sh が対象
################################################################################
section "4. Lambda"

# 関数一覧
subsection "Lambda関数一覧（関数名・ランタイム・タイムアウト・メモリ）"
_aws_run lambda list-functions \
  --query 'Functions[?starts_with(FunctionName,`ts-010`)].{
    Name:FunctionName,
    Runtime:Runtime,
    State:State,
    Handler:Handler,
    Timeout:Timeout,
    MemorySize:MemorySize,
    LastModified:LastModified
  }' \
  --output table

# 各Lambda関数の詳細
for func in "${LAMBDA_FUNC_NAME}" "${PRJ_PREFIX}-lmd-020"; do
  subsection "Lambda詳細: ${func}"

  # 関数の存在確認（未存在と取得失敗を区別）
  local_chk=$(_aws_run lambda get-function \
    --function-name "${func}" \
    --query 'Configuration.FunctionName' --output text)
  if [[ "${local_chk}" == （* ]]; then
    echo "  ${local_chk}"
    continue
  fi

  # 関数設定（ランタイム・ハンドラ・タイムアウト・メモリ・IAMロール）
  # 同一性確認ポイント: Runtime・Handler・Timeout・MemorySize・Role ARN
  echo "  [関数設定（Runtime・Handler・Timeout・MemorySize・Role）]"
  _aws_run lambda get-function \
    --function-name "${func}" \
    --query 'Configuration.{
      Name:FunctionName,
      State:State,
      Role:Role,
      Handler:Handler,
      Runtime:Runtime,
      Timeout:Timeout,
      MemorySize:MemorySize,
      LastModified:LastModified,
      CodeSize:CodeSize
    }' \
    --output table

  # コードハッシュ（デプロイ済みコードの同一性を確認するSHA256ハッシュ）
  # 同一性確認ポイント: 再デプロイ後にこの値が一致すること
  echo "  [コードSHA256ハッシュ（同一コードの証明）]"
  _aws_run lambda get-function \
    --function-name "${func}" \
    --query 'Configuration.CodeSha256' \
    --output text

  # 環境変数（設定されている場合）
  echo "  [環境変数（Variables）]"
  _aws_run lambda get-function-configuration \
    --function-name "${func}" \
    --query 'Environment.Variables' \
    --output table

  # トリガー（イベントソースマッピング）
  echo "  [イベントソースマッピング（トリガー）]"
  _aws_run lambda list-event-source-mappings \
    --function-name "${func}" \
    --query 'EventSourceMappings[].{EventSourceArn:EventSourceArn,State:State,BatchSize:BatchSize}' \
    --output table

  # リソースベースポリシー（mk-s3-trigger.sh が S3からの呼び出し許可を追加）
  # 同一性確認ポイント: Principal（s3.amazonaws.com）・SourceArn（入力バケット）
  echo "  [リソースベースポリシー（呼び出し元サービスの許可設定）]"
  local_policy=$(_aws_run lambda get-policy \
    --function-name "${func}" \
    --query 'Policy' --output text)
  if [[ "${local_policy}" == （* ]]; then
    echo "  ${local_policy}"
  else
    echo "${local_policy}" | python3 -m json.tool 2>/dev/null || echo "${local_policy}"
  fi
done

################################################################################
# 5. IAM
# IAMロール・ユーザーの権限設定を確認する
# mk-role-build.sh / mk-role-exec.sh / mk-role-lambda-010.sh / mk-role-ec2-010.sh /
# mk-lambda-terminator.sh / mk-iam-user.sh が対象
# 【重要】インラインポリシーの内容が同一であることが、同一インフラ証明の核心
################################################################################
section "5. IAM"

# ロール一覧
subsection "IAMロール一覧（ロール名・RoleId・作成日時）"
_aws_run iam list-roles \
  --query 'Roles[?starts_with(RoleName,`ts-010`)].{
    Name:RoleName,
    RoleId:RoleId,
    Created:CreateDate
  }' \
  --output table

# 各ロールの詳細（信頼ポリシー・管理ポリシー・インラインポリシー内容）
for role in \
  "${IAM_ROLE_BUILD_NAME}" \
  "${IAM_ROLE_EXEC_NAME}" \
  "${IAM_ROLE_LAMBDA_NAME}" \
  "${IAM_ROLE_EC2_NAME}" \
  "${PRJ_PREFIX}-role-lambda-020"
do
  subsection "IAMロール詳細: ${role}（信頼ポリシー・管理ポリシー・インラインポリシー内容）"
  info_iam_role "${role}"
done

# EC2用インスタンスプロファイル（mk-role-ec2-010.sh が作成・関連付け）
# 同一性確認ポイント: インスタンスプロファイル名・関連付けられたロール名
subsection "IAMインスタンスプロファイル（EC2用ロール割り当て確認）"
_aws_run iam list-instance-profiles-for-role \
  --role-name "${IAM_ROLE_EC2_NAME}" \
  --query 'InstanceProfiles[].{
    ProfileName:InstanceProfileName,
    ProfileId:InstanceProfileId,
    Created:CreateDate,
    Roles:Roles[].RoleName
  }' \
  --output table

# IAMユーザー
subsection "IAMユーザー（ユーザー名・UserId・作成日時）"
_aws_run iam list-users \
  --query 'Users[?starts_with(UserName,`ts-010`)].{
    Name:UserName,
    UserId:UserId,
    Created:CreateDate
  }' \
  --output table

# ユーザー詳細（存在する場合のみ）
user_chk=$(_aws_run iam get-user --user-name "${IAM_USER_NAME}" \
  --query 'User.UserName' --output text)
if [[ "${user_chk}" != （* && -n "${user_chk}" && "${user_chk}" != "None" ]]; then
  # アクセスキー一覧（キーID・ステータス・作成日時）
  echo "  [アクセスキー（KeyId・Status・作成日時）]"
  _aws_run iam list-access-keys \
    --user-name "${IAM_USER_NAME}" \
    --query 'AccessKeyMetadata[].{KeyId:AccessKeyId,Status:Status,Created:CreateDate}' \
    --output table

  # ユーザーに直接アタッチされた管理ポリシー
  echo "  [ユーザー管理ポリシー（AttachedPolicies）]"
  _aws_run iam list-attached-user-policies \
    --user-name "${IAM_USER_NAME}" \
    --query 'AttachedPolicies[].{PolicyName:PolicyName,PolicyArn:PolicyArn}' \
    --output table

  # ユーザーインラインポリシー（存在する場合）
  echo "  [ユーザーインラインポリシー（PolicyDocument）]"
  local_user_inline=$(_aws_run iam list-user-policies \
    --user-name "${IAM_USER_NAME}" \
    --query 'PolicyNames[]' --output text)
  if [[ "${local_user_inline}" == （* ]]; then
    echo "  ${local_user_inline}"
  elif [[ -z "${local_user_inline}" || "${local_user_inline}" == "None" ]]; then
    echo "  （インラインポリシーなし）"
  else
    for pol_name in ${local_user_inline}; do
      echo "  ポリシー名: ${pol_name}"
      _aws_json iam get-user-policy \
        --user-name "${IAM_USER_NAME}" \
        --policy-name "${pol_name}" \
        --query 'PolicyDocument'
    done
  fi
elif [[ "${user_chk}" == （* ]]; then
  echo "  ${user_chk}"
fi

################################################################################
# 6. SNS
# SNSトピックとサブスクリプション設定を確認する
# mk-sns-topic.sh / set-sms-subscription.sh / set-email-subscription.sh が対象
################################################################################
section "6. SNS"

# トピック情報とサブスクリプション
# 同一性確認ポイント: トピック名・サブスクリプションのProtocol・Endpoint・確認状態
subsection "SNSトピック（TopicArn・サブスクリプション一覧）"
TOPIC_ARN=$(_aws_run sns list-topics \
  --query "Topics[?contains(TopicArn,'${SNS_TOPIC_NAME}')].TopicArn" \
  --output text)

if [[ "${TOPIC_ARN}" == （* ]]; then
  echo "  ${TOPIC_ARN}"
elif [[ -n "${TOPIC_ARN}" && "${TOPIC_ARN}" != "None" ]]; then
  echo "  TopicArn: ${TOPIC_ARN}"

  # トピック属性（配信ポリシー等）
  echo "  [トピック属性（表示名・配信ポリシー）]"
  _aws_run sns get-topic-attributes \
    --topic-arn "${TOPIC_ARN}" \
    --query 'Attributes.{DisplayName:DisplayName,Policy:Policy}' \
    --output table

  # サブスクリプション一覧（通知先・プロトコル・確認状態）
  echo "  [サブスクリプション（Protocol・Endpoint・Status）]"
  _aws_run sns list-subscriptions-by-topic \
    --topic-arn "${TOPIC_ARN}" \
    --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,SubscriptionArn:SubscriptionArn}' \
    --output table
else
  echo "（トピック未存在）"
fi

################################################################################
# 7. CloudWatch
# ロググループの設定とメトリクスフィルタを確認する
# mk-cloudwatch.sh が対象
################################################################################
section "7. CloudWatch"

# ロググループ一覧
# 同一性確認ポイント: ロググループ名・保持期間（RetentionDays）
# ts-010-log-* : mk-cloudwatch.sh が作成するカスタムロググループ
# /aws/lambda/ts-010-* : Lambda 実行時に AWS が自動作成するロググループ
subsection "ロググループ（グループ名・保持期間・蓄積サイズ）"
_aws_run logs describe-log-groups \
  --log-group-name-prefix "${PRJ_PREFIX}-log" \
  --query 'logGroups[].{
    Name:logGroupName,
    RetentionDays:retentionInDays,
    StoredBytes:storedBytes,
    CreatedAt:creationTime
  }' \
  --output table

# Lambda 実行時に AWS が自動作成するロググループ（/aws/lambda/<関数名>）
# mk-cloudwatch.sh の対象外だが、Lambda 関数に紐付くリソースとして確認が必要
subsection "Lambda自動作成ロググループ（/aws/lambda/ts-010-*）"
_aws_run logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/${PRJ_PREFIX}" \
  --query 'logGroups[].{
    Name:logGroupName,
    RetentionDays:retentionInDays,
    StoredBytes:storedBytes,
    CreatedAt:creationTime
  }' \
  --output table

# 各ロググループのメトリクスフィルタ（mk-cloudwatch.sh が設定する場合）
# 同一性確認ポイント: フィルタパターン・メトリクス名・名前空間
subsection "メトリクスフィルタ（フィルタパターン・メトリクス名）"
for lg in "${CW_LOG_GROUP_LAMBDA_NAME}" "${CW_LOG_GROUP_EC2_NAME}" "${CW_LOG_GROUP_SYSTEM_NAME}"; do
  echo "  ロググループ: ${lg}"
  _aws_run logs describe-metric-filters \
    --log-group-name "${lg}" \
    --query 'metricFilters[].{
      FilterName:filterName,
      FilterPattern:filterPattern,
      MetricName:metricTransformations[0].metricName,
      Namespace:metricTransformations[0].metricNamespace
    }' \
    --output table
done

# CloudWatch アラーム（mk-cloudwatch.sh がメトリクスフィルタに対して設定）
# 同一性確認ポイント: アラーム名・対象メトリクス・閾値・アクション（SNS通知先）
subsection "CloudWatch アラーム（アラーム名・メトリクス・状態）"
_aws_run cloudwatch describe-alarms \
  --query "MetricAlarms[?starts_with(AlarmName,'${PRJ_PREFIX}')].{
    Name:AlarmName,
    Metric:MetricName,
    Namespace:Namespace,
    Threshold:Threshold,
    ComparisonOperator:ComparisonOperator,
    State:StateValue,
    Actions:AlarmActions
  }" \
  --output table

################################################################################
# 8. EventBridge
# EventBridgeルールとターゲット設定を確認する
# mk-eventbridge-rule.sh が対象
################################################################################
section "8. EventBridge"

# ルール設定
# 同一性確認ポイント: イベントパターン（EC2停止イベント）・State（ENABLED）
RULE_NAME="${PRJ_PREFIX}-rule-stop-ec2-trigger"  # EventBridgeルール名

subsection "EventBridgeルール（イベントパターン・State）"
_aws_run events describe-rule \
  --name "${RULE_NAME}" \
  --query '{
    Name:Name,
    State:State,
    ScheduleExpression:ScheduleExpression,
    EventPattern:EventPattern,
    Description:Description
  }' \
  --output table

# ターゲット設定（ルールが発火したときに呼び出すLambda関数）
# 同一性確認ポイント: ターゲットARN（Lambda関数）
subsection "EventBridgeターゲット（ターゲットARN・ID）"
_aws_run events list-targets-by-rule \
  --rule "${RULE_NAME}" \
  --query 'Targets[].{Id:Id,Arn:Arn,Input:Input}' \
  --output table

################################################################################
# 9. CloudTrail
# CloudTrailの証跡設定を確認する
# set-cloud-trail.sh が対象
################################################################################
section "9. CloudTrail"

# 証跡一覧
# 同一性確認ポイント: 証跡名・S3バケット名・マルチリージョン設定
subsection "証跡一覧（証跡名・S3バケット・マルチリージョン設定）"
_aws_run cloudtrail describe-trails \
  --query "trailList[?contains(Name,'${PRJ_PREFIX}') || contains(S3BucketName,'${PRJ_PREFIX}')].{
    Name:Name,
    S3BucketName:S3BucketName,
    IsMultiRegionTrail:IsMultiRegionTrail,
    IncludeGlobalServiceEvents:IncludeGlobalServiceEvents,
    HomeRegion:HomeRegion
  }" \
  --output table

# 証跡のステータス（記録中かどうか）
TRAIL_NAME=$(_aws_run cloudtrail describe-trails \
  --query "trailList[?contains(S3BucketName,'${PRJ_PREFIX}')].Name" \
  --output text)

if [[ "${TRAIL_NAME}" == （* ]]; then
  echo "  ${TRAIL_NAME}"
elif [[ -n "${TRAIL_NAME}" && "${TRAIL_NAME}" != "None" ]]; then
  subsection "証跡ステータス（ロギング有効・無効）"
  _aws_run cloudtrail get-trail-status \
    --name "${TRAIL_NAME}" \
    --query '{
      IsLogging:IsLogging,
      LatestDeliveryTime:LatestDeliveryTime,
      LatestDeliveryError:LatestDeliveryError
    }' \
    --output table

  # イベントセレクタ（S3データイベント等の記録設定）
  # 同一性確認ポイント: ReadWriteType・IncludeManagementEvents・DataResources
  subsection "イベントセレクタ（記録対象イベント・S3データイベント設定）"
  _aws_json cloudtrail get-event-selectors \
    --trail-name "${TRAIL_NAME}" \
    --query 'EventSelectors[].{
      ReadWriteType:ReadWriteType,
      IncludeManagementEvents:IncludeManagementEvents,
      DataResources:DataResources
    }'
fi

################################################################################
echo ""
echo "============================================================"
echo "リソース情報出力完了: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
