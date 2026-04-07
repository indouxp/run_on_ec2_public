# mk-role-ec2-010.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、EC2 インスタンスが使用する IAM ロール（`ts-010-role-ec2-010`）とインスタンスプロファイルを作成します。既存の同名ロール・プロファイルが存在する場合は削除してから再作成します。

作成するリソース:
- IAM ロール（名前: `ts-010-role-ec2-010`）
  - 信頼ポリシー: `ec2.amazonaws.com` による AssumeRole を許可
  - 管理ポリシー: `CloudWatchAgentServerPolicy`
  - インラインポリシー（`ts-010-policy-ec2-010`）:
    - S3 入力バケット（`${BKT_IN}`）への GetObject・ListBucket 権限
    - S3 出力バケット（`${BKT_OUT}`）への PutObject・ListBucket 権限
    - SNS Publish 権限
    - SES SendEmail・SendRawEmail 権限
    - CloudWatch Logs 書き込み権限（`ts-010-log-*` グループのみ）
    - EC2 TerminateInstances 権限（`ts-010-ec2-010` タグ付きインスタンスのみ）
- IAM インスタンスプロファイル（名前: `ts-010-role-ec2-010`）

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）
- セキュリティ設定（[設計書/セキュリティ設定.md](セキュリティ設定.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli
- AWS 認証: `AWS_PROFILE=ts-usr-admin`（IAM 操作のため直接プロファイル指定）

---

## 3. 前提条件

- S3 バケット（`${BKT_IN}`、`${BKT_OUT}`）が作成済みであること
- CloudWatch ロググループ（`ts-010-log-*`）が作成済みであること（参照のみ）

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `IAM_ROLE_EC2_NAME` | 作成する IAM ロールおよびインスタンスプロファイルの名前 | `ts-010-role-ec2-010` |
| `IAM_POLICY_EC2_NAME` | インラインポリシーの名前 | `ts-010-ec2-custom-policy` |
| `S3_BKT_IN_NAME` | EC2 が読み取る入力 S3 バケット名 | `${BKT_IN}` |
| `S3_BKT_OUT_NAME` | EC2 が書き込む出力 S3 バケット名 | `${BKT_OUT}` |
| `AWS_REGION` | AWSリージョン | `ap-northeast-1` |
| `PRJ_PREFIX` | プロジェクトプレフィックス | `ts-010` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. 作業用一時ディレクトリ（`mk-role-ec2-010.sh.src`）を作成する。作成できない場合はエラー終了する。
3. `trap` を設定し、ERR / INT / TERM シグナル発生時に `term()` を呼び出して一時ディレクトリを削除し、`exit 1` で終了する。EXIT シグナルでも `term()` を呼び出す。
4. ログファイル（`mk-role-ec2-010.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。

### `confirm_role()` — 実行前後の確認

5. `aws iam list-roles` でプロジェクトプレフィックスのロール一覧を表示する。
6. `aws iam get-role` で EC2 実行ロールの詳細を表示する（存在しない場合はその旨を表示）。
7. アタッチ済み管理ポリシー一覧とインラインポリシー名一覧を表示する。
8. `aws iam get-instance-profile` でインスタンスプロファイルの詳細を表示する。

### `make_role()` — ロール作成処理

9. 既存のインスタンスプロファイルからロールを解除する（`aws iam remove-role-from-instance-profile`）。
10. 既存のインスタンスプロファイルを削除する（`aws iam delete-instance-profile`）。
11. 既存のインラインポリシーを削除する（`aws iam delete-role-policy`）。
12. 管理ポリシー `CloudWatchAgentServerPolicy` をデタッチする（`aws iam detach-role-policy`）。
13. 既存ロールを削除する（`aws iam delete-role`）。
14. 信頼ポリシー JSON（`trust-policy-ec2.json`）を作業ディレクトリに生成する。
    - Principal: `ec2.amazonaws.com`、Action: `sts:AssumeRole`
15. `aws iam create-role` でロールを作成し、プロジェクトタグを付与する。
16. `aws iam attach-role-policy` で `CloudWatchAgentServerPolicy` 管理ポリシーをアタッチする。
17. カスタムポリシー JSON（`ec2-custom-policy.json`）を作業ディレクトリに生成する。
18. `aws iam put-role-policy` でインラインポリシーをアタッチする。
19. `aws iam create-instance-profile` でインスタンスプロファイルを作成し、プロジェクトタグを付与する。
20. `aws iam add-role-to-instance-profile` でインスタンスプロファイルにロールを関連付ける。
21. AWS 反映待ちとして `sleep 10` を実行する。

### メイン処理の流れ

22. 実行前に `confirm_role()` を呼び出してリソース状態を記録する。
23. `make_role()` を呼び出してリソースを作成する。
24. 実行後に `confirm_role()` を再度呼び出して結果を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| IAM ロール | `ts-010-role-ec2-010` | 既存削除→新規作成 |
| 管理ポリシーアタッチ | `CloudWatchAgentServerPolicy` | アタッチ |
| インラインポリシー | `ts-010-policy-ec2-010` | 作成（S3/SNS/SES/CloudWatch/EC2 権限） |
| インスタンスプロファイル | `ts-010-role-ec2-010` | 既存削除→新規作成・ロール関連付け |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `trap 'term; exit 1' ERR INT TERM` により、異常終了時は作業用一時ディレクトリを自動削除する。
- `trap 'term' EXIT` により、正常終了時も一時ディレクトリを削除する。
- 既存リソースの削除処理（ロール解除・プロファイル削除・ポリシー削除・デタッチ）は `|| true` または `2>/dev/null &&` で失敗を無視する（リソースが存在しない場合に備えるため）。
- すべての処理ログは `mk-role-ec2-010.sh.log` に記録される。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
