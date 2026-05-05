#!/usr/bin/env bash
#
# Uses nix-eval-jobs with $(nproc) workers
# NOTE: Ignores tests with expectedError
#
# Redirect stdout to null IF you only want to see failures
set -aeuo pipefail

system="x86_64-linux"
if test -n "${1:-}"; then
  system="${1}"
  shift
fi

suite=""
testFilter=""
preSuite=""
postSuite=""

if test -n "${1:-}"; then
  input="$1"
  # Split suite.test-name into suite + test filter
  suite="${input%%.*}"
  if [[ "$input" == *.* ]]; then
    testFilter="${input#*.}"
  fi
  preSuite=".${suite}"
  postSuite="${suite}."
  shift
fi

args=($@)

# When a specific test is requested, delegate to nix-unit for traces
if test -n "$testFilter"; then
  nix_unit_output=$(nix-unit --override-input den . --flake "./templates/ci#.tests.${suite}" "${args[@]}" 2>&1) || true
  # Show only the matching test's output (with surrounding trace context)
  echo "$nix_unit_output" | grep -v '^[✅❌🎉😢]' | grep -v 'successful$' >&2 || true
  if echo "$nix_unit_output" | grep -q "^✅ ${testFilter}$"; then
    echo "✅ ${postSuite}${testFilter}"
    echo "🎉 1/1 successful" >&2
  else
    echo "❌ ${postSuite}${testFilter}"
    echo "😢 0/1 successful" >&2
    exit 1
  fi
  exit 0
fi

results=$(mktemp -t den-test-XXXXX.json)

# Cap workers and per-worker memory to prevent OOM from infinite recursion.
# nproc can be very high (32+); limit workers so worst-case memory is bounded.
max_workers=8
mem_per_worker=2048  # MiB
workers=$(( $(nproc) < max_workers ? $(nproc) : max_workers ))

nix-eval-jobs \
  --flake ./templates/ci#tests${preSuite} \
  --override-input den . \
  --workers "$workers" \
  --max-memory-size "$mem_per_worker" \
  --force-recurse \
  --select 'tests: let
    system="'"${system}"'";
    go = prefix: v:
      if v ? expr then
        let
          hasExpected = v ? expected && !(v.expected ? undefined);
          hasExpectedError = v ? expectedError && !(v.expectedError ? undefined);
          pass = if hasExpected then v.expr == v.expected
                 else if hasExpectedError then true # ignored
                 else true;
          name = builtins.replaceStrings ["." "'\''"] ["-" "_"] prefix;
        in derivation {
          name = if pass then "PASS-${name}" else "FAIL-${name}";
          system = "${system}"; builder = "/bin/sh";
          args = ["-c" "echo > $out"];
        }
      else if builtins.isAttrs v then
        builtins.mapAttrs (k: go (if prefix == "" then k else "${prefix}.${k}")) v
      else derivation { name = "SKIP"; system = "${system}"; builder = "/bin/sh"; args = ["-c" "echo > $out"]; };
  in builtins.mapAttrs (k: go k) tests' \
  "${args[@]}" 2>/dev/null \
  | tee "$results" \
  | jq -r 'if (.name != null and (.name | startswith("PASS-"))) then "✅ '"${postSuite}"'" + .attr else empty end'

pass=$(jq -r 'select(.name != null and (.name | startswith("PASS-"))) | "."' "$results" | wc -l)
fail=$(jq -r 'select(.error != null or (.name != null and (.name | startswith("FAIL-")))) | "."' "$results" | wc -l)
total=$(expr "$pass" + "$fail")

if [ "$fail" -eq "0" ]; then
  echo "🎉 ${pass}/${total} successful" >&2
  rm "$results" || true
else
  echo >&2
  echo "💥 FAILURES (${fail}):" >&2
  echo "For details run with \`just ci-deep <suite>\`" >&2
  echo "where <suite> does not include \`.test-xyz\`" >&2
  echo >&2
  jq -r 'select(.error != null or (.name != null and (.name | startswith("FAIL-")))) | "❌ '"${postSuite}"'" + .attr' "$results" >&2
  echo >&2
  echo "😢 ${pass}/${total} successful" >&2
  rm "$results" || true
  exit 1
fi
