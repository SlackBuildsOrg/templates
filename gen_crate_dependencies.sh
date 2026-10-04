#!/bin/bash
#
# gen DOWNLOAD and MD5SUM values for slackbuilds using cargo
#
# Copyright 2017-2022 Andrew Clemons, Wellington New Zealand
# Copyright 2022-2026 Andrew Clemons, Tokyo Japan
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -e
set -o pipefail

help() {
  cat <<EOF
Usage: ${0##*/} ARCHIVE [INFOFILE]

Generate URLs for downloading all required crates for the Cargo.lock files in ARCHIVE. The m5sum of each crate is also generated.
If you pass INFOFILE, update the DOWNLOAD and MD5SUM values of it with those URLs and md5sums.

Options:
  -h, --help  Show this help message.

Environment:
  CARGOLOCKMAXDEPTH  Maximum depth passed to find to look for Cargo.lock in the archive (default: 2).
  CARGOLOCKDEPTH     Minimum depth passed to find to look for Cargo.lock in the archive (default: 2).
EOF
}

case "$1" in
  -h|--help)
    help
    exit 0
    ;;
esac

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  help >&2
  exit 1
fi

FILE="$(readlink -m "$1")"

INFOFILE=""
if [ -n "$2" ]; then
  INFOFILE="$(readlink -m "$2")"
fi

WORKDIR="$(mktemp -t tmp.XXXXXXXXXX -d)"
trap 'rm -rf "$WORKDIR"' INT TERM HUP QUIT EXIT

cd "$WORKDIR"

tar -xf "$FILE"

touch urls md5sums

CARGOLOCKMAXDEPTH=${CARGOLOCKMAXDEPTH:-2}
CARGOLOCKDEPTH=${CARGOLOCKDEPTH:-2}

grep -h -A 3 "\[\[package\]\]" $(find . -maxdepth "$CARGOLOCKMAXDEPTH" -mindepth "$CARGOLOCKDEPTH" -name Cargo.lock | tr '\n' ' ') | \
  sed 's/[[:space:]]*=[[:space:]]*/=/g;s/^--//;s/^\[\[/--\n[[/' | \
  awk 'BEGIN { RS = "--\n" ; FS="\n" } { print $2, $3, $4 }' | sed 's/"//g;s/name=//;s/ version=/=/' | \
  grep crates\.io-index | sed 's/ source=.*$//' | sort -u | while read -r dep ; do

  crate="$(printf "%s\n" "$dep" | cut -d= -f1)"
  version="$(printf "%s\n" "$dep" | cut -d= -f2)"

  >&2 printf "Processing %s=%s\n" "$crate" "$version"

  url="https://static.crates.io/crates/$crate/$crate-$(printf '%s\n' "$version" | sed 's/+/%2B/g').crate"

  printf "          %s\n" "$url" >> urls

  wget -q "$url"

  md5sum "$crate-$version.crate" | awk '{ print $1 }' | sed 's/^/        /' >> md5sums
done

cat urls
printf -- "--\n"
cat md5sums

if [ -n "$INFOFILE" ] && [ -f "$INFOFILE" ]; then
  first_url="$(sed -n 's/^DOWNLOAD="\([^ ]*\).*/\1/p' "$INFOFILE")"
  first_md5="$(sed -n 's/^MD5SUM="\([^ ]*\).*/\1/p' "$INFOFILE")"

  {
    printf 'DOWNLOAD="%s \\\n' "$first_url"
    awk 'NR > 1 { print prev " \\" } { prev = $0 } END { print prev "\"" }' urls
  } > new_download.tmp

  {
    printf 'MD5SUM="%s \\\n' "$first_md5"
    awk 'NR > 1 { print prev " \\" } { prev = $0 } END { print prev "\"" }' md5sums
  } > new_md5.tmp

  awk '
  /^DOWNLOAD=/ {
    while ((getline line < "new_download.tmp") > 0) print line
    close("new_download.tmp")
    skip=1; next
  }
  /^MD5SUM=/ {
    while ((getline line < "new_md5.tmp") > 0) print line
    close("new_md5.tmp")
    skip=1; next
  }
  skip && / \\$/ { next }
  skip { skip=0; next }
  { print }
  ' "$INFOFILE" > "${INFOFILE}.tmp" && mv "${INFOFILE}.tmp" "$INFOFILE"
fi
