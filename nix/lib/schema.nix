# Resolve gen-schema through the gen HUB, preferring a consumer-provided flake
# input and falling back to the rev pinned in the CI lock, so den evaluates
# without forcing every consumer to declare the input.
#
# THE HUB, NOT gen-schema DIRECTLY, and neither half of that is a preference.
#
# Coherence: the hub binds every sibling's `gen-*` input with `follows`, so one
# input yields one revision per library. Pinning gen-schema directly leaves den
# holding its transitive closure — measured at the bump that motivated this
# file: three revisions of gen-prelude and two of gen-schema in one lock, which
# reads as one value while being several builds.
#
# The fallback: gen-schema's own root declares `{ prelude, merge, algebra,
# identity }` and states "There is NO `...`: an argument this root does not
# declare is a loud error, not a silent drop". So the old
# `import gen-schema { inherit lib; }` below is a loud refusal at every
# consumer that does not declare the input — which is all but one of den's
# templates. The hub's root takes the vestigial `{ }` and hands back the
# resolved roster, so the fallback has something total to call.
{ inputs, lib, ... }:
let
  lock = builtins.fromJSON (builtins.readFile ../../templates/ci/flake.lock);
  locked = lock.nodes.gen.locked;
  genSrc = builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.zip";
    sha256 = locked.narHash;
  };
  # Two entry shapes for one roster: the flake publishes `lib.mkGenLibs` (a
  # function of a vestigial argument), the standalone root yields the roster
  # directly. Dispatch on which channel supplied it rather than probing the
  # value, so a member that changes shape is loud here instead of silently
  # taking the other arm.
  roster = if inputs ? gen then inputs.gen.lib.mkGenLibs { } else import genSrc { };
in
let
  base = roster.schema;

  # nixpkgs `lib` as a BASE module argument, injected ONCE here rather than at
  # each call site. nixpkgs' `evalModules` supplies `lib` to every module at
  # every level; gen's ships no nixpkgs lib by construction, so supplying it is
  # den's job. `_module.args` is NOT the channel: a module that forces `lib`
  # while producing its own top-level attrset then reads the config fixpoint it
  # is part of, which is an uncatchable infinite recursion naming neither the
  # module nor the argument (#687).
  #
  # At the boundary, not the call sites, so a new `mkInstanceType` or
  # `mkSchemaOption` call cannot forget it. den threaded four sites by hand
  # first and that is exactly one edit away from reintroducing the defect.
  #
  # A caller's own `specialArgs` win, so a kind can still shadow `lib`.
  withLib =
    f: args:
    f (
      args
      // {
        specialArgs = {
          inherit lib;
        }
        // (args.specialArgs or { });
      }
    );
in
base
// {
  mkInstanceType = kindValue: withLib (base.mkInstanceType kindValue);
  mkSchemaOption = withLib base.mkSchemaOption;
}
