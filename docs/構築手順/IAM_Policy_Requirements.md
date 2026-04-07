# IAMポリシー要件一覧

## 1. 概要

### 1.1 目的
本文書は、このシステムを構築および実行するために必要なIAM権限を、以下の2フェーズに分類してまとめます。

1. **インフラ構築フェーズ**: 管理者が環境構築スクリプト（`src/shell/*.sh`）を実行する際に必要な権限
2. **システム実行フェーズ**: Lambda関数・EC2インスタンス・運用担当者が日々の運用中に使用する権限

### 1.2 関連文書

**参照文書**
- 基本設計書（[設計書/基本設計.md](../設計書/基本設計.md)）
- セキュリティ設定一覧（[設計書/セキュリティ設定.md](../設計書/セキュリティ設定.md)）

---

## 2. インフラ構築フェーズ

管理者（またはCI/CDパイプライン）が `src/shell/` 以下のスクリプトを実行してAWSリソースを作成・設定するために必要な権限です。

### 実行者の区分

インフラ構築は2種類の実行者を使い分けます。

| 実行者 | AWSプロファイル | 対象スクリプト |
|--------|---------------|--------------|
| 管理者ユーザー | `ts-usr-admin`（AdministratorAccess） | IAM系スクリプト（`mk-role-*.sh` / `mk-iam-user.sh`） |
| 構築用ロール | `ts-010-role-build`（`assume-role.sh` 経由） | それ以外のスクリプト |

`ts-usr-admin` は**インフラ構築フェーズのIAM作成時のみ**使用します。
構築完了後・運用フェーズでは使用しません。

---

### IAM
- `iam:CreateRole`, `iam:DeleteRole`, `iam:GetRole`, `iam:ListRoles`（ロールの作成・削除・参照・列挙）
- `iam:PassRole`（EC2起動時にIAMロールを渡す）
- `iam:CreatePolicy`, `iam:DeletePolicy`, `iam:GetPolicy`, `iam:ListPolicies`（ポリシーの作成・削除・参照・列挙）
- `iam:AttachRolePolicy`, `iam:DetachRolePolicy`（管理ポリシーのアタッチ・デタッチ）
- `iam:PutRolePolicy`, `iam:DeleteRolePolicy`（インラインポリシーの設定・削除）
- `iam:CreateInstanceProfile`, `iam:DeleteInstanceProfile`, `iam:GetInstanceProfile`（EC2インスタンスプロファイルの管理）
- `iam:AddRoleToInstanceProfile`, `iam:RemoveRoleFromInstanceProfile`（インスタンスプロファイルへのロール関連付け・解除）
- `iam:ListInstanceProfiles`, `iam:ListRolePolicies`, `iam:ListAttachedRolePolicies`（構成確認・削除前の棚卸し）
- `iam:TagRole`, `iam:UntagRole`（ロールへのプロジェクトタグ付け・削除）
- `iam:TagInstanceProfile`, `iam:UntagInstanceProfile`（インスタンスプロファイルへのプロジェクトタグ付け・削除）
- `iam:TagUser`, `iam:UntagUser`（IAMユーザーへのプロジェクトタグ付け・削除）

### EC2 / VPC
- `ec2:CreateVpc`, `ec2:DeleteVpc`, `ec2:DescribeVpcs`, `ec2:ModifyVpcAttribute`, `ec2:DescribeVpcAttribute`（VPCの作成・削除・参照・属性設定）
- `ec2:CreateSubnet`, `ec2:DeleteSubnet`, `ec2:DescribeSubnets`, `ec2:ModifySubnetAttribute`（サブネットの作成・削除・参照・属性設定）
- `ec2:CreateInternetGateway`, `ec2:DeleteInternetGateway`, `ec2:DescribeInternetGateways`, `ec2:AttachInternetGateway`, `ec2:DetachInternetGateway`（インターネットゲートウェイの管理・VPCへのアタッチ・デタッチ）
- `ec2:CreateRouteTable`, `ec2:DeleteRouteTable`, `ec2:DescribeRouteTables`, `ec2:CreateRoute`, `ec2:DeleteRoute`, `ec2:AssociateRouteTable`（ルートテーブルの作成・削除・ルート設定・サブネットへの関連付け）
- `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup`, `ec2:DescribeSecurityGroups`, `ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress`（セキュリティグループの作成・削除・インバウンドルール設定）
- `ec2:CreateKeyPair`, `ec2:DeleteKeyPair`, `ec2:DescribeKeyPairs`（SSH接続用キーペアの作成・削除・参照）
- `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:DescribeInstances`, `ec2:CreateTags`（動作確認テスト用のインスタンス起動・削除・参照・タグ付け）

### S3
- `s3:CreateBucket`, `s3:DeleteBucket`, `s3:ListBucket`, `s3:ListAllMyBuckets`, `s3:GetBucketLocation`（バケットの作成・削除・オブジェクト一覧・全バケット列挙・リージョン確認）
- `s3:PutBucketPolicy`, `s3:GetBucketPolicy`, `s3:DeleteBucketPolicy`（バケットポリシーの設定・参照・削除）
- `s3:PutBucketPublicAccessBlock`, `s3:GetBucketPublicAccessBlock`（パブリックアクセスブロックの設定・参照）
- `s3:PutEncryptionConfiguration`, `s3:GetEncryptionConfiguration`（サーバーサイド暗号化（AES-256）の設定・参照）
- `s3:PutBucketVersioning`, `s3:GetBucketVersioning`（バージョニングの有効化・参照）
- `s3:ListBucketVersions`, `s3:DeleteObjectVersion`（バージョン一覧取得・バケット削除前のバージョン削除）
- `s3:PutLifecycleConfiguration`, `s3:GetLifecycleConfiguration`（ライフサイクルルールの設定・参照）
- `s3:PutBucketNotification`, `s3:GetBucketNotification`（S3イベント通知の設定・参照 ― Lambda起動トリガー用）
- `s3:PutBucketOwnershipControls`, `s3:GetBucketOwnershipControls`（オブジェクト所有権設定の変更・参照）
- `s3:PutBucketTagging`, `s3:GetBucketTagging`（バケットへのプロジェクトタグ付け・参照）

### Lambda
- `lambda:CreateFunction`, `lambda:DeleteFunction`, `lambda:GetFunction`, `lambda:GetFunctionConfiguration`（関数の作成・削除・参照・設定取得）
- `lambda:UpdateFunctionCode`, `lambda:UpdateFunctionConfiguration`（関数コードおよび設定の更新）
- `lambda:AddPermission`, `lambda:RemovePermission`, `lambda:GetPolicy`（S3/EventBridgeからの呼び出し許可の付与・削除・参照）
- `lambda:ListFunctions`, `lambda:ListTags`, `lambda:TagResource`（関数一覧取得・タグ参照・プロジェクトタグ付け）

### CloudWatch Logs
- `logs:CreateLogGroup`, `logs:DeleteLogGroup`, `logs:DescribeLogGroups`, `logs:PutRetentionPolicy`（ロググループの作成・削除・参照・保持期間設定）
- `logs:DeleteLogStream`, `logs:DescribeLogStreams`（ログストリームの削除・参照）
- `logs:PutMetricFilter`, `logs:DeleteMetricFilter`, `logs:DescribeMetricFilters`（メトリックフィルターの設定・削除・参照）
- `logs:TagLogGroup`（ロググループへのプロジェクトタグ付け）

### EventBridge
- `events:PutRule`, `events:DeleteRule`, `events:DescribeRule`, `events:ListRules`（ルールの作成・削除・参照・列挙）
- `events:PutTargets`, `events:RemoveTargets`, `events:ListTargetsByRule`（ルールのターゲット設定・削除・参照 ― EC2停止イベント → Lambda終了関数の連携）
- `events:TagResource`（リソースへのプロジェクトタグ付け）

### CloudTrail
- `cloudtrail:CreateTrail`, `cloudtrail:DeleteTrail`, `cloudtrail:DescribeTrails`, `cloudtrail:GetTrail`（証跡の作成・削除・参照）
- `cloudtrail:StartLogging`, `cloudtrail:StopLogging`（証跡ログの記録開始・停止）
- `cloudtrail:PutEventSelectors`（記録対象イベントの絞り込み設定）
- `cloudtrail:AddTags`（証跡へのプロジェクトタグ付け）

### SNS
- `sns:CreateTopic`, `sns:DeleteTopic`, `sns:GetTopicAttributes`, `sns:SetTopicAttributes`（トピックの作成・削除・属性参照・属性設定）
- `sns:Subscribe`（メール・SMS宛先のサブスクリプション登録）
- `sns:ListTopics`（トピック一覧取得 ― 既存トピックの重複確認用）
- `sns:TagResource`（リソースへのプロジェクトタグ付け）

### SES
- 構築スクリプト内での自動セットアップはありません。メール送信に使用する送信元アドレスの検証（`ses:VerifyEmailIdentity` 等）は事前に手動で実施してください。

### STS
- `sts:GetCallerIdentity`（実行中のIAMエンティティのアカウントID取得 ― ポリシーARN組み立て用）

---

## 3. システム実行フェーズ

稼働中のシステム（Lambda関数・EC2インスタンス）および運用担当者が付与されたIAMロールを通じて使用する権限です。

### A. Lambda起動関数用ロール（`ts-010-role-lambda-010`）

LambdaがS3トリガーで起動し、EC2を立ち上げるために必要な権限です。

**マネージドポリシー:**
- `AWSLambdaBasicExecutionRole`（CloudWatch Logsへのログ書込）

**カスタムポリシー:**
- **S3:**
  - `s3:GetObject`（Resource: `arn:aws:s3:::${BKT_IN}/*`）— 入力バケットから定義ファイルを読み込む
  - `s3:PutObject`（Resource: `arn:aws:s3:::${BKT_OUT}/*`）— エラー時に出力バケットへログを書き込む
- **EC2:**
  - `ec2:RunInstances` — バッチ処理用EC2インスタンスを起動する
  - `ec2:DescribeInstances`, `ec2:DescribeSubnets`, `ec2:DescribeSecurityGroups` — 起動前に定義ファイルで指定されたリソースの存在確認
  - `ec2:CreateTags` — 起動したインスタンスにNameタグ等を付与する
- **IAM:**
  - `iam:PassRole`（Resource: `arn:aws:iam::*:role/ts-010-role-ec2-010`）— EC2にIAMロールを渡す
  - `iam:GetInstanceProfile` — EC2のインスタンスプロファイルARNを取得する
- **SNS:**
  - `sns:Publish`（Resource: `arn:aws:sns:<Region>:<AccountID>:ts-010-sns-010`）— バリデーションエラー時のSMS通知
- **SES:**
  - `ses:SendEmail`（Resource: `arn:aws:ses:<Region>:<AccountID>:identity/*`）— バリデーションエラー時のメール通知

### B. Lambda終了関数用ロール（`ts-010-role-lambda-020`）

EventBridge経由でEC2停止を検知し、インスタンスを削除するために必要な権限。

**マネージドポリシー:**
- `AWSLambdaBasicExecutionRole`（CloudWatch Logsへのログ書込）

**カスタムポリシー:**
- **EC2:**
  - `ec2:DescribeInstances` — インスタンスIDからタグ等を取得して削除対象を特定する
  - `ec2:TerminateInstances` — 対象インスタンスを削除する

### C. EC2インスタンス用ロール（`ts-010-role-ec2-010`）

起動したEC2がバッチ処理を行い、結果を保存・通知・自己終了するために必要な権限。

**マネージドポリシー:**
- `CloudWatchAgentServerPolicy`（CloudWatch Agentの起動・メトリクス/ログ送信）

**カスタムポリシー:**
- **S3:**
  - `s3:GetObject`, `s3:ListBucket`（Resource: `arn:aws:s3:::${BKT_IN}/*`）— 実行スクリプト・入力ファイルのダウンロード
  - `s3:PutObject`, `s3:ListBucket`（Resource: `arn:aws:s3:::${BKT_OUT}/*`）— 処理結果・ログファイルのアップロード
- **SNS:**
  - `sns:Publish`（Resource: `*`）— 処理完了・失敗時のSMS通知
- **SES:**
  - `ses:SendEmail`, `ses:SendRawEmail`（Resource: `*`）— 処理完了・失敗時のメール通知
- **CloudWatch Logs:**
  - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`（Resource: `arn:aws:logs:<Region>:*:log-group:ts-010-log-*`）— バッチ処理ログのリアルタイム送信
- **EC2:**
  - `ec2:TerminateInstances`（Condition: `tag:Name = ts-010-ec2-010`）— バッチ処理完了後の自己削除

### D. 実行用ロール（`ts-010-role-exec`）

`ts-010-user` が `aws-pop-bktobj.sh` などの運用スクリプトを実行する際に AssumeRole して使用するロールです。

**カスタムポリシー:**
- **S3:**
  - `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`, `s3:ListAllMyBuckets`
    （Resource: `arn:aws:s3:::${BKT_IN}`, `${BKT_IN}/*`, `${BKT_OUT}`, `${BKT_OUT}/*`）
    — 運用スクリプト（`aws-pop-bktobj.sh` 等）によるオブジェクトのダウンロード・アップロード・削除・一覧取得
- **EC2:**
  - `ec2:RunInstances`, `ec2:DescribeInstances`, `ec2:DescribeSubnets`, `ec2:DescribeSecurityGroups`, `ec2:CreateTags` — 手動でのインスタンス起動・状態確認・タグ付け
  - `ec2:TerminateInstances`（Condition: `tag:Name = ts-010-ec2-010`）— 手動でのインスタンス削除（対象タグ付きのみ）
- **IAM:**
  - `iam:PassRole`, `iam:GetInstanceProfile`（Resource: `ts-010-role-ec2-010`, `ts-010-role-lambda-010`, `ts-010-role-exec`）— EC2/Lambda起動時にIAMロールを渡す・プロファイルARNを取得する
- **SNS / SES:**
  - `sns:Publish`（Resource: `arn:aws:sns:<Region>:<AccountID>:ts-010-sns-010`）— 手動実行時のSMS通知
  - `ses:SendEmail`, `ses:SendRawEmail`（Resource: `arn:aws:ses:<Region>:<AccountID>:identity/*`）— 手動実行時のメール通知
- **CloudWatch Logs:**
  - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`（Resource: `arn:aws:logs:<Region>:<AccountID>:log-group:ts-010-log-*`）— 手動実行時のログ書込
  - `logs:DescribeLogGroups`, `logs:DescribeLogStreams`, `logs:GetLogEvents`（Resource: `arn:aws:logs:<Region>:<AccountID>:log-group:ts-010-log-*`）— 実行ログの参照・確認

### E. IAMユーザー（`ts-010-user`）

運用担当者が使用するIAMユーザーです。直接AWSリソースを操作せず、必要なロールへ AssumeRole して権限を行使します。

**インラインポリシー:**
- **STS:**
  - `sts:AssumeRole`（Resource: `arn:aws:iam::<AccountID>:role/ts-010-role-build`, `ts-010-role-exec`）
    — インフラ構築ロール（`ts-010-role-build`）および実行用ロール（`ts-010-role-exec`）へのスイッチ
- **CloudWatch Logs:**
  - `logs:DescribeLogGroups`, `logs:DescribeLogStreams`, `logs:GetLogEvents`, `logs:FilterLogEvents`
    （Resource: `*`）— AssumeRole なしで直接ログを閲覧する（実行状況の確認用）

---

**作成日**: 2025年8月26日
**更新日**: 2026年4月2日
**バージョン**: 1.3
**作成者**: tsystem
**承認者**: tsystem
