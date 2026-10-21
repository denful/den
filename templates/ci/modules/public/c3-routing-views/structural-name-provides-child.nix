# `mkUnderscore` (nix/lib/aspects/types.nix) filtered a provides child's NAME
# through the structural-key registry — the set that classifies an ASPECT'S
# OWN top-level keys for content dispatch. Reusing it there filtered out any
# provides child whose author-chosen name happened to also be an ordinary
# aspect option (description, meta, name, includes, excludes, provides,
# policies, into, classes): the child was silently dropped from
# `.provides`/`._` with no error, and the aspect's own option default (e.g.
# `description = "Aspect <name>"`) read back in its place.
#
# Reaching the child and forwarding it onto the aspect's own top level are two
# separate questions, and only the first is site-independent. `.provides`/`._`
# reach every child whatever it is called; the only genuine machinery at THAT
# seam is the `__`-prefix pipeline-internal convention and `_` itself — `_` is
# the namespace's own alias sigil, and a multi-def nested key's content wrapper
# injects a literal `_` alongside its real children (see
# multidef-provides-internals.nix), so an unfiltered `_` leaks wrapper
# machinery as a provides key.
#
# Forwarding is reserved against the structural registry, because a child
# landing in the aspect's own option position is read structurally from there.
# A declared submodule wins that position by itself (every aspect option has a
# default), but the two RAW construction sites have no submodule and no
# defaults, so they need the reservation to behave the same — `provides.name`
# at a raw site used to become the aspect's own name and die coercing a set to
# a string. `mkUnderscore.forwardable` is what the raw sites fold.
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

    # Arm two of test-structural-name-survives-at-all-sites. That cell reaches
    # the same three children through `._` and delivers their content; this one
    # shows none of them displaced the aspect's own option to get there. The
    # two must disagree about the top level and agree about `._`.
    test-own-option-not-displaced-at-any-site = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # site A — declared submodule
        den.aspects.d10sa = {
          description = "own-desc";
          provides.description.nixos.environment.etc."d10-sa".text = "y";
        };
        # site B — functor-carrying battery attrset
        den.aspects.d10sh.provides.d10sb = {
          __functor = _self: _args: { };
          _.description.nixos.environment.etc."d10-sb".text = "y";
        };
        # site C — nested freeform key
        den.aspects.d10sc.holder.provides.description.nixos.environment.etc."d10-sc".text = "y";

        expr = {
          ownValue = den.aspects.d10sa.description;
          # No submodule at a raw site means no own value to read — and the
          # child no longer supplies one in its place.
          rawBatteryTop = den.aspects.d10sh.d10sb ? description;
          rawNestedTop = den.aspects.d10sc.holder ? description;
          # …while `._` still reaches all three.
          reachA = den.aspects.d10sa._ ? description;
          reachB = den.aspects.d10sh.d10sb._ ? description;
          reachC = den.aspects.d10sc.holder._ ? description;
        };
        expected = {
          ownValue = "own-desc";
          rawBatteryTop = false;
          rawNestedTop = false;
          reachA = true;
          reachB = true;
          reachC = true;
        };
      }
    );

    # A child named `name` reached the top level at the raw sites, where the
    # pipeline reads it as the aspect's own name: including the holder died on
    # `cannot coerce a set to a string`, with no `den:` prefix and no mention
    # of the collision. Both the holder's own content and the child deliver.
    test-name-collision-does-not-break-its-holder = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.d10n.holder = {
          nixos.environment.etc."d10-n-own".text = "y";
          provides.name.nixos.environment.etc."d10-n".text = "y";
        };
        den.aspects.igloo.includes = [
          den.aspects.d10n.holder
          den.aspects.d10n.holder._.name
        ];

        expr = {
          own = igloo.environment.etc ? "d10-n-own";
          child = igloo.environment.etc ? "d10-n";
        };
        expected = {
          own = true;
          child = true;
        };
      }
    );
  };
}
