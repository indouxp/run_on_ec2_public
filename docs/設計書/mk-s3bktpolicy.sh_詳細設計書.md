# mk-s3bktpolicy.sh 詳細設計書

## 1. 概要

### 1.1 目的

本ドキュメントは、S3バケットポリシー設定スクリプト `mk-s3bktpolicy.sh` の詳細設計を定義します。

本スクリプトは以下のAWSリソースに対してバケットポリシーを設定します。

- **入力バケット** `${BKT_IN}`: LambdaロールおよびEC2ロールに `s3:GetObject`・`s3:ListBucket` を許可
- **出力バケット** `${BKT_OUT}`: LambdaロールおよびEC2ロールに `s3:PutObject`・`s3:ListBucket` を許可

いずれも既存ポリシーを削除してから新規ポリシーを適用する（削除→再作成）方式です。また両バケットにバケット所有者制御（`BucketOwnerEnforced`）を設定します。

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）
- mk-s3bkt.sh 詳細設計書（[設計書/mk-s3bkt.sh_詳細設計書.md](mk-s3bkt.sh_詳細設計書.md)）

## 2. 実行環境

- **実行場所**: `infra/` ディレクトリ
- **必要コマンド**: aws cli, jq
- **AWS認証**: `source assume-role.sh`（ts-010-role-build を AssumeRole）

## 3. 前提条件

| 条件 | 内容 |
|:---|:---|
| AWS認証 | ts-010-role-build の AssumeRole が有効であること |
| S3バケット | `${BKT_IN}` および `${BKT_OUT}` が作成済みであること |
| IAMロール | `ts-010-role-lambda-010` および `ts-010-role-ec2-010` が作成済みであること（ポリシーのPrincipal ARNに使用） |

> **注意**: 本スクリプトは `mk-s3bkt.sh` から自動呼び出しされる場合があります。

## 4. 入力

### 4.1 設定ファイル（config.sh）

本スクリプトは `config.sh` を直接 `source` しません。バケット名およびIAMロール名はスクリプト内にハードコードされています。AWSアカウントIDは実行時に `aws sts get-caller-identity` で動的に取得します。

| 使用値 | 内容 | 値 |
|:---|:---|:---|
| バケット名（入力） | 入力バケット名 | `${BKT_IN}` |
| バケット名（出力） | 出力バケット名 | `${BKT_OUT}` |
| Lambdaロール名 | ポリシーのPrincipal | `ts-010-role-lambda-010` |
| EC2ロール名 | ポリシーのPrincipal | `ts-010-role-ec2-010` |
| AWSアカウントID | ARN構築用（動的取得） | 実行時取得 |

### 4.2 引数

なし。

## 5. 処理フロー

### 初期化処理

1. `set -euo pipefail` によるエラー時即時終了を設定する
2. 作業用一時ディレクトリ `./mk-s3bktpolicy.sh.src` を作成する
3. トラップを設定する（ERR/INT/TERM 時は一時ディレクトリ削除後に終了、EXIT 時は削除）
4. 以降の標準出力・標準エラー出力を `mk-s3bktpolicy.sh.log` にリダイレクトする

### confirm_s3policy 関数（実行前確認）

5. `aws s3api get-bucket-policy` で `${BKT_IN}` の既存ポリシーを取得し `jq` で整形表示する
   （ポリシーなしの場合はメッセージを出力する）
6. `aws s3api get-bucket-policy` で `${BKT_OUT}` の既存ポリシーを取得し `jq` で整形表示する
   （ポリシーなしの場合はメッセージを出力する）
7. `aws s3api get-bucket-acl` で `${BKT_IN}` のACLを表示する
   （権限不足の場合はスキップメッセージを出力する）
8. `aws s3api get-bucket-acl` で `${BKT_OUT}` のACLを表示する
   （権限不足の場合はスキップメッセージを出力する）

### make_s3policy 関数（ポリシー設定）

9. `aws sts get-caller-identity` でAWSアカウントIDを取得する

**入力バケット（${BKT_IN}）のポリシー設定:**

10. `aws s3api delete-bucket-policy` で既存ポリシーを削除する（ポリシーなしの場合はメッセージを出力して継続）
11. ポリシーJSONファイル `${BKT_IN}-policy.json` を一時ディレクトリに生成する
    - Statement 1（`AllowLambdaRoleAccess`）: `ts-010-role-lambda-010` に `s3:GetObject`・`s3:ListBucket` を許可
    - Statement 2（`AllowEC2RoleAccess`）: `ts-010-role-ec2-010` に `s3:GetObject`・`s3:ListBucket` を許可
    - リソース対象: バケット本体（`arn:aws:s3:::${BKT_IN}`）とオブジェクト（`arn:aws:s3:::${BKT_IN}/*`）
12. `aws s3api put-bucket-policy` で生成したJSONをバケットポリシーとして適用する

**出力バケット（${BKT_OUT}）のポリシー設定:**

13. `aws s3api delete-bucket-policy` で既存ポリシーを削除する（ポリシーなしの場合はメッセージを出力して継続）
14. ポリシーJSONファイル `${BKT_OUT}-policy.json` を一時ディレクトリに生成する
    - Statement 1（`AllowLambdaRoleAccess`）: `ts-010-role-lambda-010` に `s3:PutObject`・`s3:ListBucket` を許可
    - Statement 2（`AllowEC2RoleAccess`）: `ts-010-role-ec2-010` に `s3:PutObject`・`s3:ListBucket` を許可
    - リソース対象: バケット本体（`arn:aws:s3:::${BKT_OUT}`）とオブジェクト（`arn:aws:s3:::${BKT_OUT}/*`）
15. `aws s3api put-bucket-policy` で生成したJSONをバケットポリシーとして適用する

**バケット所有者制御設定:**

16. `aws s3api put-bucket-ownership-controls` で `${BKT_IN}` に `BucketOwnerEnforced` を設定する
    （エラーが発生した場合はスキップし警告を出力する）
17. `aws s3api put-bucket-ownership-controls` で `${BKT_OUT}` に `BucketOwnerEnforced` を設定する
    （エラーが発生した場合はスキップし警告を出力する）

**Lambda通知設定サンプルファイル生成:**

18. Lambda通知設定サンプルJSONファイル `notification-config-sample.json` を一時ディレクトリに生成する
    （実際の通知設定は `mk-s3-trigger.sh` が行う）

### confirm_s3policy 関数（実行後確認）

19. 手順5〜8と同様に、設定後のバケットポリシーおよびACLを確認・表示する

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| S3バケットポリシー | `${BKT_IN}` | 既存削除・新規作成（Lambda/EC2ロールの GetObject・ListBucket 許可） |
| S3バケットポリシー | `${BKT_OUT}` | 既存削除・新規作成（Lambda/EC2ロールの PutObject・ListBucket 許可） |
| S3バケット所有者制御 | `${BKT_IN}` | `BucketOwnerEnforced` 設定 |
| S3バケット所有者制御 | `${BKT_OUT}` | `BucketOwnerEnforced` 設定 |

## 7. エラーハンドリング

| 状況 | 対処 |
|:---|:---|
| `set -euo pipefail` | コマンド失敗・未定義変数参照・パイプエラー時に即時終了する |
| ERR/INT/TERM シグナル | `term` 関数を呼び出し、一時ディレクトリを削除後に `exit 1` |
| EXIT | `term` 関数を呼び出し、一時ディレクトリを削除する（正常終了時も含む） |
| ポリシー削除失敗（ポリシーなし） | `|| echo "..."` でエラーを吸収し、処理を継続する |
| ACL確認失敗（権限不足） | `2>/dev/null || echo "..."` でエラーを吸収し、スキップメッセージを出力する |
| バケット所有者制御設定失敗 | `2>/dev/null && ... || echo "..."` でエラーを吸収し、スキップメッセージを出力する |

> **注意**: Explicit Deny を含むポリシーをバケットに設定すると、ルートユーザーを含む全アクセスが遮断されるリスクがあります。本スクリプトのポリシーは Allow のみで構成されています。

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
