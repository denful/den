#!/usr/bin/env bash
# Decides whether a change needs den's test suite: the one place that rule lives.
#
#   test-scope.sh < changed-paths    prints "true" or "false"
#   test-scope.sh --self-test        checks the rule against sample paths
#   test-scope.sh --decide           the CI step: reads EVENT, PR, BEFORE, SHA,
#                                    REPO from the environment and writes
#                                    nix-changed to $GITHUB_OUTPUT
#
# --decide fails closed. Skipped required checks count as passing, so a wrong
# "false" would merge untested code: if the self-test fails or the changed
# files can't be listed, it answers "true".
#
# A change needs the tests when it touches Nix code, a lock file, or the test
# machinery itself (this script, test.yml, justfile, ci.bash).
set -euo pipefail

pattern='(\.nix|(^|/)flake\.lock|(^|/)npins/sources\.json|^\.github/workflows/test\.yml|^\.github/test-scope\.sh|^justfile|^ci\.bash)$'

if [[ "${1:-}" == "--decide" ]]; then
  decide() {
    local files
    if ! "$0" --self-test >&3 2>&3; then
      echo "::error::test-scope.sh --self-test failed; running the tests" >&3
      echo true
      return
    fi
    case "${EVENT:-}" in
      pull_request | pull_request_review)
        # The PR's own files, not a tree diff against main's tip. Captured
        # first, so a failed or partial listing can't read as "nothing changed".
        if ! files=$(gh api --paginate "repos/${REPO}/pulls/${PR}/files" --jq '.[].filename'); then
          echo "::warning::could not list the PR's changed files; running the tests" >&3
          echo true
          return
        fi
        ;;
      push)
        # A first or force push has no usable `before`: test it.
        if [[ -z "${BEFORE:-}" || "${BEFORE}" =~ ^0+$ ]] ||
          ! git fetch --depth 1 origin "${BEFORE}" >&2 ||
          ! files=$(git diff --name-only "${BEFORE}" "${SHA}" --); then
          echo true
          return
        fi
        ;;
      *)
        # workflow_dispatch: a manual run is a request to test.
        echo true
        return
        ;;
    esac
    printf '%s\n' "$files" | "$0"
  }
  # fd 3 carries annotations and diagnostics past the capture to the log.
  exec 3>&1
  changed=$(decide)
  echo "nix-changed=${changed}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  echo "test-scope: ${EVENT:-?} -> nix-changed=${changed}" >&2
  exit 0
fi

if [[ "${1:-}" == "--self-test" ]]; then
  fail=0
  check() {
    local path=$1 want=$2 got
    got=$(printf '%s\n' "$path" | "$0")
    if [[ "$got" != "$want" ]]; then
      echo "test-scope: '$path' gave $got, expected $want" >&2
      fail=1
    fi
  }
  check nix/lib/entities/user.nix true
  check templates/ci/flake.lock true
  check templates/ci/provider/flake.lock true
  check templates/noflake/npins/sources.json true
  check .github/workflows/test.yml true
  check .github/test-scope.sh true
  check justfile true
  check ci.bash true
  check docs/src/content/docs/guides/from-zero-to-den.mdx false
  check README.md false
  check .github/workflows/docs.yml false
  check templates/noflake/README.md false
  check flake.lock.bak false
  exit "$fail"
fi

if grep -qE "$pattern"; then
  echo true
else
  echo false
fi
