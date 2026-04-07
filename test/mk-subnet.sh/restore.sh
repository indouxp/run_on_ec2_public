#!/usr/bin/env bash
set -uo pipefail
set -eE

#
# テスト対象削除
#
rm -f config.sh
rm -f mk-subnet.sh

#
# テスト用ディレクトリへのシンボリックリンク
#
ln -s ../../src/shell/config.sh config.sh.org     || true
ln -s ../../src/shell/mk-subnet.sh mk-subnet.sh.org || true
ln -s ../../src/shell/assume-role.sh .             || true
