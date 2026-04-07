# mk-igw.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、プロジェクト用のインターネットゲートウェイ（IGW）を作成し、既存の VPC にアタッチします。既存の同名 IGW が存在する場合は VPC からデタッチして削除してから再作成します。

作成・更新するリソース:
- インターネットゲートウェイ（名前: `ts-010-igw-010`）
- IGW を VPC（`ts-010-vpc-010`）へアタッチ

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
| `VPC_NAME` | アタッチ先 VPC の名前タグ | `ts-010-vpc-010` |
| `IGW_NAME` | 作成する IGW の名前タグ | `ts-010-igw-010` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. ログファイル（`mk-igw.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。

### `confirm_igw()` — 実行前後の確認

3. `aws ec2 describe-internet-gateways` で `Name` タグが `IGW_NAME` に一致する IGW を検索し、InternetGatewayId・Attachments を JSON 形式で出力する。IGW が存在しない場合はその旨を表示する。

### `create_and_attach_igw()` — IGW 作成・アタッチ処理

4. `aws ec2 describe-vpcs` で `VPC_NAME` に一致する VPC ID を取得する。VPC が存在しない場合（結果が `None`）はエラーメッセージを出力して `exit 1` で終了する。
5. `aws ec2 describe-internet-gateways` で既存 IGW の ID を取得する。
6. 既存 IGW が存在する場合（結果が `None` でない場合）:
   a. アタッチされている VPC ID を取得する。
   b. アタッチされている場合は `aws ec2 detach-internet-gateway` でデタッチし、5 秒待機する。
   c. `aws ec2 delete-internet-gateway` で IGW を削除し、5 秒待機する。
7. `aws ec2 create-internet-gateway` で新規 IGW を作成し、IGW ID を取得する。
8. `aws ec2 create-tags` で IGW に `Name` タグ（値: `IGW_NAME`）とプロジェクトタグ（`PRJ_TAG_KEY=PRJ_TAG_VALUE`）を付与する。
9. `aws ec2 attach-internet-gateway` で IGW を VPC にアタッチする。

### メイン処理の流れ

10. 実行前に `confirm_igw()` を呼び出してリソース状態を記録する。
11. `create_and_attach_igw()` を呼び出してリソースを作成・アタッチする。
12. 実行後に `confirm_igw()` を再度呼び出して結果を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| インターネットゲートウェイ | `ts-010-igw-010` | 既存デタッチ・削除→新規作成 |
| IGW アタッチ | `ts-010-vpc-010` への接続 | 新規 IGW を VPC にアタッチ |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- 親 VPC が見つからない場合は明示的な `exit 1` でエラー終了する。
- IGW デタッチ後・削除後に `sleep 5` を挿入し、AWS の反映待ちを行う。
- すべての処理ログは `mk-igw.sh.log` に記録される。

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
