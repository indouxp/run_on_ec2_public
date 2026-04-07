# assume-role.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、`ts-010-role-build`（構築用）または `ts-010-role-exec`（実行用）へ AssumeRole し、取得した一時認証情報を環境変数（`AWS_ACCESS_KEY_ID`・`AWS_SECRET_ACCESS_KEY`・`AWS_SESSION_TOKEN`）に設定します。`source` コマンドで読み込んで使用するファイルです（直接実行は禁止）。

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- mk-role-build.sh 詳細設計書（[設計書/mk-role-build.sh_詳細設計書.md](mk-role-build.sh_詳細設計書.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli、python3
- 使用方法: `source assume-role.sh [build|exec]`
  - `build`: `ts-010-role-build` を AssumeRole（デフォルト）
  - `exec`: `ts-010-role-exec` を AssumeRole
- 直接実行禁止: `bash assume-role.sh` または `./assume-role.sh` での実行は不可

---

## 3. 前提条件

- `ts-010-user` の認証情報（デフォルトプロファイルまたは指定プロファイル）が設定済みであること
- `ts-010-user` が対象ロールへの `sts:AssumeRole` 権限を持つこと
- `config.sh` が同ディレクトリに存在すること

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

config.sh が未読み込みの場合（`PRJ_PREFIX` 環境変数が未設定の場合のみ）に自動読み込みされます。

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `IAM_ROLE_BUILD_NAME` | 構築用ロール名 | `ts-010-role-build` |
| `IAM_ROLE_EXEC_NAME` | 実行用ロール名 | `ts-010-role-exec` |

### 4.2 引数

| 引数 | 説明 | デフォルト |
|:---|:---|:---|
| `$1` | AssumeRole するロールタイプ（`build` または `exec`） | `build` |

---

## 5. 処理フロー

### 直接実行チェック

1. `BASH_SOURCE[0]` と `$0` が一致するかを確認する。一致する場合（直接実行）はエラーメッセージを表示して `exit 1` で終了する。

### 初期化

2. `BASH_SOURCE[0]` からスクリプト自身のディレクトリ（`_AR_SCRIPT_DIR`）を取得する。
3. `PRJ_PREFIX` 環境変数が未設定の場合のみ `config.sh` を読み込む。

### AssumeRole 処理

4. 第 1 引数（`_AR_ROLE_TYPE`）に応じてロール名（`_AR_ROLE_NAME`）を決定する:
   - `build` → `IAM_ROLE_BUILD_NAME`
   - `exec` → `IAM_ROLE_EXEC_NAME`
   - その他 → エラーメッセージを表示して `return 1` で終了する。
5. `aws sts get-caller-identity` で AWS アカウント ID（`_AR_ACCOUNT_ID`）を取得する。取得失敗の場合は `return 1` で終了する。
6. AssumeRole 対象 ARN（`_AR_ROLE_ARN`）を生成する: `arn:aws:iam::<AccountID>:role/<RoleName>`
7. セッション名（`_AR_SESSION_NAME`）を生成する: `${USER}-YYYYMMDDHHMMSS`
8. `aws sts assume-role` で一時認証情報（`_AR_CREDS`）を取得する。失敗した場合はエラーメッセージを表示して `return 1` で終了する。
9. `python3` で `_AR_CREDS` JSON を解析し、以下の環境変数を設定する:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN`
10. 有効期限（`_AR_EXPIRATION`）を取得して表示する。
11. `aws sts get-caller-identity` で設定後の ID を確認・表示する。

### 後処理

12. 使用した一時変数（`_AR_*`）をすべて `unset` して環境を汚染しないようにする。

---

## 6. 設定される環境変数

| 環境変数 | 内容 |
|:---|:---|
| `AWS_ACCESS_KEY_ID` | 一時アクセスキー ID |
| `AWS_SECRET_ACCESS_KEY` | 一時シークレットアクセスキー |
| `AWS_SESSION_TOKEN` | セッショントークン |

> **注意**: 設定した環境変数は `AWS_PROFILE` より優先されます。`info-all.sh` 実行前など、プロファイルに戻す必要がある場合は `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN` を実行してください。

---

## 7. エラーハンドリング

- 直接実行された場合は `exit 1` で即時終了する。
- AWS アカウント ID の取得失敗、AssumeRole 失敗、不明なロールタイプ指定の場合は `return 1`（`source` 環境ではシェルを終了させない）でエラー終了する。
- 処理ログのリダイレクトはなし（標準出力に直接表示）。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
