# mk-subnet.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、プロジェクト用のサブネットを VPC 内に作成します。既存の同名サブネットが存在する場合は削除してから再作成します。

作成するリソース:
- サブネット（名前: `ts-010-subnet-010`、CIDR: `10.0.1.0/24`、VPC: `ts-010-vpc-010`）

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

| リソース | リソース名 | 確認方法 |
|:---|:---|:---|
| VPC | `ts-010-vpc-010` | `mk-vpc.sh` で作成済みであること |

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `VPC_NAME` | 作成先 VPC の名前タグ | `ts-010-vpc-010` |
| `SUBNET_NAME` | 作成するサブネットの名前タグ | `ts-010-subnet-010` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. ログファイル（`mk-subnet.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。
3. 作業用一時ディレクトリ（`mk-subnet.sh.src`）を作成する。作成できない場合はエラー終了する。
4. `trap` を設定し、ERR / INT / TERM シグナル発生時に `term()` を呼び出して一時ディレクトリを削除し、`exit 1` で終了する。EXIT シグナルでも `term()` を呼び出す。

### `confirm_subnet()` — 実行前後の確認

5. `aws ec2 describe-subnets` で `Name` タグが `SUBNET_NAME` に一致するサブネットを検索し、SubnetId・CidrBlock・VpcId・Tags を JSON 形式で出力する。サブネットが存在しない場合はその旨を表示する。

### `make_subnet()` — サブネット作成処理

6. `aws ec2 describe-vpcs` で `VPC_NAME` に一致する VPC ID を取得する。VPC が存在しない場合（結果が `None`）はエラーメッセージを出力して `exit 1` で終了する。
7. `aws ec2 describe-subnets` で既存サブネットの ID を取得する（VPC ID でも絞り込む）。
8. 既存サブネットが存在する場合（結果が `None` でない場合）、`aws ec2 delete-subnet` で削除し、5 秒待機する（AWS の反映待ち）。
9. `aws ec2 create-subnet` で VPC 内に CIDR `10.0.1.0/24` のサブネットを作成し、サブネット ID を取得する。
10. `aws ec2 create-tags` でサブネットに `Name` タグ（値: `SUBNET_NAME`）とプロジェクトタグ（`PRJ_TAG_KEY=PRJ_TAG_VALUE`）を付与する。

### メイン処理の流れ

11. 実行前に `confirm_subnet()` を呼び出してリソース状態を記録する。
12. `make_subnet()` を呼び出してリソースを作成する。
13. 実行後に `confirm_subnet()` を再度呼び出して結果を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| サブネット | `ts-010-subnet-010` | 既存削除→新規作成（CIDR: `10.0.1.0/24`） |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term; exit 1' ERR INT TERM` により、異常終了時は作業用一時ディレクトリ（`mk-subnet.sh.src`）を自動削除する。
- `trap 'term' EXIT` により、正常終了時も一時ディレクトリを削除する。
- 親 VPC が見つからない場合は明示的な `exit 1` でエラー終了する。
- サブネット削除後に `sleep 5` を挿入し、AWS の反映待ちを行う。
- すべての処理ログは `mk-subnet.sh.log` に記録される。

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
