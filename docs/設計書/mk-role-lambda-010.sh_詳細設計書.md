# mk-role-lambda-010.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、Lambda 関数（ts-010-lmd-010）が使用する IAM ロール（`ts-010-role-lambda-010`）を作成します。既存の同名ロールが存在する場合は削除してから再作成します。

作成するリソース:
- IAM ロール（名前: `ts-010-role-lambda-010`）
  - 信頼ポリシー: `lambda.amazonaws.com` による AssumeRole を許可
  - 管理ポリシー: `AWSLambdaBasicExecutionRole`（CloudWatch Logs 書き込み）
  - インラインポリシー（`ts-010-policy-lambda-010`）:
    - S3 入力バケット（`${BKT_IN}`）への GetObject 権限
    - S3 出力バケット（`${BKT_OUT}`）への PutObject 権限
    - EC2 起動・検索・タグ付け権限
    - EC2 インスタンスプロファイル取得権限
    - IAM PassRole 権限（`ts-010-role-ec2-010` のみ）
    - SNS Publish 権限（`ts-010-sns-010` のみ）
    - SES SendEmail 権限

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）
- セキュリティ設定（[設計書/セキュリティ設定.md](セキュリティ設定.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli
- AWS 認証: `AWS_PROFILE=ts-usr-admin`（IAM 操作のため直接プロファイル指定）

---

## 3. 前提条件

- S3 バケット（`${BKT_IN}`、`${BKT_OUT}`）が作成済みであること
- SNS トピック（`ts-010-sns-010`）が作成済みであること
- EC2 実行ロール（`ts-010-role-ec2-010`）の名前が確定していること

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `IAM_ROLE_LAMBDA_NAME` | 作成する IAM ロールの名前 | `ts-010-role-lambda-010` |
| `IAM_POLICY_LAMBDA_NAME` | インラインポリシーの名前 | `ts-010-lambda-custom-policy-010` |
| `S3_BKT_IN_NAME` | Lambda が読み取る入力 S3 バケット名 | `${BKT_IN}` |
| `S3_BKT_OUT_NAME` | Lambda が書き込む出力 S3 バケット名 | `${BKT_OUT}` |
| `SNS_TOPIC_NAME` | 通知先 SNS トピック名 | `ts-010-sns-010` |
| `AWS_REGION` | AWSリージョン | `ap-northeast-1` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. 作業用一時ディレクトリ（`mk-role-lambda-010.sh.src`）を作成する。作成できない場合はエラー終了する。
3. `trap` を設定し、ERR / INT / TERM シグナル発生時に `term()` を呼び出して一時ディレクトリを削除し、`exit 1` で終了する。EXIT シグナルでも `term()` を呼び出す。
4. ログファイル（`mk-role-lambda-010.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。

### `confirm_role()` — 実行前後の確認

5. `aws iam get-role` でロールの存在を確認する。存在しない場合はその旨を表示する。
6. ロールが存在する場合は詳細・アタッチ管理ポリシー・インラインポリシーを出力する。

### `make_role()` — ロール作成処理

7. `aws iam get-role` で既存ロールの有無を確認する。
8. 既存ロールが存在する場合:
   a. `aws iam delete-role-policy` でインラインポリシーを削除する（存在しない場合はスキップ）。
   b. `aws iam detach-role-policy` で管理ポリシーをデタッチする（アタッチされていない場合はスキップ）。
   c. `aws iam delete-role` でロールを削除する。
   d. AWS 反映待ちとして `sleep 5` を実行する。
9. 信頼ポリシー JSON（`trust-policy-lambda.json`）を作業ディレクトリに生成する。
   - Principal: `lambda.amazonaws.com`、Action: `sts:AssumeRole`
10. `aws iam create-role` でロールを作成し、プロジェクトタグを付与する。
11. `aws iam attach-role-policy` で `AWSLambdaBasicExecutionRole` 管理ポリシーをアタッチする。
12. `aws sts get-caller-identity` で AWS アカウント ID を取得する。
13. カスタムポリシー JSON（`lambda-custom-policy.json`）を作業ディレクトリに生成する。
14. `aws iam put-role-policy` でインラインポリシーをアタッチする。

### メイン処理の流れ

15. 実行前に `confirm_role()` を呼び出してリソース状態を記録する。
16. `make_role()` を呼び出してリソースを作成する。
17. 実行後に `confirm_role()` を再度呼び出して結果を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| IAM ロール | `ts-010-role-lambda-010` | 既存削除→新規作成 |
| 管理ポリシーアタッチ | `AWSLambdaBasicExecutionRole` | アタッチ |
| インラインポリシー | `ts-010-policy-lambda-010` | 作成（S3/EC2/SNS/SES 権限） |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term; exit 1' ERR INT TERM` により、異常終了時は作業用一時ディレクトリを自動削除する。
- `trap 'term' EXIT` により、正常終了時も一時ディレクトリを削除する。
- 既存インラインポリシーの削除・管理ポリシーのデタッチ失敗は `||` で無視する（存在しない場合に備えるため）。
- すべての処理ログは `mk-role-lambda-010.sh.log` に記録される。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
