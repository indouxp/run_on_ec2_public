#!/usr/bin/env bash
set -uo pipefail
set -eE

#
# テスト対象削除
#
rm -f config.sh
rm -f mk-s3bkt.sh

#
# テスト用ディレクトリへのシンボリックリンク
#
ln -s ../../src/shell/config.sh config.sh.org       || true
ln -s ../../src/shell/mk-s3bkt.sh mk-s3bkt.sh.org   || true
ln -s ../../src/shell/assume-role.sh .               || true
