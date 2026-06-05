{ denTest, ... }:
{
  flake.tests.policies = {

    test-policy-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.host-to-test-rel =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include { nixos.users.users.tux.description = "from-rel-target-stage"; })
          ];

        den.default.includes = [ den.policies.host-to-test-rel ];

        expr = igloo.users.users.tux.description;
        expected = "from-rel-target-stage";
      }
    );

    # Both a policy target stage and an into transition contribute
    # to the resolved NixOS config without clobbering each other.
    test-policy-coexists-with-into = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.nixos.users.users.tux.description = "from-default-stage";

        den.policies.host-to-test-rel-coexist =
          _:
          let
            inherit (den.lib.policy) include;
          in
          [
            (include { nixos.networking.hostName = "from-rel-stage"; })
          ];

        den.default.includes = [ den.policies.host-to-test-rel-coexist ];

        expr = [
          igloo.networking.hostName
          igloo.users.users.tux.description
        ];
        expected = [
          "from-rel-stage"
          "from-default-stage"
        ];
      }
    );

  };
}
