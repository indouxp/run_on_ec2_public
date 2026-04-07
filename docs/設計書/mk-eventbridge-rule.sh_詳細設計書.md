# mk-eventbridge-rule.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、EC2 インスタンスの停止イベントを検知して Lambda 関数（`ts-010-lmd-020`）を呼び出す EventBridge ルール（`ts-010-rule-stop-ec2-trigger`）を作成します。既存の同名ルールが存在する場合は削除してから再作成します。

作成するリソース:
- EventBridge ルール（名前: `ts-010-rule-stop-ec2-trigger`）
  - イベントパターン: EC2 インスタンス状態変化通知（`stopped` 状態）
  - ターゲット: Lambda 関数 `ts-010-lmd-020`
- Lambda への呼び出し許可（`lambda:InvokeFunction`）

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- mk-lambda-terminator.sh 詳細設計書（[設計書/mk-lambda-terminator.sh_詳細設計書.md](mk-lambda-terminator.sh_詳細設計書.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli
- AWS 認証: `source assume-role.sh`（`ts-010-role-build` を AssumeRole）

---

## 3. 前提条件

- Lambda 関数（`ts-010-lmd-020`）が作成済みであること（`mk-lambda-terminator.sh` 実行済み）

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
| `RULE_NAME` | EventBridge ルール名 | `ts-010-rule-stop-ec2-trigger` |
| `LAMBDA_FUNC_NAME` | ターゲット Lambda 関数名 | `ts-010-lmd-020` |

### 4.3 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. ログファイル（`mk-eventbridge-rule.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。

> 注意: 本スクリプトは `MY_SRC_DIR`（作業用一時ディレクトリ）を使用しません。

### `make_rule()` — EventBridge ルール作成処理

3. 既存ルールが存在する場合:
   a. `aws events remove-targets` でターゲット（ID: `1`）を削除する（失敗は無視）。
   b. `aws lambda remove-permission` で Lambda の呼び出し許可を削除する（失敗は無視）。
   c. `aws events delete-rule` でルールを削除する。
4. イベントパターン JSON を生成する:
   - source: `aws.ec2`
   - detail-type: `EC2 Instance State-change Notification`
   - detail.state: `stopped`
5. `aws events put-rule` でルールを作成する（状態: ENABLED、プロジェクトタグ付与）。
6. `aws lambda get-function` で Lambda 関数の ARN を取得する。ARN が取得できない場合はエラー終了する。
7. `aws lambda add-permission` で Lambda 関数に EventBridge からの呼び出し許可を追加する（既に存在する場合はスキップ）。
8. `aws events put-targets` でルールのターゲットとして Lambda 関数（ID: `1`）を設定する。

### メイン処理の流れ

9. `make_rule()` を呼び出してルールを作成する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| EventBridge ルール | `ts-010-rule-stop-ec2-trigger` | 既存削除→新規作成 |
| Lambda 呼び出し許可 | `EventBridgeInvoke-ts-010-rule-stop-ec2-trigger` | 追加 |
| EventBridge ターゲット | `ts-010-lmd-020`（ID: `1`） | 設定 |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- 既存ルールのターゲット削除・Lambda 許可削除は `|| true` で失敗を無視する。
- Lambda 関数が見つからない場合はエラーメッセージを出力して `exit 1` で終了する。
- Lambda への呼び出し許可追加（`add-permission`）は既に存在する場合にエラーとなるため `|| echo "..."` でスキップする。
- すべての処理ログは `mk-eventbridge-rule.sh.log` に記録される。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
