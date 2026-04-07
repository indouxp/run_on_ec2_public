# mk-lambda.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、S3イベントをトリガーにEC2インスタンスを起動するLambda関数（`ts-010-lmd-010`）をデプロイします。

主な処理は以下の通りです。

- EC2用IAMインスタンスプロファイル（`ts-010-role-ec2-010`）の確認・作成
- `src/lambda/` 以下のPythonコードをZIP化してデプロイパッケージを生成
- Lambda関数（`ts-010-lmd-010`）の削除・再作成
- `mk-s3-trigger.sh` を自動呼び出してS3トリガーを再設定

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）
- 定義ファイル仕様書（[設計書/定義ファイル仕様.md](定義ファイル仕様.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli, zip
- AWS認証: `source assume-role.sh`（`ts-010-role-build` を AssumeRole）

---

## 3. 前提条件

このスクリプト実行前に以下のリソースが存在・設定されていること。

| 前提リソース | 説明 |
|:---|:---|
| IAMロール `ts-010-role-lambda-010` | Lambda実行ロール（`mk-role-lambda-010.sh` で作成） |
| IAMロール `ts-010-role-ec2-010` | EC2実行ロール（`mk-role-ec2-010.sh` で作成） |
| S3バケット `${BKT_IN}` | 入力バケット（`mk-s3bkt.sh` で作成） |
| `src/lambda/lambda_function.py` | Lambdaのメインソースコード |
| `src/lambda/user_data_template.sh` | EC2 UserDataテンプレート（ZIPに同梱） |
| `config.sh` | 共通設定ファイル |

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `LAMBDA_FUNC_NAME` | デプロイするLambda関数名 | `ts-010-lmd-010` |
| `IAM_ROLE_LAMBDA_NAME` | Lambda実行IAMロール名 | `ts-010-role-lambda-010` |
| `IAM_ROLE_EC2_NAME` | EC2実行IAMロール名（インスタンスプロファイル名と兼用） | `ts-010-role-ec2-010` |
| `PRJ_TAG_KEY` | タグキー名 | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | タグ値（プロジェクトプレフィックス） | `ts-010` |

### 4.2 内部設定変数

| 変数名 | 説明 | 値 |
|:---|:---|:---|
| `HANDLER` | Lambdaハンドラー | `lambda_function.main_handler` |
| `RUNTIME` | Lambdaランタイム | `python3.12` |
| `ZIP_FILE` | デプロイパッケージファイル名 | `deployment.zip` |
| `SRC_DIR` | Lambdaソースディレクトリ | `../lambda` |

### 4.3 引数

なし。

---

## 5. 処理フロー

スクリプトは以下の順序で処理を実行します。

### 5.1 実行前確認（`confirm_lambda`）

1. `aws lambda get-function` で Lambda関数 `ts-010-lmd-010` の現在の設定・状態を表示する。
2. 関数が存在しない場合は「存在しません」と出力して続行する。

### 5.2 デプロイ処理（`deploy_lambda`）

1. **IAMインスタンスプロファイルの確認・作成**
   - `aws iam get-instance-profile` でプロファイル `ts-010-role-ec2-010` の存在を確認する。
   - 存在しない場合は `aws iam create-instance-profile` でプロファイルを作成し、同名ロールをプロファイルに追加して10秒待機する。
   - 既に存在する場合はスキップする。

2. **デプロイパッケージ（ZIP）の作成**
   - `cat` で `lambda_function.py` の内容をログに出力する。
   - `cd ../lambda && zip -r $OLDPWD/deployment.zip .` で `src/lambda/` 以下をすべてZIP化する（`user_data_template.sh` も同梱される）。

3. **Lambda関数の削除・再作成**
   - `aws iam get-role` で Lambda実行ロールのARNを取得する。
   - `aws lambda get-function` で既存関数の存在を確認し、存在する場合は `aws lambda delete-function` で削除する。
   - `aws lambda create-function` で以下のパラメータで新規作成する。
     - タイムアウト: 300秒
     - メモリサイズ: 256MB
     - プロジェクトタグを付与

### 5.3 S3トリガーの再設定（`setup_s3_trigger`）

1. `mk-s3-trigger.sh` のパスを解決し、ファイルの存在を確認する。
2. `bash mk-s3-trigger.sh` を実行し、S3バケット（`${BKT_IN}`）からLambdaへのトリガーを再設定する。
   - Lambda削除・再作成後はリソースベースポリシー（S3からの呼び出し許可）が消えるため、必ず実行する。

### 5.4 実行後確認（`confirm_lambda`）

1. `confirm_lambda` を再度実行し、デプロイ後の状態を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作 |
|:---|:---|:---|
| Lambda関数 | `ts-010-lmd-010` | 削除・再作成 |
| IAMインスタンスプロファイル | `ts-010-role-ec2-010` | 新規作成（未存在時のみ） |
| ZIPファイル（ローカル） | `deployment.zip` | 作成（上書き） |
| S3トリガー（Lambda リソースポリシー） | `${BKT_IN}` → `ts-010-lmd-010` | `mk-s3-trigger.sh` 経由で再設定 |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定しており、コマンドが失敗した場合は即時終了する。
- ログはスクリプト名と同名の `.log` ファイル（`mk-lambda.sh.log`）に追記（`exec >> "${LOG_PATH}" 2>&1`）する。
- `mk-s3-trigger.sh` が見つからない場合は `[ERROR]` メッセージを出力して `exit 1` する。
- IAMインスタンスプロファイルの作成失敗・Lambda関数の作成失敗は `set -e` により即時スクリプト終了となる。

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
