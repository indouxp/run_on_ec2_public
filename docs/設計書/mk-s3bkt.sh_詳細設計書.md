# mk-s3bkt.sh 詳細設計書

## 1. 概要

### 1.1 目的

本ドキュメントは、S3バケット作成スクリプト `mk-s3bkt.sh` の詳細設計を定義します。

本スクリプトは以下のAWSリソースを作成・設定します。

- **入力バケット** `${BKT_IN}`: EC2で処理するスクリプトや入力データを格納する読み取り専用バケット
- **出力バケット** `${BKT_OUT}`: EC2の処理結果・ログを格納する書き込み専用バケット

両バケットに対して以下のセキュリティ設定を行います。

- パブリックアクセスブロック設定（全ブロック有効化）
- サーバーサイド暗号化設定（AES256 / BucketKey有効）
- プロジェクトタグ付与

バケット作成完了後、後続設定スクリプト（`mk-s3bktpolicy.sh`、`mk-s3-trigger.sh`）を自動実行します。

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）

**派生文書**
- mk-s3bktpolicy.sh 詳細設計書（[設計書/mk-s3bktpolicy.sh_詳細設計書.md](mk-s3bktpolicy.sh_詳細設計書.md)）
- mk-s3-trigger.sh 詳細設計書（[設計書/mk-s3-trigger.sh_詳細設計書.md](mk-s3-trigger.sh_詳細設計書.md)）
- mk-s3-lifecicle.sh 詳細設計書（[設計書/mk-s3-lifecicle.sh_詳細設計書.md](mk-s3-lifecicle.sh_詳細設計書.md)）

## 2. 実行環境

- **実行場所**: `infra/` ディレクトリ
- **必要コマンド**: aws cli, jq
- **AWS認証**: `source assume-role.sh`（ts-010-role-build を AssumeRole）

## 3. 前提条件

| 条件 | 内容 |
|:---|:---|
| AWS認証 | ts-010-role-build の AssumeRole が有効であること |
| config.sh | `infra/` ディレクトリに config.sh が存在すること |
| Lambda関数（任意） | S3トリガー自動設定を行う場合は `ts-010-lmd-010` が作成済みであること（未作成の場合はトリガー設定をスキップし警告を出力） |

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `AWS_REGION` | AWSリージョン | `ap-northeast-1` |
| `PRJ_PREFIX` | プロジェクトプレフィックス | `ts-010` |
| `S3_BKT_IN_NAME` | 入力バケット名 | `${BKT_IN}` |
| `S3_BKT_OUT_NAME` | 出力バケット名 | `${BKT_OUT}` |
| `S3_TRIGGER_ID` | S3トリガーID | `ts-010-lambda-trigger` |
| `LAMBDA_FUNC_NAME` | Lambda関数名 | `ts-010-lmd-010` |
| `PRJ_TAG_KEY` | タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | タグ値 | `ts-010` |

### 4.2 引数

なし。

## 5. 処理フロー

### 初期化処理

1. `set -euo pipefail` によるエラー時即時終了を設定する
2. `config.sh` を読み込む
3. 作業用一時ディレクトリ `./mk-s3bkt.sh.src` を作成する
4. トラップを設定する（ERR/INT/TERM 時は一時ディレクトリ削除後に終了、EXIT 時は一時ディレクトリを削除）
5. 以降の標準出力・標準エラー出力を `mk-s3bkt.sh.log` にリダイレクトする

### confirm_s3bucket 関数（実行前確認）

6. `aws s3api list-buckets` で `${PRJ_PREFIX}-bkt` プレフィックスを持つバケット一覧を表示する
7. `aws s3api head-bucket` で入力バケットの存在確認と `get-bucket-location` でリージョンを表示する
8. `aws s3api head-bucket` で出力バケットの存在確認と `get-bucket-location` でリージョンを表示する

### make_s3bucket 関数（バケット作成）

**入力バケット（${BKT_IN}）の処理:**

9. `aws s3api head-bucket` でバケットの存在確認を行う
10. バケットが既存の場合、以下の手順で削除する
    - バージョニングを Suspended に設定する（削除前準備）
    - `aws s3 rm --recursive` でオブジェクトを全削除する
    - `aws s3api list-object-versions` と `jq` でバージョン付きオブジェクト・削除マーカーのリストを作成し、`aws s3api delete-objects` で削除する
    - `aws s3api delete-bucket` でバケットを削除する
11. `aws s3api create-bucket` で入力バケットを `--create-bucket-configuration LocationConstraint` 付きで作成する
12. `aws s3api put-bucket-tagging` でプロジェクトタグ（`PRJ_TAG_KEY=PRJ_TAG_VALUE`）を設定する

**出力バケット（${BKT_OUT}）の処理:**

13. 入力バケットと同様の手順（手順9〜12）で出力バケットを削除・再作成する

**セキュリティ設定:**

14. `aws s3api put-public-access-block` で入力バケットのパブリックアクセスを全ブロックする
    （`BlockPublicAcls=true, IgnorePublicAcls=true, BlockPublicPolicy=true, RestrictPublicBuckets=true`）
15. `aws s3api put-public-access-block` で出力バケットのパブリックアクセスを全ブロックする
16. `aws s3api put-bucket-encryption` で入力バケットにAES256暗号化（BucketKey有効）を設定する
17. `aws s3api put-bucket-encryption` で出力バケットにAES256暗号化（BucketKey有効）を設定する

**Lambda通知設定ファイル生成:**

18. `aws sts get-caller-identity` でAWSアカウントIDを取得する
19. S3通知設定JSONファイル（`s3-notification-config.json`）を一時ディレクトリに生成する
    （Lambda ARNはアカウントIDと設定変数から組み立て。実際の通知設定は mk-s3-trigger.sh が行う）

### setup_dependent_resources 関数（後続設定の自動実行）

20. `mk-s3bktpolicy.sh` の存在確認を行い、`bash` コマンドで実行する（バケットポリシーの再設定）
21. `aws lambda get-function` でLambda関数の存在を確認する
    - Lambda関数が存在する場合: `mk-s3-trigger.sh` を実行する（S3トリガーの再設定）
    - Lambda関数が存在しない場合: スキップし、後から手動実行するよう警告を出力する
22. ライフサイクルルールは引数が必要なため自動実行できない旨の警告と手動実行コマンドを出力する

### confirm_s3bucket 関数（実行後確認）

23. 手順6〜8と同様に、作成後のバケット状態を確認・表示する

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| S3バケット | `${BKT_IN}` | 既存削除・新規作成 |
| S3バケット | `${BKT_OUT}` | 既存削除・新規作成 |
| S3バケット設定 | `${BKT_IN}` | パブリックアクセスブロック設定 |
| S3バケット設定 | `${BKT_OUT}` | パブリックアクセスブロック設定 |
| S3バケット設定 | `${BKT_IN}` | サーバーサイド暗号化設定（AES256） |
| S3バケット設定 | `${BKT_OUT}` | サーバーサイド暗号化設定（AES256） |
| S3バケットタグ | `${BKT_IN}` | プロジェクトタグ付与 |
| S3バケットタグ | `${BKT_OUT}` | プロジェクトタグ付与 |

## 7. エラーハンドリング

| 状況 | 対処 |
|:---|:---|
| スクリプト冒頭 `set -euo pipefail` | コマンド失敗・未定義変数参照・パイプエラー時に即時終了する |
| ERR/INT/TERM シグナル | `term` 関数を呼び出し、一時ディレクトリ `./mk-s3bkt.sh.src` を削除後に `exit 1` |
| EXIT | `term` 関数を呼び出し、一時ディレクトリを削除する（正常終了時も含む） |
| 既存バケット削除時のバージョン削除 | `list-object-versions` の失敗時は `{}` にフォールバック。`delete-objects` 対象なしの場合はスキップ（`|| true`） |
| バケット削除・オブジェクト削除 | `|| true` で個々のエラーを吸収し、バケット全体の削除処理を継続する |
| `mk-s3bktpolicy.sh` が見つからない | エラーメッセージを出力して `exit 1` |
| `mk-s3-trigger.sh` が見つからない | エラーメッセージを出力して `exit 1` |
| Lambda関数が未作成 | 警告を出力してトリガー設定をスキップする（`exit 1` しない） |

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
