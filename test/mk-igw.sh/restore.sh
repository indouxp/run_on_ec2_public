#!/usr/bin/env bash
set -uo pipefail
set -eE

#
# テスト対象削除
#
rm -f config.sh
rm -f mk-igw.sh

#
# テスト用ディレクトリへのシンボリックリンク
#
ln -s ../../src/shell/config.sh config.sh.org     || true
ln -s ../../src/shell/mk-igw.sh mk-igw.sh.org     || true
ln -s ../../src/shell/assume-role.sh .             || true
