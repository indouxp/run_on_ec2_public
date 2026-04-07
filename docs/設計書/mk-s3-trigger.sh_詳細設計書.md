# mk-s3-trigger.sh 詳細設計書

## 1. 概要

### 1.1 目的

本ドキュメントは、S3トリガー設定スクリプト `mk-s3-trigger.sh` の詳細設計を定義します。

本スクリプトはS3バケット `${BKT_IN}` に `.conf` ファイルがアップロードされたときにLambda関数 `ts-010-lmd-010` を呼び出すトリガーを設定します。具体的には以下の2つのAWSリソースを設定します。

- **Lambdaリソースベースポリシー**: S3サービスからLambda関数を呼び出す権限（`lambda:InvokeFunction`）を付与
- **S3バケット通知設定**: `.conf` ファイル作成（`s3:ObjectCreated:*`）時にLambda ARNへ通知するよう設定

既存の設定がある場合は削除してから再設定します。

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）
- mk-s3bkt.sh 詳細設計書（[設計書/mk-s3bkt.sh_詳細設計書.md](mk-s3bkt.sh_詳細設計書.md)）
- mk-lambda.sh 詳細設計書（[設計書/mk-lambda.sh_詳細設計書.md](mk-lambda.sh_詳細設計書.md)）

## 2. 実行環境

- **実行場所**: `infra/` ディレクトリ
- **必要コマンド**: aws cli
- **AWS認証**: `source assume-role.sh`（ts-010-role-build を AssumeRole）

## 3. 前提条件

| 条件 | 内容 |
|:---|:---|
| AWS認証 | ts-010-role-build の AssumeRole が有効であること |
| S3バケット | `${BKT_IN}` が作成済みであること |
| Lambda関数 | `ts-010-lmd-010` が作成済みであること |
| config.sh | スクリプトと同じディレクトリに `config.sh` が存在すること |

> **注意**: 本スクリプトは `mk-s3bkt.sh` および `mk-lambda.sh` から自動呼び出しされる場合があります。

## 4. 入力

### 4.1 設定ファイル（config.sh）

`config.sh` を `source` して以下の変数を使用します。

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `S3_BKT_IN_NAME` | トリガー対象バケット名 | `${BKT_IN}` |
| `LAMBDA_FUNC_NAME` | 呼び出し対象Lambda関数名 | `ts-010-lmd-010` |

### 4.2 スクリプト内定数

| 変数名 | 説明 | 値 |
|:---|:---|:---|
| `BUCKET_NAME` | バケット名（`S3_BKT_IN_NAME` から取得） | `${BKT_IN}` |
| `FUNC_NAME` | Lambda関数名（`LAMBDA_FUNC_NAME` から取得） | `ts-010-lmd-010` |
| `STATEMENT_ID` | Lambdaポリシーステートメントの識別ID | `s3-trigger-for-ts-010-lmd-010` |
| `NOTIFICATION_ID` | S3通知設定の識別ID | `lambda-trigger-for-conf-files` |

### 4.3 引数

なし。

## 5. 処理フロー

### 初期化処理

1. `set -euo pipefail` によるエラー時即時終了を設定する
2. 作業用一時ディレクトリ `./mk-s3-trigger.sh.src` を作成する（`mkdir -p`）
3. トラップを設定する（ERR/INT/TERM 時は一時ディレクトリ削除後に終了、EXIT 時は削除）
4. 以降の標準出力・標準エラー出力を `mk-s3-trigger.sh.log` にリダイレクトする
5. `config.sh` を読み込む
6. `BUCKET_NAME`・`FUNC_NAME`・`STATEMENT_ID`・`NOTIFICATION_ID` を設定する

### confirm_trigger 関数（実行前確認）

7. `aws lambda get-policy` でLambda関数 `ts-010-lmd-010` のリソースベースポリシーを表示する
   （ポリシーなしの場合はメッセージを出力する）
8. `aws s3api get-bucket-notification-configuration` でS3バケット `${BKT_IN}` の通知設定を表示する
   （設定なしの場合はメッセージを出力する）

### set_trigger 関数（トリガー設定）

9. `aws sts get-caller-identity` でAWSアカウントIDを取得する
10. `aws lambda get-function` でLambda関数のARN（`LAMBDA_ARN`）を取得する
11. `BUCKET_ARN` を `arn:aws:s3:::${BUCKET_NAME}` として設定する

**Lambda呼び出し権限の付与:**

12. `aws lambda remove-permission` で既存のステートメント（`STATEMENT_ID`）を削除する
    （存在しない場合はエラーを無視して継続する）
13. `aws lambda add-permission` でS3サービスからのLambda呼び出し権限を付与する
    - Action: `lambda:InvokeFunction`
    - Principal: `s3.amazonaws.com`
    - SourceArn: `BUCKET_ARN`
    - SourceAccount: `ACCOUNT_ID`（混乱した代理問題対策）

**S3通知設定の作成:**

14. 通知設定JSON（`NOTIFICATION_CONFIG`）をシェル変数として構築する
    - LambdaFunctionArn: `LAMBDA_ARN`
    - Events: `s3:ObjectCreated:*`
    - Filter: Suffix `.conf`（`.conf` ファイルのみトリガー）
    - Id: `NOTIFICATION_ID`
15. `aws s3api put-bucket-notification-configuration` でS3バケットに通知設定を適用する

### confirm_trigger 関数（実行後確認）

16. 手順7〜8と同様に、設定後のLambdaポリシーとS3通知設定を確認・表示する

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| Lambdaリソースベースポリシー | `ts-010-lmd-010` | 既存ステートメント削除・新規追加（S3からの `lambda:InvokeFunction` 許可） |
| S3バケット通知設定 | `${BKT_IN}` | `.conf` ファイル作成時にLambda ARNへ通知する設定を適用 |

## 7. エラーハンドリング

| 状況 | 対処 |
|:---|:---|
| `set -euo pipefail` | コマンド失敗・未定義変数参照・パイプエラー時に即時終了する |
| ERR/INT/TERM シグナル | `term` 関数を呼び出し、一時ディレクトリを削除後に `exit 1` |
| EXIT | `term` 関数を呼び出し、一時ディレクトリを削除する（正常終了時も含む） |
| `lambda remove-permission` 失敗（権限なし） | `2>/dev/null || echo "..."` でエラーを吸収し、処理を継続する |
| `lambda get-policy` 失敗（ポリシーなし） | `2>/dev/null || echo "..."` でエラーを吸収し、メッセージを出力する |
| `get-bucket-notification-configuration` 失敗 | `2>/dev/null || echo "..."` でエラーを吸収し、メッセージを出力する |

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
