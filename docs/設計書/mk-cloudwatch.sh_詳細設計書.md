# mk-cloudwatch.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、プロジェクト用の CloudWatch ロググループ 3 本を作成します。既存の同名ロググループが存在する場合はログストリームを含めて削除してから再作成します。各ロググループには保持期間（30 日）・タグ・エラー監視用メトリックフィルターを設定します。

作成するリソース:
- CloudWatch ロググループ（保持期間: 30 日）
  - Lambda ログ: `ts-010-log-lambda-010`
  - EC2 ログ: `ts-010-log-ec2-010`
  - システムログ: `ts-010-log-system-010`
- メトリックフィルター（各ロググループにエラー監視フィルター設定）
  - Lambda 用: `ts-010-lambda-error-filter`（メトリック: `ts-010-lambda-errors`）
  - EC2 用: `ts-010-ec2-error-filter`（メトリック: `ts-010-ec2-errors`）
  - システム用: `ts-010-system-error-filter`（メトリック: `ts-010-system-errors`）

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli
- AWS 認証: `source assume-role.sh`（`ts-010-role-build` を AssumeRole）

---

## 3. 前提条件

特になし（他のリソースに依存しません）。

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `CW_LOG_GROUP_LAMBDA_NAME` | Lambda ロググループ名 | `ts-010-log-lambda-010` |
| `CW_LOG_GROUP_EC2_NAME` | EC2 ロググループ名 | `ts-010-log-ec2-010` |
| `CW_LOG_GROUP_SYSTEM_NAME` | システムロググループ名 | `ts-010-log-system-010` |
| `PRJ_PREFIX` | プロジェクトプレフィックス | `ts-010` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. 作業用一時ディレクトリ（`mk-cloudwatch.sh.src`）を作成する。
3. `trap` を設定し、ERR / INT / TERM シグナル発生時に `term()` を呼び出して一時ディレクトリを削除し、`exit 1` で終了する。EXIT シグナルでも `term()` を呼び出す。
4. ログファイル（`mk-cloudwatch.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。

### `confirm_cloudwatch()` — 実行前後の確認

5. `aws logs describe-log-groups` で `ts-010-log` プレフィックスのロググループ一覧を表示する。
6. Lambda・EC2・システムの各ロググループについて、名前・作成日時・保持期間・格納バイト数を表示する。

### `make_cloudwatch()` — ロググループ作成処理

7. Lambda ロググループ（`ts-010-log-lambda-010`）の処理:
   a. 既存ロググループが存在する場合:
      - ログストリーム一覧を取得し、各ストリームを `aws logs delete-log-stream` で削除する。
      - `aws logs delete-log-group` でロググループを削除する。
   b. `aws logs create-log-group` で新規ロググループを作成する。
   c. `aws logs put-retention-policy` で保持期間を 30 日に設定する。

8. EC2 ロググループ（`ts-010-log-ec2-010`）について手順 7 と同様の処理を行う。

9. システムロググループ（`ts-010-log-system-010`）について手順 7 と同様の処理を行う。

10. 3 つのロググループにタグを付与する（`aws logs tag-log-group`）:
    - 共通タグ: `Project`、`Component`（lambda / ec2 / system）、プロジェクトタグ

11. メトリックフィルターを作成する（`aws logs put-metric-filter`）:
    - フィルターパターン: `ERROR`（各ロググループ共通）
    - Lambda 用: メトリック名 `ts-010-lambda-errors`、名前空間 `ts-010/Lambda`
    - EC2 用: メトリック名 `ts-010-ec2-errors`、名前空間 `ts-010/EC2`
    - システム用: メトリック名 `ts-010-system-errors`、名前空間 `ts-010/System`

### メイン処理の流れ

12. 実行前に `confirm_cloudwatch()` を呼び出してリソース状態を記録する。
13. `make_cloudwatch()` を呼び出してリソースを作成する。
14. 実行後に `confirm_cloudwatch()` を再度呼び出して結果を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| CloudWatch ロググループ | `ts-010-log-lambda-010` | 既存削除→新規作成（保持期間 30 日） |
| CloudWatch ロググループ | `ts-010-log-ec2-010` | 既存削除→新規作成（保持期間 30 日） |
| CloudWatch ロググループ | `ts-010-log-system-010` | 既存削除→新規作成（保持期間 30 日） |
| メトリックフィルター | `ts-010-lambda-error-filter` | 作成（ERROR パターン） |
| メトリックフィルター | `ts-010-ec2-error-filter` | 作成（ERROR パターン） |
| メトリックフィルター | `ts-010-system-error-filter` | 作成（ERROR パターン） |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term; exit 1' ERR INT TERM` により、異常終了時は作業用一時ディレクトリを自動削除する。
- `trap 'term' EXIT` により、正常終了時も一時ディレクトリを削除する。
- ログストリームの削除は `|| true` で失敗を無視する（ストリームが存在しない場合に備えるため）。
- すべての処理ログは `mk-cloudwatch.sh.log` に記録される。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
