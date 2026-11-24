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
{
  inputs,
  lib,
  den,
  ...
}:
let
  lock = builtins.fromJSON (builtins.readFile ../../templates/ci/flake.lock);
  locked = lock.nodes.gen.locked;
  genSrc = builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
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

  # gen-schema takes the options first; the kind-first order is the deprecated
  # spelling. The options are a closed key set, so anything else is a kind.
  instanceOptionKeys = [
    "extraModules"
    "strict"
    "specialArgs"
  ];
  isInstanceOptions = a: builtins.all (k: builtins.elem k instanceOptionKeys) (builtins.attrNames a);

  # Every entity kind's instances carry `resolved` (and `__scopeName`,
  # `collisionPolicy`), which `hasAspect` on `den.schema.conf` reads. Injected
  # at the boundary, where the kind name is known, so a custom kind's registry
  # gets them exactly as host, user and home do instead of inheriting a
  # `hasAspect` that throws. Prepended, so a kind's own extraModules (home's
  # `__scopeName`) still override.
  inherit (import ./entities/_types.nix { inherit lib den; }) resolvedCtxModule;
  withResolved =
    opts: kindValue:
    if kindValue.isEntity or false then
      opts // { extraModules = [ (resolvedCtxModule kindValue.kind) ] ++ (opts.extraModules or [ ]); }
    else
      opts;
  mkInstanceTypeFor =
    opts: kindValue: withLib base.mkInstanceType (withResolved opts kindValue) kindValue;
in
# gen's paired constructions stay off den's public surface: den reaches them
# only through `__mkInstancePaired` below.
builtins.removeAttrs base [ "mkInstancePaired" ]
// {
  # The gen libraries beyond gen-schema that den builds on, from the same roster
  # on the flake path and the fallback. A consumer's own `gen` input can be older
  # than den's pin, so a missing member is named rather than left to fail inside
  # whatever first reads it.
  gen =
    let
      needed = [
        [
          "merge"
          "priorityBand"
        ]
        [
          "algebra"
          "record"
          "foldLayersTraced"
        ]
        [
          "algebra"
          "term"
        ]
        [
          "identity"
          "hashIdentity"
        ]
      ];
      missing = builtins.filter (p: !lib.hasAttrByPath p roster) needed;
    in
    if missing != [ ] then
      throw ''
        den: the gen libraries den was given are too old: they lack ${
          lib.concatMapStringsSep ", " (lib.concatStringsSep ".") missing
        }.
        den needs gen at 620ceaab6180cc6de3843db4473507f739580e75 or later. Update your `gen` input.
      ''
    else
      {
        inherit (roster) algebra identity;
        merge = builtins.removeAttrs roster.merge [ "refusingSubmodulePaired" ];
      };

  # PROVISIONAL. The one caller of gen-schema's paired construction, and
  # through it of gen-merge's refusingSubmodulePaired: `{ type; evaluate; }`,
  # where `evaluate loc defs` is one evaluation of `type`, `{ config;
  # provenance; }`. It isn't yet in the gen den pins; it's reached here alone,
  # so a change to it stays in one place.
  __mkInstancePaired =
    opts: kindValue:
    if base ? mkInstancePaired then
      withLib base.mkInstancePaired (withResolved opts kindValue) kindValue
    else
      throw ''
        den: the gen libraries den was given are too old for the user registry: they lack gen-schema's paired instance construction (`mkInstancePaired`), which isn't yet in the gen den pins.
        den needs gen-schema at 7f2a0dd1c42bcd99d88661316209596d65d4dc8e or later, with gen-merge at 65070d57db3a92279733c8ea7a59d4a8a509aa79 or later. Every config with a host user or a home reads the registry.
      '';

  mkInstanceType =
    a:
    if isInstanceOptions a then
      mkInstanceTypeFor a
    else
      lib.warn ''
        den: `den.lib.schema.mkInstanceType` called kind-first for kind '${a.kind or "?"}' is deprecated.
        gen-schema takes the options first. Swap the arguments:
          - den.lib.schema.mkInstanceType den.schema.${a.kind or "<kind>"} { … }
          + den.lib.schema.mkInstanceType { … } den.schema.${a.kind or "<kind>"}
      '' (opts: mkInstanceTypeFor opts a);
  mkSchemaOption = withLib base.mkSchemaOption;
  mkInstanceRegistry =
    opts: kindValue: withLib base.mkInstanceRegistry (withResolved opts kindValue) kindValue;

  # `den.schema.<kind>.imports = [ den.lib.strict ]` (deprecated) lands `isStrict` on every
  # instance, which a closed kind would refuse.
  strictCompatModules =
    strict:
    lib.optional strict {
      options.isStrict = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
        visible = false;
      };
    };
}
