# Issue #674: identical values from multiple aspects must merge, not conflict.
#
# route.nix's `mergeableType` deep-merges attrsets and concatenates lists, but
# anything else (scalars, derivations) hit the conflict throw — even when every
# definition was the same value. NixOS's own `mergeEqualOption` accepts equal
# definitions, so `enable = true` in two aspects broke where plain NixOS is fine.
{ denTest, inputs, ... }:
{
  imports = [ inputs.den.flakeOutputs.packages ];

  flake.tests.deadbugs-issue-674 = {

    # Two aspects producing the same derivation at the same key.
    test-identical-derivations-merge = denTest (
      {
        config,
        den,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.pkg-one.packages =
          { pkgs, ... }:
          {
            shared = pkgs.writeText "shared" "same";
          };

        den.aspects.pkg-two.packages =
          { pkgs, ... }:
          {
            shared = pkgs.writeText "shared" "same";
          };

        den.schema.flake-system.includes = [
          den.aspects.pkg-one
          den.aspects.pkg-two
        ];

        expr = builtins.readFile config.flake.packages.x86_64-linux.shared;
        expected = "same";
      }
    );

    # The reported symptom: the same scalar set by two aspects. Deep-merging the
    # app attrset descends to `type`/`program`, which have two defs apiece.
    test-identical-scalars-merge = denTest (
      {
        config,
        den,
        inputs,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.apps ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.app-one.apps =
          { pkgs, ... }:
          {
            shared = {
              type = "app";
              program = "${pkgs.hello}/bin/hello";
            };
          };

        den.aspects.app-two.apps =
          { pkgs, ... }:
          {
            shared = {
              type = "app";
              program = "${pkgs.hello}/bin/hello";
            };
          };

        den.schema.flake-system.includes = [
          den.aspects.app-one
          den.aspects.app-two
        ];

        expr = config.flake.apps.x86_64-linux.shared.type;
        expected = "app";
      }
    );

    # Negative control: disagreeing definitions must still be a hard conflict.
    test-conflicting-values-still-throw = denTest (
      {
        config,
        den,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.pkg-one.packages =
          { pkgs, ... }:
          {
            shared = pkgs.writeText "shared" "one";
          };

        den.aspects.pkg-two.packages =
          { pkgs, ... }:
          {
            shared = pkgs.writeText "shared" "two";
          };

        den.schema.flake-system.includes = [
          den.aspects.pkg-one
          den.aspects.pkg-two
        ];

        expr =
          (builtins.tryEval (builtins.seq config.flake.packages.x86_64-linux.shared.outPath true)).success;
        expected = false;
      }
    );
  };
}
