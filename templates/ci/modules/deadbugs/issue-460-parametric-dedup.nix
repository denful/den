# Issue #460: Parametric aspects with non-context args (like unfree) were
# silently dropped when included via a parametric wrapper function.
#
# Root cause: applyDeep eagerly replaced includes it couldn't resolve with
# the current context ({host,user}) with {}, destroying them before the
# statics path could resolve them with {class, aspect-chain}.
{ denTest, ... }:
{
  flake.tests.deadbugs-issue-460 = {

    # Baseline: static includes work (never broken).
    test-unfree-static-includes = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.apps._.app-a.includes = [ (den._.unfree [ "drawio" ]) ];
        den.aspects.apps._.app-b.includes = [ (den._.unfree [ "obsidian" ]) ];

        den.aspects.tux.includes = [
          den.aspects.apps._.app-a
          den.aspects.apps._.app-b
        ];

        expr = lib.sort (a: b: a < b) tuxHm.unfree.packages;
        expected = [
          "drawio"
          "obsidian"
        ];
      }
    );

    # Regression: parametric wrapper { host, ... }: { includes = [...] }
    # around sub-aspects whose includes need { class, aspect-chain }.
    test-unfree-parametric-wrapper-fx = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.apps._.app-a.includes = [ (den._.unfree [ "drawio" ]) ];
        den.aspects.apps._.app-b.includes = [ (den._.unfree [ "obsidian" ]) ];

        den.aspects.tux.includes = [
          (
            { host, ... }:
            {
              includes = [
                den.aspects.apps._.app-a
                den.aspects.apps._.app-b
              ];
            }
          )
        ];

        expr = lib.sort (a: b: a < b) tuxHm.unfree.packages;
        expected = [
          "drawio"
          "obsidian"
        ];
      }
    );

    # Same regression on legacy pipeline.
    test-unfree-parametric-wrapper-legacy = denTest (
      {
        den,
        lib,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.apps._.app-a.includes = [ (den._.unfree [ "drawio" ]) ];
        den.aspects.apps._.app-b.includes = [ (den._.unfree [ "obsidian" ]) ];

        den.aspects.tux.includes = [
          (
            { host, ... }:
            {
              includes = [
                den.aspects.apps._.app-a
                den.aspects.apps._.app-b
              ];
            }
          )
        ];

        expr = lib.sort (a: b: a < b) tuxHm.unfree.packages;
        expected = [
          "drawio"
          "obsidian"
        ];
      }
    );

  };
}
