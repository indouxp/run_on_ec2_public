# del-all.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、このプロジェクト（ts-010）で作成した**全 AWS リソースをまとめて削除**します。クリーンな再構築や環境撤収（プロジェクト終了時）を目的として使用します。

> **警告**: 本スクリプトは破壊的操作を行います。実行すると削除したリソースは元に戻せません。実行前に必ず内容を確認し、削除前のベースライン保存（`info-all.sh --save`）を強く推奨します。

削除するリソースの種別（実行順序）:

1. EC2インスタンス（`ts-010-ec2-ssh-010`、`ts-010-ec2-010`）
2. EventBridgeルール（`ts-010-rule-stop-ec2-trigger`）
3. Lambda関数（`ts-010-lmd-010`、`ts-010-lmd-020`）
4. S3トリガー（入力バケットの通知設定クリア）
5. SNSトピックおよびサブスクリプション（`ts-010-sns-010`）
6. CloudWatch ロググループ（プロジェクト管理分 + Lambda自動作成分）
7. S3バケット（`${BKT_IN}`、`${BKT_OUT}`）
8. CloudTrail証跡とログバケット（`ts-010-trail-010`、`${BKT_CLOUDTRAIL}`）
9. キーペア（`ts-010-keypair`）
10. ネットワーク（SG → サブネット → ルートテーブル → IGW → VPC）
11. IAMロール・ユーザー（全5ロール + `ts-010-user`）

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli、python3（S3バージョン付きオブジェクト削除処理内で使用）
- AWS認証: `AWS_PROFILE=ts-usr-admin`（IAM 操作を含むため管理者プロファイルを使用）

---

## 3. 前提条件

- `AWS_PROFILE=ts-usr-admin` が有効なプロファイルであること。
- `config.sh` が同ディレクトリ（`src/shell/`）に存在すること。
- 本スクリプトは `infra/` 内のシンボリックリンク経由で実行されます。

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `PRJ_PREFIX` | プロジェクトプレフィックス | `ts-010` |
| `AWS_REGION` | AWSリージョン | `ap-northeast-1` |
| `LAMBDA_FUNC_NAME` | Lambda関数名 | `ts-010-lmd-010` |
| `S3_BKT_IN_NAME` | S3入力バケット名 | `${BKT_IN}` |
| `S3_BKT_OUT_NAME` | S3出力バケット名 | `${BKT_OUT}` |
| `SNS_TOPIC_NAME` | SNSトピック名 | `ts-010-sns-010` |
| `CW_LOG_GROUP_LAMBDA_NAME` | CloudWatch Lambdaロググループ名 | `ts-010-log-lambda-010` |
| `CW_LOG_GROUP_EC2_NAME` | CloudWatch EC2ロググループ名 | `ts-010-log-ec2-010` |
| `CW_LOG_GROUP_SYSTEM_NAME` | CloudWatch システムロググループ名 | `ts-010-log-system-010` |
| `VPC_NAME` | VPC名 | `ts-010-vpc-010` |
| `IAM_ROLE_LAMBDA_NAME` | Lambda実行IAMロール名 | `ts-010-role-lambda-010` |
| `IAM_ROLE_EC2_NAME` | EC2実行IAMロール名 | `ts-010-role-ec2-010` |
| `IAM_ROLE_BUILD_NAME` | インフラ構築用IAMロール名 | `ts-010-role-build` |
| `IAM_ROLE_EXEC_NAME` | 実行用IAMロール名 | `ts-010-role-exec` |
| `IAM_USER_NAME` | IAMユーザー名 | `ts-010-user` |

### 4.2 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `set -uo pipefail` を設定する（`-e` は付けない。リソース未存在時のエラーを `|| true` で吸収するため）。
2. `config.sh` を読み込み、環境変数を設定する。
3. ログファイル（`del-all.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。
4. 開始タイムスタンプを出力する。

### Step 1: EC2インスタンスの終了

5. `aws ec2 describe-instances` で `ts-010-ec2-ssh-010` タグを持つ実行中/停止中インスタンスの ID を取得する。
6. 存在する場合、`aws ec2 terminate-instances` で終了リクエストを送信し、`aws ec2 wait instance-terminated` で完全終了まで待機する。
7. 同様に `ts-010-ec2-010` についても確認・終了処理を実施する。

### Step 2: EventBridgeルールの削除

8. `aws events describe-rule` でルール `ts-010-rule-stop-ec2-trigger` の存在を確認する。
9. 存在する場合、先にターゲット（`aws events list-targets-by-rule` で取得）を `aws events remove-targets` で削除する。
10. `aws events delete-rule` でルールを削除する。

### Step 3: Lambda関数の削除

11. `ts-010-lmd-010` および `ts-010-lmd-020` の 2 関数について、`aws lambda get-function` で存在確認する。
12. 存在する場合、`aws lambda delete-function` で削除する。

### Step 4: S3トリガー（通知設定）のクリア

13. `aws s3api head-bucket` で入力バケット `${BKT_IN}` の存在を確認する。
14. 存在する場合、`aws s3api put-bucket-notification-configuration` に空オブジェクト `{}` を設定し、通知設定をクリアする。

### Step 5: SNSトピック・サブスクリプションの削除

15. `aws sns list-topics` でトピック ARN を取得する。
16. 存在する場合、`aws sns list-subscriptions-by-topic` でサブスクリプション一覧を取得し、`PendingConfirmation` を除く全サブスクリプションを `aws sns unsubscribe` で解除する。
17. `aws sns delete-topic` でトピックを削除する。

### Step 6: CloudWatch ロググループの削除

18. `ts-010-log-lambda-010`、`ts-010-log-ec2-010`、`ts-010-log-system-010` の 3 ロググループについて、`aws logs describe-log-groups` で存在確認し、`aws logs delete-log-group` で削除する。
19. Lambda が自動作成するロググループ（`/aws/lambda/ts-010-lmd-010`、`/aws/lambda/ts-010-lmd-020`）についても同様に確認・削除する。

### Step 7: S3バケットの削除（内部関数 `_delete_bucket`）

20. `aws s3api head-bucket` でバケット存在を確認する。未存在の場合はスキップする。
21. `aws s3api delete-bucket-policy` でバケットポリシーを削除する。
22. `aws s3api list-object-versions` でバージョン付きオブジェクトと削除マーカーを取得し、`python3` で JSON を生成して `aws s3api delete-objects` で一括削除する。
23. `aws s3 rm --recursive` で残りの通常オブジェクトを削除する。
24. `aws s3api delete-bucket` でバケットを削除する。
25. `${BKT_IN}`、`${BKT_OUT}` の順で `_delete_bucket` を呼び出す。

### Step 8: CloudTrailの削除

26. `aws cloudtrail get-trail` で証跡 `ts-010-trail-010` の存在を確認する。
27. 存在する場合、`aws cloudtrail stop-logging` でロギングを停止し、`aws cloudtrail delete-trail` で証跡を削除する。
28. CloudTrailログバケット `${BKT_CLOUDTRAIL}` を `_delete_bucket` 関数で削除する。

### Step 9: キーペアの削除

29. `aws ec2 describe-key-pairs` でキーペア `ts-010-keypair` の存在を確認する。
30. 存在する場合、`aws ec2 delete-key-pair` で削除する。

### Step 10: ネットワークリソースの削除

31. `aws ec2 describe-vpcs` で `VPC_NAME` タグを持つ VPC の ID を取得する。
32. 存在する場合、以下の順序で削除する（依存関係の逆順）。
    1. デフォルト SG を除く全セキュリティグループ（`aws ec2 delete-security-group`）
    2. 全サブネット（`aws ec2 delete-subnet`）
    3. カスタムルートテーブル（メインルートテーブル以外）（`aws ec2 delete-route-table`）
    4. メインルートテーブルの IGW ルート（`aws ec2 delete-route` で `0.0.0.0/0` を削除）
    5. IGW のデタッチ（`aws ec2 detach-internet-gateway`）と削除（`aws ec2 delete-internet-gateway`）
    6. VPC（`aws ec2 delete-vpc`）

### Step 11: IAMロール・ユーザーの削除（内部関数 `_delete_role`）

33. `_delete_role` 関数: IAMロールの管理ポリシーをすべてデタッチし、インラインポリシーをすべて削除してからロールを削除する。
34. `ts-010-role-lambda-020` を `_delete_role` で削除する。
35. `ts-010-role-lambda-010` を `_delete_role` で削除する。
36. `ts-010-role-ec2-010` を処理する。先にインスタンスプロファイルからロールを外し（`aws iam remove-role-from-instance-profile`）、インスタンスプロファイルを削除（`aws iam delete-instance-profile`）してから `_delete_role` を呼び出す。
37. `ts-010-role-build` と `ts-010-role-exec` を `_delete_role` で削除する。
38. IAMユーザー `ts-010-user` を処理する。アクセスキーをすべて削除し、インラインポリシーをすべて削除してから `aws iam delete-user` で削除する。

### 完了

39. 完了タイムスタンプを出力する。
40. `~/.aws/credentials` の手動更新を促すメッセージを出力する。

---

## 6. 出力・副作用

| 項目 | 内容 |
|:---|:---|
| ログファイル | `./del-all.sh.log`（実行ディレクトリに追記） |
| 削除対象AWSリソース | EC2、EventBridge、Lambda、S3トリガー、SNS、CloudWatch、S3バケット、CloudTrail、キーペア、VPC/IGW/SG/サブネット/ルートテーブル、IAMロール・ユーザー |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -uo pipefail` を設定する（`-e` は付けず、リソース未存在エラーは `|| true` で吸収する）。
- 各削除操作の末尾に `|| true` を付与し、リソース未存在や削除エラーが発生してもスクリプトを継続させる。
- リソース存在確認は事前に実施し、未存在の場合は「スキップ」メッセージを出力して次の処理へ進む。
- すべての処理ログは `del-all.sh.log` に記録される。

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
