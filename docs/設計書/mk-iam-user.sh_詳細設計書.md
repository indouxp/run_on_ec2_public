# mk-iam-user.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、プロジェクト用 IAM ユーザー（`ts-010-user`）を作成し、構築用ロール（`ts-010-role-build`）と実行用ロール（`ts-010-role-exec`）への AssumeRole 権限、および CloudWatch Logs の閲覧権限を付与します。既存の同名ユーザーが存在する場合は削除してから再作成します。

作成するリソース:
- IAM ユーザー（名前: `ts-010-user`）
  - インラインポリシー（`ts-010-user-policy`）:
    - `ts-010-role-build` への AssumeRole 権限
    - `ts-010-role-exec` への AssumeRole 権限
    - CloudWatch Logs の閲覧権限（DescribeLogGroups / DescribeLogStreams / GetLogEvents / FilterLogEvents）

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
- AWS 認証: `AWS_PROFILE=ts-usr-admin`（IAM 操作のため直接プロファイル指定）

---

## 3. 前提条件

- 構築用ロール（`ts-010-role-build`）が作成済みであること
- 実行用ロール（`ts-010-role-exec`）が作成済みであること

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `IAM_USER_NAME` | 作成する IAM ユーザー名 | `ts-010-user` |
| `IAM_ROLE_BUILD_NAME` | AssumeRole を許可する構築用ロール名 | `ts-010-role-build` |
| `IAM_ROLE_EXEC_NAME` | AssumeRole を許可する実行用ロール名 | `ts-010-role-exec` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. 作業用一時ディレクトリ（`mk-iam-user.sh.src`）を作成する。
3. `trap` を設定し、ERR / INT / TERM シグナル発生時に `term()` を呼び出して一時ディレクトリを削除し、`exit 1` で終了する。EXIT シグナルでも `term()` を呼び出す。
4. ログファイル（`mk-iam-user.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。
5. `aws sts get-caller-identity` で AWS アカウント ID を取得する。
6. インラインポリシー名 `${IAM_USER_NAME}-policy` を設定する。

### `confirm_user()` — 実行前後の確認

7. `aws iam get-user` でユーザーの詳細を表示する（存在しない場合はその旨を表示）。
8. `aws iam list-user-policies` でインラインポリシー名一覧を表示する。

### `make_user()` — ユーザー作成処理

9. `aws iam get-user` で既存ユーザーの有無を確認する。
10. 既存ユーザーが存在する場合:
    a. `aws iam list-access-keys` でアクセスキー一覧を取得し、各キーを `aws iam delete-access-key` で削除する。
    b. `aws iam list-user-policies` でインラインポリシー名一覧を取得し、各ポリシーを `aws iam delete-user-policy` で削除する。
    c. `aws iam delete-user` でユーザーを削除する。
11. `aws iam create-user` でユーザーを作成し、プロジェクトタグを付与する。
12. AssumeRole ポリシー JSON（`user-assume-policy.json`）を作業ディレクトリに生成する。
    - Statement 1: `ts-010-role-build` / `ts-010-role-exec` への `sts:AssumeRole` を許可
    - Statement 2: CloudWatch Logs の閲覧アクション（全リソース対象）を許可
13. `aws iam put-user-policy` でインラインポリシーをアタッチする。

### メイン処理の流れ

14. 実行前に `confirm_user()` を呼び出してリソース状態を記録する。
15. `make_user()` を呼び出してリソースを作成する。
16. 実行後に `confirm_user()` を再度呼び出して結果を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| IAM ユーザー | `ts-010-user` | 既存削除（アクセスキー・ポリシー含む）→新規作成 |
| インラインポリシー | `ts-010-user-policy` | 作成（AssumeRole・CloudWatch Logs 閲覧権限） |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term; exit 1' ERR INT TERM` により、異常終了時は作業用一時ディレクトリを自動削除する。
- `trap 'term' EXIT` により、正常終了時も一時ディレクトリを削除する。
- ユーザー削除前にアクセスキーとインラインポリシーを先にすべて削除する（削除順序の遵守）。
- すべての処理ログは `mk-iam-user.sh.log` に記録される。

> **注意**: IAM ユーザー再作成後は、アクセスキーが削除されます。`reissue-accesskey.sh` を実行してアクセスキーを再発行し、AWS CLI の credentials を更新してください。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
