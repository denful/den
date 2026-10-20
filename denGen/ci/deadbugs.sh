#!/usr/bin/env bash
# usage: deadbugs.sh <den-path> <out.tsv> [suite...]  (run from the den checkout)
# PASS iff rc==0 and "N/M successful" with M>0, N==M (0/0 is a false green).
set -u
# a failed realpath left den empty and nix silently fell back to the locked den input
den=$(realpath -e "${1#path:}") || { echo "bad den path: $1" >&2; exit 2; }; den="path:$den"; out=$2; shift 2
if [ $# -gt 0 ]; then suites=("$@"); else
  mapfile -t suites < <(rg -oN --no-filename -r '$1' 'flake\.tests\.([A-Za-z0-9_-]+)' templates/ci/modules/deadbugs/*.nix | sort -u)
fi
[ ${#suites[@]} -gt 0 ] || { echo "no suites" >&2; exit 2; }
scratch=$(mktemp -d); export den scratch
one() {
  s=$1; log=$scratch/$s.log
  (ulimit -v 8388608; timeout 300 nix run nixpkgs#nix-unit -- --override-input den "$den" --flake "./templates/ci#.tests.$s" > "$log" 2>&1); rc=$?
  nm=$(grep -oE '[0-9]+/[0-9]+ successful' "$log" | tail -1 | grep -oE '^[0-9]+/[0-9]+')
  err=$(grep -m1 'error:' "$log" | cut -c1-160 | tr '\t' ' ')
  st=ERROR
  if [ -n "$nm" ]; then
    n=${nm%/*}; m=${nm#*/}
    if [ "$rc" -eq 0 ] && [ "$m" -gt 0 ] && [ "$n" -eq "$m" ]; then st=PASS; else st=FAIL; fi
  fi
  printf '%s\t%s\t%s\t%s\n' "$s" "$st" "${nm:--}" "$err" > "$scratch/$s.row"
}
export -f one
printf '%s\n' "${suites[@]}" | xargs -P4 -I{} bash -c 'one {}'
: > "$out"
for s in "${suites[@]}"; do cat "$scratch/$s.row" >> "$out"; done
