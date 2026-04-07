# mk-ec2-with-ssh.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、SSH 接続が可能なテスト用 EC2 インスタンス（`ts-010-ec2-ssh-010`）を作成します。既存の同名インスタンスが存在する場合は削除（Terminate）してから再作成します。作成後は SSH 接続に必要な情報（インスタンス ID・パブリック IP・SSH コマンド例）を表示します。

作成するリソース:
- EC2 インスタンス（名前: `ts-010-ec2-ssh-010`）
  - AMI: `ami-09ed31f8f34719e20`（デフォルト）
  - インスタンスタイプ: `t3.micro`
  - キーペア: `ts-010-keypair`
  - セキュリティグループ: `ts-010-sg-010`（SSH ルール追加済み）
  - サブネット: `ts-010-subnet-010`（パブリックサブネット）
  - IAM インスタンスプロファイル: `ts-010-role-ec2-010`
  - パブリック IP: 自動割り当て

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- mk-keypair.sh 詳細設計書（[設計書/mk-keypair.sh_詳細設計書.md](mk-keypair.sh_詳細設計書.md)）
- mk-sg-ssh.sh 詳細設計書（[設計書/mk-sg-ssh.sh_詳細設計書.md](mk-sg-ssh.sh_詳細設計書.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli
- AWS 認証: `source assume-role.sh`（`ts-010-role-build` を AssumeRole）

---

## 3. 前提条件

- VPC（`ts-010-vpc-010`）が作成済みであること
- サブネット（`ts-010-subnet-010`）が作成済みであること
- セキュリティグループ（`ts-010-sg-010`）が作成済みかつ SSH ルールが追加済みであること（`mk-sg-ssh.sh` 実行済み）
- キーペア（`ts-010-keypair`）が作成済みであること（`mk-keypair.sh` 実行済み）
- IAM インスタンスプロファイル（`ts-010-role-ec2-010`）が作成済みであること（`mk-role-ec2-010.sh` 実行済み）

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `VPC_NAME` | VPC の名前タグ | `ts-010-vpc-010` |
| `SUBNET_NAME` | サブネットの名前タグ | `ts-010-subnet-010` |
| `SG_NAME` | セキュリティグループ名 | `ts-010-sg-010` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 スクリプト内固定値

| 変数名 | 内容 | 値 |
|:---|:---|:---|
| `EC2_INSTANCE_NAME` | 作成する EC2 インスタンスの Name タグ | `ts-010-ec2-ssh-010` |
| `KEYPAIR_NAME` | 使用するキーペア名 | `ts-010-keypair` |
| `DEFAULT_AMI_ID` | 使用する AMI ID | `ami-09ed31f8f34719e20` |
| IAM ロール名 | インスタンスプロファイル名（スクリプト内固定） | `ts-010-role-ec2-010` |

### 4.3 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. 作業用一時ディレクトリ（`mk-ec2-with-ssh.sh.src`）を作成する。
3. `trap` を設定し、ERR / INT / TERM シグナル発生時に `term()` を呼び出して一時ディレクトリを削除し、`exit 1` で終了する。EXIT シグナルでも `term()` を呼び出す。
4. ログファイル（`mk-ec2-with-ssh.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。

### `confirm_resources()` — 前提リソース確認

5. `aws ec2 describe-vpcs` で VPC ID を確認する。見つからない場合は `exit 1` で終了する。
6. `aws ec2 describe-subnets` でサブネット ID を確認する。見つからない場合は `exit 1` で終了する。
7. `aws ec2 describe-security-groups` でセキュリティグループ ID を確認する。見つからない場合は `exit 1` で終了する。
8. `aws ec2 describe-key-pairs` でキーペアの存在を確認する。見つからない場合は `exit 1` で終了する。
9. `aws iam get-instance-profile` でインスタンスプロファイルの存在と ARN を確認する。見つからない場合は `exit 1` で終了する。

### `create_ec2_instance()` — EC2 インスタンス作成処理

10. `aws ec2 describe-instances` で同名の既存インスタンス（running / stopped / pending 状態）を検索する。
11. 既存インスタンスが存在する場合:
    - `aws ec2 terminate-instances` でインスタンスを削除する。
    - `aws ec2 wait instance-terminated` で削除完了を待機する。
12. `aws ec2 run-instances` で新規 EC2 インスタンスを作成する:
    - AMI: `DEFAULT_AMI_ID`、タイプ: `t3.micro`
    - キーペア・セキュリティグループ・サブネット・インスタンスプロファイルを指定
    - パブリック IP 自動割り当て有効
    - Name タグ・プロジェクトタグを付与
13. `aws ec2 wait instance-running` でインスタンスの起動完了を待機する。
14. `aws ec2 describe-instances` でパブリック IP アドレスを取得する。
15. SSH 接続情報（インスタンス ID・パブリック IP・SSH コマンド例）を表示する。

### メイン処理の流れ

16. `confirm_resources()` を呼び出して前提リソースを確認する。
17. `create_ec2_instance()` を呼び出して EC2 インスタンスを作成する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| EC2 インスタンス | `ts-010-ec2-ssh-010` | 既存削除→新規作成（t3.micro） |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term; exit 1' ERR INT TERM` により、異常終了時は作業用一時ディレクトリを自動削除する。
- `trap 'term' EXIT` により、正常終了時も一時ディレクトリを削除する。
- 各前提リソース（VPC / サブネット / SG / キーペア / インスタンスプロファイル）が見つからない場合は `exit 1` で終了する。
- すべての処理ログは `mk-ec2-with-ssh.sh.log` に記録される。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
