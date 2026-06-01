# Two aspects both contribute to the `atuin` class. The `atuin` aspect forwards
# its own `atuin` content into `programs.atuin` while `igloo` provides `atuin`
# to its users and also contributes flags. Forwarded content from the provider
# aspect must merge with the host's own contribution, not overwrite it.
{ denTest, ... }:
let
  atuinModule =
    { lib, ... }:
    {
      options.programs.atuin.flags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
in
{
  flake.tests.deadbugs.issue-583-forwarding-overwrite = {

    test-forwarded-flags-merge = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        atuinClass =
          { class, aspect-chain }:
          den._.forward {
            each = lib.singleton null;
            fromClass = _: "atuin";
            intoClass = _: "nixos";
            intoPath = _: [
              "programs"
              "atuin"
            ];
            fromAspect = _: lib.head aspect-chain;
            guard = _: true;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.includes = [ den._.mutual-provider ];

        den.aspects.atuin = {
          includes = [
            atuinClass
          ];

          atuin.flags = [
            "--hello"
          ];
        };

        den.aspects.igloo = {
          nixos.imports = [ atuinModule ];

          provides.to-users.includes = [
            den.aspects.atuin
          ];

          atuin.flags = [
            "--world"
            "--baz"
          ];
        };

        expr = lib.sort lib.lessThan igloo.programs.atuin.flags;

        expected = [
          "--baz"
          "--hello"
          "--world"
        ];
      }
    );

  };
}
