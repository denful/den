system := `nix-instantiate --eval --raw -E builtins.currentSystem`

help:
  just -l

check-all:
  just check-noflake
  just all check
  just unit

check-noflake:
  nix-build ./templates/noflake --no-out-link -A flake.nixosConfigurations.igloo

update-all:
  cd templates/noflake && npins update den
  just all update

update-nix-effects:
  cd templates/ci && nix flake update nix-effects

docs:
  cd docs && pnpm run dev

ci test="" *args:
  bash ./ci.bash "{{system}}" "{{test}}" {{args}}

ci-deep test="" *args:
  just nix-unit ci "{{test}}" {{args}}

test test_name *args:
  nix-unit --override-input den . --flake ./templates/ci#.tests.{{test_name}} {{args}}

bogus *args:
  just nix-unit bogus "bogus" {{args}}

nix-unit template test *args:
  nix-unit  --override-input den . --flake ./templates/{{template}}#.tests.{{test}} {{args}}
  
check template *args:
  nix flake check  --override-input den . ./templates/{{template}} {{args}}

update template:
  nix flake update --flake ./templates/{{template}} den

all task:
  just {{task}} minimal
  just {{task}} example
  just {{task}} default
  just {{task}} ci
  just {{task}} bogus
  just {{task}} microvm
  just {{task}} nvf-standalone
  just {{task}} flake-parts-modules

fmt:
  nix run github:vic/checkmate#fmt --override-input target .

unit:
  nix flake check --override-input target . github:vic/checkmate

repl:
  nix repl --override-input den . ./templates/ci

[arg("tmpdir",long="tmpdir"), arg("head",long="head",short="h"), arg("base",long="base",short="b"), arg("warm",long="warm",short="w"), arg("runs",long="runs",short="r")]
bench tmpdir="/tmp" head="HEAD" base="refs/remotes/origin/main" warm="2" runs="5" *args: 
  rm -rf "{{tmpdir}}/den-head" "{{tmpdir}}/den-base"
  git clone --local --depth 1 --revision "$(git rev-list -n1 {{head}})" .git "{{tmpdir}}/den-head" 2>/dev/null
  git clone --local --depth 1 --revision "$(git rev-list -n1 {{base}})" .git "{{tmpdir}}/den-base" 2>/dev/null
  rm -rf "{{tmpdir}}/den-base/templates/ci"
  cp -r "{{tmpdir}}/den-head/templates/ci" "{{tmpdir}}/den-base/templates/ci"
  pushd "{{tmpdir}}/den-base" && git add templates/ci && popd
  hyperfine -m "{{runs}}" -w "{{warm}}" {{args}} \
    -n head "nix-unit --override-input den {{tmpdir}}/den-head --flake {{tmpdir}}/den-head/templates/ci#.tests.performance 2>&1 | tail -1" \
    -n base "nix-unit --override-input den {{tmpdir}}/den-base --flake {{tmpdir}}/den-base/templates/ci#.tests.performance 2>&1 | tail -1"
  rm -rf "{{tmpdir}}/den-head" "{{tmpdir}}/den-base"
