# mk-role-exec.sh 詳細設計書

## 1. 概要

### 1.1 目的

本ドキュメントは、システム運用・実行用IAMロール `ts-010-role-exec` を作成するシェルスクリプト `mk-role-exec.sh` の詳細な設計を定義します。

このスクリプトは、システム実行フェーズに必要な権限（S3アクセス・EC2操作・ログ出力・通知など）を持つIAMロールを作成します。このロールを使用することで、ユーザーはシステムの動作をシミュレートまたは手動実行できます。既存のロールが存在する場合は削除して再作成します。

作成するAWSリソース:

- IAMロール: `ts-010-role-exec`
- インラインポリシー: `ts-010-role-exec-policy`

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）

**派生文書**
- なし

## 2. 実行環境

- **実行場所**: `infra/` ディレクトリ
- **必要コマンド**: aws cli
- **AWS認証**: `AWS_PROFILE=ts-usr-admin`（IAM操作のため管理者プロファイルを使用）

## 3. 前提条件

- `AWS_PROFILE=ts-usr-admin` が設定済みであること
- `config.sh` が同一ディレクトリに存在すること
- S3バケット（`${BKT_IN}`、`${BKT_OUT}`）が作成済みであること
- SNSトピック（`ts-010-sns-010`）が作成済みであること
- EC2ロール（`ts-010-role-ec2-010`）・Lambdaロール（`ts-010-role-lambda-010`）が作成済みであること（ポリシーARNに使用するため）

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `PRJ_PREFIX` | プロジェクトプレフィックス | `ts-010` |
| `IAM_ROLE_EXEC_NAME` | 作成するIAMロール名 | `ts-010-role-exec` |
| `IAM_ROLE_EC2_NAME` | EC2実行ロール名（IAMPassRole対象） | `ts-010-role-ec2-010` |
| `IAM_ROLE_LAMBDA_NAME` | Lambda実行ロール名（IAMPassRole対象） | `ts-010-role-lambda-010` |
| `S3_BKT_IN_NAME` | S3入力バケット名 | `${BKT_IN}` |
| `S3_BKT_OUT_NAME` | S3出力バケット名 | `${BKT_OUT}` |
| `SNS_TOPIC_NAME` | SNSトピック名 | `ts-010-sns-010` |
| `AWS_REGION` | AWSリージョン | `ap-northeast-1` |
| `PRJ_TAG_KEY` | タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | タグ値 | `ts-010` |

### 4.2 引数

なし

## 5. 処理フロー

スクリプトは以下の順序で処理を実行します。

1. **初期設定**
    - `set -euo pipefail` を設定し、エラー・未定義変数・パイプ失敗時に即時終了するようにします。
    - `SCRIPT_DIR`・`PROJECT_ROOT` を取得し、`config.sh` を `source` で読み込みます。
    - `MY_SRC_DIR`（`./${MY_NAME}.src`）・`LOG_PATH`（`./${MY_NAME}.log`）を設定します。
    - `trap 'term; exit 1' ERR INT TERM` と `trap 'term' EXIT` を設定し、終了時に `MY_SRC_DIR` を削除します。

2. **ログ出力開始**
    - `exec >> "${LOG_PATH}" 2>&1` により、以降の全標準出力・標準エラー出力をログファイルにリダイレクトします。

3. **アカウントID取得**
    - `aws sts get-caller-identity` でAWSアカウントIDを取得し、`AWS_ACCOUNT_ID` に格納します。

4. **`confirm_role` 関数（実行前確認）**
    - `aws iam get-role` で `ts-010-role-exec` の存在と詳細を確認します。
    - `aws iam list-role-policies` でインラインポリシー一覧を確認します。

5. **`make_role` 関数（ロール作成処理）**

    1. **既存ロール削除**
        - `aws iam delete-role-policy` でインラインポリシー `ts-010-role-exec-policy` を削除します（存在しない場合はエラーを無視）。
        - `aws iam delete-role` でロール `ts-010-role-exec` を削除します（存在しない場合はエラーを無視）。

    2. **信頼関係ポリシー作成**
        - `${MY_SRC_DIR}/trust-policy-exec.json` を生成します。
        - `Principal` として `arn:aws:iam::${AWS_ACCOUNT_ID}:root`（アカウントルート）を指定します。
        - `Action` は `sts:AssumeRole` のみを許可します。

    3. **ロール作成**
        - `aws iam create-role` でロール `ts-010-role-exec` を作成します。
        - プロジェクトタグ（`PRJ_TAG_KEY` / `PRJ_TAG_VALUE`）を付与します。

    4. **インラインポリシー定義**
        - `${MY_SRC_DIR}/exec-policy.json` を生成します。以下のSidで権限を定義します。

        | Sid | 対象サービス | 主な権限 | リソース制限 |
        |:---|:---|:---|:---|
        | `S3Access` | S3 | GetObject / PutObject / DeleteObject / ListBucket / ListAllMyBuckets | `${BKT_IN}`・`${BKT_OUT}` のみ |
        | `EC2Operation` | EC2 | RunInstances / DescribeInstances / DescribeSubnets / DescribeSecurityGroups / CreateTags | `*` |
        | `EC2SelfTermination` | EC2 | TerminateInstances | Nameタグ `ts-010-ec2-010` が付与されたリソースのみ（Condition） |
        | `IAMPassRole` | IAM | PassRole / GetInstanceProfile | EC2ロール・Lambdaロール・自ロールのARNのみ |
        | `Notifications` | SNS / SES | Publish / SendEmail / SendRawEmail | SNSトピックARN・SES identityのみ |
        | `Logging` | CloudWatch Logs | CreateLogGroup / CreateLogStream / PutLogEvents / Describe / GetLogEvents | `${PRJ_PREFIX}-log-*` パターンのみ |

    5. **ポリシーアタッチ**
        - `aws iam put-role-policy` でインラインポリシーをロールにアタッチします。

6. **`confirm_role` 関数（実行後確認）**
    - ステップ4と同様の確認を再度実行し、ロールが正しく作成されたことを検証します。

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 内容 |
|:---|:---|:---|
| IAMロール | `ts-010-role-exec` | 信頼関係: アカウントルート（`sts:AssumeRole`） |
| インラインポリシー | `ts-010-role-exec-policy` | システム実行フェーズに必要な6分野の権限セット |

## 7. エラーハンドリング

- **`set -euo pipefail`**: コマンドの失敗・未定義変数参照・パイプ失敗のいずれかで即時終了します。
- **trapによるクリーンアップ**: ERR/INT/TERMシグナル受信時および EXIT 時に `term()` 関数を呼び出し、`MY_SRC_DIR` を削除します。これにより一時的に生成したJSONポリシーファイルが残存しないようにします。
- **既存リソース削除時のエラー無視**: `2>/dev/null || true` により、削除対象が存在しない場合のエラーを無視して処理を継続します。

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
