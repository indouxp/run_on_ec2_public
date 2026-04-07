# reissue-accesskey.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、`ts-010-user` の新しいアクセスキーを発行し、AWS CLI のデフォルトプロファイルの認証情報（`aws_access_key_id` / `aws_secret_access_key`）を更新します。IAM ユーザー（`ts-010-user`）を再作成した後や、定期的なキーローテーション時に使用します。

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- mk-iam-user.sh 詳細設計書（[設計書/mk-iam-user.sh_詳細設計書.md](mk-iam-user.sh_詳細設計書.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ（または任意のディレクトリ）
- 必要コマンド: aws cli、awk、cut
- AWS 認証: `AWS_PROFILE=ts-usr-admin`（IAM 操作のため `ts-usr-admin` プロファイルを明示指定）
- 実行方法: `./reissue-accesskey.sh`（直接実行）

---

## 3. 前提条件

- `ts-usr-admin` プロファイルに `iam:CreateAccessKey` 権限があること
- `ts-010-user` が既に作成済みであること
- `ts-010-user` のアクセスキー数が上限（2 個）に達していないこと（既存キーを事前に削除すること）

---

## 4. 入力

### 4.1 設定ファイル

設定ファイルを使用しません。

### 4.2 スクリプト内固定値

| 変数名 | 内容 | 値 |
|:---|:---|:---|
| `SCRIPT_NAME` | スクリプト名 | `reissue-accesskey.sh` |
| `TMP_NAME` | 一時ファイル名 | `reissue-accesskey.sh.tmp` |
| `TMP_PATH` | 一時ファイルのフルパス | `/tmp/reissue-accesskey.sh.tmp` |

### 4.3 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. スクリプト名（`SCRIPT_NAME`）・一時ファイルパス（`TMP_PATH`）を設定する。
2. `trap 'term' 0` で終了時に `term()` を呼び出し、一時ファイル（`/tmp/reissue-accesskey.sh.tmp`）を削除する。
3. `set -euo pipefail` を設定する。

### アクセスキー発行

4. `AWS_PROFILE=ts-usr-admin aws iam create-access-key --user-name ts-010-user` でアクセスキーを発行する。
5. `awk` でキー情報（`AccessKeyId` / `SecretAccessKey`）を `AccessKeyId:SecretAccessKey` 形式に整形して一時ファイルに保存する。

### 安全性チェック

6. `SecretAccessKey` に `:` が含まれる場合、`cut` による分割が不正になるためエラー終了する。（この事態は実際には発生しないが、防御的チェックとして実施）

### 認証情報更新

7. `cut -d: -f1` で `AccessKeyId` を取得する。
8. `cut -d: -f2` で `SecretAccessKey` を取得する。
9. `aws configure set aws_access_key_id` でデフォルトプロファイルのアクセスキー ID を更新する。
10. `aws configure set aws_secret_access_key` でデフォルトプロファイルのシークレットアクセスキーを更新する。
11. `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN` で AssumeRole 環境変数をクリアし、更新した credentials ファイルの設定を有効にする。
12. `sleep 10` で IAM アクセスキーの AWS 内伝播を待つ（新規キーは即時有効にならない場合がある）。
13. `aws sts get-caller-identity` で新しいアクセスキーでの認証が成功することを確認する。

---

## 6. 更新内容

| 対象 | 内容 |
|:---|:---|
| `~/.aws/credentials` デフォルトプロファイル | `aws_access_key_id`・`aws_secret_access_key` を更新 |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term' 0` により、終了時（正常・異常問わず）に一時ファイルを削除する。
- `SecretAccessKey` に `:` が含まれる場合は `exit 1` で終了する（エラーメッセージを標準エラー出力に表示）。
- ログファイルへのリダイレクトはなし（標準出力に直接表示）。

> **注意**: `ts-010-user` のアクセスキーは最大 2 個までです。上限に達している場合は既存のアクセスキーを手動で削除してから実行してください。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
