# Issue #645: two custom forward classes chained (`inner` -> `mid` ->
# `homeManager`) collide on the INNER hop's `den.fwd."inner/mid/<path>"`
# declaration.
#
# The inner adapter declares into the `mid` bucket, which the second hop then
# nests into `homeManager` — so the declaration reaches the target indirectly
# and a second producer survives the suppression that covers direct hops.
{ denTest, ... }:
let
  # `inner` content lands at `programs.bash` of the `mid` class; `mid` merges
  # into `homeManager` wholesale.
  innerClass =
    den: lib:
    { class, aspect-chain }:
    den._.forward {
      each = lib.singleton class;
      fromClass = _: "inner";
      intoClass = _: "mid";
      intoPath = _: [
        "programs"
        "bash"
      ];
      fromAspect = _: lib.last aspect-chain;
      guard = _: true;
    };

  midClass =
    den: lib:
    { class, aspect-chain }:
    den._.forward {
      each = lib.singleton class;
      fromClass = _: "mid";
      intoClass = _: "homeManager";
      intoPath = _: [ ];
      fromAspect = _: lib.last aspect-chain;
    };
in
{
  flake.tests.deadbugs.issue-645-chained-forward-classes = {

    test-chained-forward-with-host-aspects = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (innerClass den lib)
          (midClass den lib)
        ];

        den.aspects.chained.inner.enable = true;

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.chained ];

        expr = tuxHm.programs.bash.enable or "<stranded>";
        expected = true;
      }
    );

    # Chained content defined on the HOST aspect: dropping the spawn's copy of
    # the inner declaration must not strand what the projection carries.
    test-chained-forward-host-defined = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (innerClass den lib)
          (midClass den lib)
        ];

        den.aspects.chained.inner.enable = true;

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.chained ];

        expr = tuxHm.programs.bash.enable or "<stranded>";
        expected = true;
      }
    );

    # The same chain without the battery — no spawn, so this isolates the
    # chained-declaration collision from anything host-aspects contributes.
    test-chained-forward-without-host-aspects = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [
          (innerClass den lib)
          (midClass den lib)
        ];

        den.aspects.chained.inner.enable = true;

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.aspects.chained ];

        expr = tuxHm.programs.bash.enable or "<stranded>";
        expected = true;
      }
    );

  };
}
