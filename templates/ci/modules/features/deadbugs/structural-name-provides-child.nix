# `mkUnderscore` (nix/lib/aspects/types.nix) filtered a provides child's NAME
# through `structuralKeysSet` — the set that classifies an ASPECT'S OWN
# top-level keys for content dispatch. Reusing it here filtered out any
# provides child whose author-chosen name happened to also be an ordinary
# aspect option (description, meta, name, includes, excludes, provides,
# policies, into, classes): the child was silently dropped from
# `.provides`/`._` with no error, and the aspect's own option default (e.g.
# `description = "Aspect <name>"`) read back in its place.
#
# The only genuine machinery at THIS seam is the `__`-prefix pipeline-internal
# convention and `_` itself — `_` is the namespace's own alias sigil, and a
# multi-def nested key's content wrapper injects a literal `_` alongside its
# real children (see multidef-provides-internals.nix), so an unfiltered `_`
# leaks wrapper machinery as a provides key. Every other structural-key name
# now survives: it is reachable via `.provides`/`._` while the aspect's own
# declared option (always present, via its default) keeps top-level priority.
{ denTest, ... }:
{
  flake.tests.deadbugs.structural-name-provides-child = {

    # A structural-named child now delivers, at all three construction sites.
    test-structural-name-survives-at-all-sites = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # site A — declared submodule, direct `provides.description`.
        den.aspects.d10a.provides.description.nixos.environment.etc."d10-a".text = "y";
        # site B — functor-carrying battery attrset, `_.description` write.
        den.aspects.d10h.provides.d10b = {
          __functor = _self: _args: { };
          _.description.nixos.environment.etc."d10-b".text = "y";
        };
        # site C — nested freeform key, direct `provides.description`.
        den.aspects.d10c.holder.provides.description.nixos.environment.etc."d10-c".text = "y";

        den.aspects.igloo.includes = [
          den.aspects.d10a._.description
          den.aspects.d10h.d10b._.description
          den.aspects.d10c.holder._.description
        ];

        expr = {
          a = igloo.environment.etc ? "d10-a";
          b = igloo.environment.etc ? "d10-b";
          c = igloo.environment.etc ? "d10-c";
        };
        expected = {
          a = true;
          b = true;
          c = true;
        };
      }
    );

    # The aspect's own declared option keeps top-level priority: forwarding a
    # structural-named provides child must not clobber `aspect.description`.
    test-own-option-still-wins-at-top-level = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.d10own = {
          description = "own-desc";
          provides.description.nixos.environment.etc."d10-own".text = "y";
        };

        expr = {
          ownValue = den.aspects.d10own.description;
          childReachable = den.aspects.d10own._ ? description;
        };
        expected = {
          ownValue = "own-desc";
          childReachable = true;
        };
      }
    );

    # CONTROL: a provides child named `_` stays reserved — it's the
    # namespace's own alias sigil, and letting it through leaks multi-def
    # wrapper machinery (multidef-provides-internals.nix). Loud, not silent:
    # the aspect simply has no child by that name, same as before this fix.
    test-underscore-name-stays-reserved = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.d10u.provides._.nixos.environment.etc."d10-u".text = "y";

        expr = den.aspects.d10u._ ? "_";
        expected = false;
      }
    );
  };
}
