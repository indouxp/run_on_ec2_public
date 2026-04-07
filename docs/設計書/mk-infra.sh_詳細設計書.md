# mk-infra.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、インフラ構築スクリプトの実行作業ディレクトリ `infra/` を作成し、`src/shell/` 内の各スクリプトへのシンボリックリンクを設置します。また、プロジェクトルートに `lambda/` シンボリックリンクを作成します。本スクリプトは、プロジェクトを新規に展開した際に最初に実行します。

作成するリソース:
- `infra/` ディレクトリ
- `infra/mk-*.sh` → `../src/shell/mk-*.sh`（全 mk-*.sh）
- `infra/set-*.sh` → `../src/shell/set-*.sh`（全 set-*.sh）
- `infra/aws-*.sh` → `../src/shell/aws-*.sh`（全 aws-*.sh）
- `infra/config.sh` → `../src/shell/config.sh`
- `infra/assume-role.sh` → `../src/shell/assume-role.sh`
- `infra/del-all.sh` → `../src/shell/del-all.sh`
- `infra/info-all.sh` → `../src/shell/info-all.sh`
- `infra/reissue-accesskey.sh` → `../src/shell/reissue-accesskey.sh`
- `infra/構築手順書.md` → `../docs/構築手順/構築手順書.md`
- `<PROJECT_ROOT>/lambda` → `src/lambda`
- `infra/.gitignore`（`*.log` を除外）

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: プロジェクトルート（`bash src/shell/mk-infra.sh`）または `src/shell/`（`./mk-infra.sh`）
- 必要コマンド: bash、ln、mkdir
- AWS 認証: 不要（ローカルファイル操作のみ）

---

## 3. 前提条件

- プロジェクトルートに `src/shell/`、`src/lambda/`、`docs/構築手順/` が存在すること

---

## 4. 入力

### 4.1 設定ファイル

設定ファイルを使用しません。

### 4.2 スクリプト内固定値

| 変数名 | 内容 |
|:---|:---|
| `SCRIPT_DIR` | スクリプト自身のディレクトリ（`src/shell/`） |
| `PROJECT_ROOT` | プロジェクトルートディレクトリ |
| `INFRA_DIR` | `infra/` ディレクトリのパス |
| `REL_SHELL` | `infra/` から `src/shell/` への相対パス（`../src/shell`） |

### 4.3 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

1. `SCRIPT_DIR`（スクリプト自身のディレクトリ）・`PROJECT_ROOT`（プロジェクトルート）・`INFRA_DIR`（`${PROJECT_ROOT}/infra`）を設定する。
2. `mkdir -p "${INFRA_DIR}"` で `infra/` ディレクトリを作成する（既存の場合はスキップ）。
3. `cd "${INFRA_DIR}"` で `infra/` に移動する。
4. `src/shell/mk-*.sh` を `for` ループで列挙し、各ファイルへの `ln -sf` でシンボリックリンクを作成する。
5. `src/shell/set-*.sh` を同様にシンボリックリンク作成する。
6. `src/shell/aws-*.sh` を同様にシンボリックリンク作成する。
7. 個別スクリプト（`config.sh`・`assume-role.sh`・`del-all.sh`・`info-all.sh`・`reissue-accesskey.sh`）のシンボリックリンクを作成する。
8. `构築手順書.md` → `../docs/構築手順/構築手順書.md` のシンボリックリンクを作成する。
9. `${PROJECT_ROOT}/lambda` → `src/lambda` のシンボリックリンクを作成する（`mk-lambda.sh` / `mk-lambda-terminator.sh` が参照するため）。
10. `infra/.gitignore` を作成し、`*.log` を除外する。

---

## 6. 作成・更新リソース

| 種別 | パス | 内容 |
|:---|:---|:---|
| ディレクトリ | `infra/` | 構築作業用ディレクトリ |
| シンボリックリンク | `infra/mk-*.sh` 等 | `src/shell/` 内の各スクリプトへのリンク |
| シンボリックリンク | `infra/構築手順書.md` | 構築手順書へのリンク |
| シンボリックリンク | `<PROJECT_ROOT>/lambda` | `src/lambda` へのリンク |
| ファイル | `infra/.gitignore` | `*.log` を git 管理対象外にする |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- `ln -sf` はべき等（既存リンクがある場合は上書き）のため、再実行可能。
- ログファイルへのリダイレクトはなし（標準出力に直接表示）。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
