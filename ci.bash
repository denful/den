#!/usr/bin/env bash
#
# Uses nix-eval-jobs with $(nproc) workers
# NOTE: expectedError cells only verify that expr throws SOMETHING (via
# tryEval, in the --select expression below). They do not verify
# expectedError.type/.msg — nix-eval-jobs runs each job out-of-process, so
# only tryEval's success/failure crosses that boundary, not the caught
# exception's details. Use `nix-unit` directly (`just ci-deep`/`just test`)
# for full type/msg verification.
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
evalLog=$(mktemp -t den-test-XXXXX.err)

# Cap workers and per-worker memory to prevent OOM from infinite recursion.
# nproc can be very high (32+); limit workers so worst-case memory is bounded.
max_workers=8
mem_per_worker=2048  # MiB
workers=$(( $(nproc) < max_workers ? $(nproc) : max_workers ))

# set +e around the pipeline: under `set -e` a dying evaluator aborts the
# script here, so the summary below never runs and the exit status arrives
# with nothing said. Read PIPESTATUS instead and report it.
set +e
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
          # nix-eval-jobs runs each job in a separate worker; only
          # tryEval'\''s success/failure crosses that boundary, not the
          # caught exception'\''s type/msg text. So this only proves expr
          # throws SOMETHING — closing the class where a fix silently stops
          # throwing and the cell still reads green. It does not verify
          # expectedError.type/.msg; only `nix-unit` does that (it uses
          # the evaluator'\''s C++ API directly to inspect the exception).
          pass = if hasExpected then v.expr == v.expected
                 else if hasExpectedError then
                   !(builtins.tryEval (builtins.deepSeq v.expr null)).success
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
  "${args[@]}" 2>"$evalLog" \
  | tee "$results" \
  | jq -r 'if (.name != null and (.name | startswith("PASS-"))) then "✅ '"${postSuite}"'" + .attr else empty end'
evalStatus=${PIPESTATUS[0]}
set -e

# A dead evaluator is not a test failure and must not be tallied as one:
# `total` below is pass+fail over whatever reached the JSON stream, so a run
# that stopped early still reads as a clean N/N with zero failures. The
# evaluator's stderr is the only thing that says which file and line killed
# it, so it is a file now rather than /dev/null.
if [ "$evalStatus" -ne 0 ]; then
  echo >&2
  echo "💥 EVALUATOR FAILED (nix-eval-jobs exit ${evalStatus})" >&2
  echo "The run stopped early — no tally covers what it did not reach." >&2
  echo >&2
  cat "$evalLog" >&2
  rm -f "$evalLog" "$results"
  exit "$evalStatus"
fi

pass=$(jq -r 'select(.name != null and (.name | startswith("PASS-"))) | "."' "$results" | wc -l)
fail=$(jq -r 'select(.error != null or (.name != null and (.name | startswith("FAIL-")))) | "."' "$results" | wc -l)
total=$(expr "$pass" + "$fail")

if [ "$fail" -eq "0" ]; then
  echo "🎉 ${pass}/${total} successful" >&2
  rm -f "$results" "$evalLog" || true
else
  echo >&2
  echo "💥 FAILURES (${fail}):" >&2
  echo "For details run with \`just ci-deep <suite>\`" >&2
  echo "where <suite> does not include \`.test-xyz\`" >&2
  echo >&2
  jq -r 'select(.error != null or (.name != null and (.name | startswith("FAIL-")))) | "❌ '"${postSuite}"'" + .attr' "$results" >&2
  echo >&2
  echo "😢 ${pass}/${total} successful" >&2
  # Only when the evaluator actually said something. An ordinary assertion
  # failure leaves nothing here but nix's lock-file warnings, and burying the
  # list of failures under those is how a diagnostic stops being read.
  if grep -q "^error:" "$evalLog"; then
    echo >&2
    echo "--- evaluator stderr ---" >&2
    cat "$evalLog" >&2
  fi
  rm -f "$results" "$evalLog" || true
  exit 1
fi
