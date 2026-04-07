# mk-lambda-terminator.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、EC2 インスタンスを削除（Terminate）するための Lambda 関数（`ts-010-lmd-020`）とその専用 IAM ロール（`ts-010-role-lambda-020`）を作成します。Lambda 関数は EventBridge ルールにより EC2 停止イベントをトリガーとして呼び出されます。

作成するリソース:
- IAM ロール（名前: `ts-010-role-lambda-020`）
  - 信頼ポリシー: `lambda.amazonaws.com` による AssumeRole を許可
  - 管理ポリシー: `AWSLambdaBasicExecutionRole`
  - インラインポリシー（`ts-010-policy-lambda-020`）:
    - EC2 DescribeInstances・TerminateInstances 権限
- Lambda 関数（名前: `ts-010-lmd-020`）
  - ソースファイル: `terminator_lambda_function.py`
  - ランタイム: Python 3.12
  - タイムアウト: 30 秒、メモリ: 128 MB

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- mk-eventbridge-rule.sh 詳細設計書（[設計書/mk-eventbridge-rule.sh_詳細設計書.md](mk-eventbridge-rule.sh_詳細設計書.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli、zip
- AWS 認証: `source assume-role.sh`（`ts-010-role-build` を AssumeRole）

---

## 3. 前提条件

- プロジェクトルートに `lambda/` シンボリックリンクが存在すること（`mk-infra.sh` 実行済み）
- `src/lambda/terminator_lambda_function.py` が存在すること

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 スクリプト内固定値

| 変数名 | 内容 | 値 |
|:---|:---|:---|
| `LAMBDA_FUNC_NAME` | Lambda 関数名 | `ts-010-lmd-020` |
| `IAM_ROLE_NAME` | Lambda 用 IAM ロール名 | `ts-010-role-lambda-020` |
| `POLICY_NAME` | インラインポリシー名 | `ts-010-policy-lambda-020` |
| `SRC_FILE` | Lambda ソースファイル名 | `terminator_lambda_function.py` |
| `ZIP_FILE` | zip アーカイブファイル名 | `terminator_lambda_function.zip` |

### 4.3 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. 作業用一時ディレクトリ（`mk-lambda-terminator.sh.src`）を作成する。
3. `trap` を設定し、ERR / INT / TERM シグナル発生時に `term()` を呼び出して一時ディレクトリを削除し、`exit 1` で終了する。EXIT シグナルでも `term()` を呼び出す。
4. ログファイル（`mk-lambda-terminator.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。

### `make_iam_role()` — IAM ロール作成処理

5. 既存 IAM ロールのクリーンアップを行う:
   - 管理ポリシー（`AWSLambdaBasicExecutionRole`）をデタッチする（失敗は無視）。
   - インラインポリシー（`ts-010-policy-lambda-020`）を削除する（失敗は無視）。
   - ロールを削除する（失敗は無視）。
6. 信頼ポリシー JSON を生成する（Principal: `lambda.amazonaws.com`）。
7. `aws iam create-role` でロールを作成し、プロジェクトタグを付与する。
8. `aws iam attach-role-policy` で `AWSLambdaBasicExecutionRole` をアタッチする。
9. カスタムポリシー JSON を生成する（EC2 DescribeInstances・TerminateInstances 権限）。
10. `aws iam put-role-policy` でインラインポリシーをアタッチする。
11. `sleep 10` で IAM ロールの AWS 反映を待つ。

### `_deploy_lambda()` — Lambda デプロイ処理

12. `src/lambda/` ディレクトリで `zip` コマンドによりソースファイルを zip 化する。
13. `aws iam get-role` でロール ARN を取得する。
14. Lambda 関数の存在を確認する:
    - 存在する場合: `aws lambda update-function-code` でコードを更新し、`aws lambda wait function-updated` で完了を待つ。その後 `aws lambda update-function-configuration` で設定を更新する。
    - 存在しない場合: `aws lambda create-function` で新規作成する（ランタイム: python3.12、タイムアウト: 30 秒、メモリ: 128 MB）。

### メイン処理の流れ

15. `make_iam_role()` を呼び出して IAM ロールを作成する。
16. `_deploy_lambda()` を呼び出して Lambda 関数をデプロイする。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| IAM ロール | `ts-010-role-lambda-020` | 既存削除→新規作成 |
| インラインポリシー | `ts-010-policy-lambda-020` | 作成（EC2 権限） |
| Lambda 関数 | `ts-010-lmd-020` | 新規作成または更新 |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term; exit 1' ERR INT TERM` により、異常終了時は作業用一時ディレクトリを自動削除する。
- `trap 'term' EXIT` により、正常終了時も一時ディレクトリを削除する。
- IAM ロールのクリーンアップ処理は `> /dev/null 2>&1 || true` で失敗を無視する。
- すべての処理ログは `mk-lambda-terminator.sh.log` に記録される。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
