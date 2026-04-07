# mk-vpc.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、プロジェクト用の VPC（Virtual Private Cloud）を作成します。既存の同名 VPC が存在する場合は削除してから再作成します。作成後、DNS ホスト名および DNS 解決を有効化します。

作成するリソース:
- VPC（名前: `ts-010-vpc-010`、CIDR: `10.0.0.0/16`）

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli
- AWS認証: `source assume-role.sh`（`ts-010-role-build` を AssumeRole）

---

## 3. 前提条件

特になし（本スクリプトがネットワーク構築の最初のステップです）。

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `VPC_NAME` | 作成する VPC の名前タグ | `ts-010-vpc-010` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. ログファイル（`mk-vpc.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。
3. 作業用一時ディレクトリ（`mk-vpc.sh.src`）を作成する。作成できない場合はエラー終了する。
4. `trap` を設定し、ERR / INT / TERM シグナル発生時に `term()` を呼び出して一時ディレクトリを削除し、`exit 1` で終了する。EXIT シグナルでも `term()` を呼び出す。

### `confirm_vpc()` — 実行前後の確認

5. `aws ec2 describe-vpcs` で `Name` タグが `VPC_NAME` に一致する VPC を検索し、VpcId・CidrBlock・Tags を JSON 形式で出力する。VPC が存在しない場合はその旨を表示する。

### `make_vpc()` — VPC 作成処理

6. `aws ec2 describe-vpcs` で既存 VPC の ID を取得する。
7. 既存 VPC が存在する場合（結果が `None` でない場合）、`aws ec2 delete-vpc` で削除する。
8. `aws ec2 create-vpc` で CIDR `10.0.0.0/16` の新規 VPC を作成し、VPC ID を取得する。
9. `aws ec2 create-tags` で VPC に `Name` タグ（値: `VPC_NAME`）とプロジェクトタグ（`PRJ_TAG_KEY=PRJ_TAG_VALUE`）を付与する。
10. `aws ec2 modify-vpc-attribute` で DNS ホスト名（`enableDnsHostnames`）を有効化する。
11. `aws ec2 modify-vpc-attribute` で DNS 解決（`enableDnsSupport`）を有効化する。

### メイン処理の流れ

12. 実行前に `confirm_vpc()` を呼び出してリソース状態を記録する。
13. `make_vpc()` を呼び出してリソースを作成する。
14. 実行後に `confirm_vpc()` を再度呼び出して結果を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| VPC | `ts-010-vpc-010` | 既存削除→新規作成（CIDR: `10.0.0.0/16`） |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term; exit 1' ERR INT TERM` により、異常終了時は作業用一時ディレクトリ（`mk-vpc.sh.src`）を自動削除する。
- `trap 'term' EXIT` により、正常終了時も一時ディレクトリを削除する。
- すべての処理ログは `mk-vpc.sh.log` に記録される。

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
