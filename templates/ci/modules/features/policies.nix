{ denTest, ... }:
{
  flake.tests.policies = {

    test-policy-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.test-rel-target.includes = [ ];

        den.policies.host-to-test-rel = {
          to = "test-rel-target";
          __functor =
            _:
            {
              __entityKind ? null,
              ...
            }:
            let
              inherit (den.lib.policy) include;
            in
            if __entityKind != "host" then
              [ ]
            else
              [
                (include { nixos.users.users.tux.description = "from-rel-target-stage"; })
              ];
        };

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

        den.schema.test-rel-coexist.includes = [ ];

        den.default.nixos.users.users.tux.description = "from-default-stage";

        den.policies.host-to-test-rel-coexist = {
          to = "test-rel-coexist";
          __functor =
            _:
            {
              __entityKind ? null,
              ...
            }:
            let
              inherit (den.lib.policy) include;
            in
            if __entityKind != "host" then
              [ ]
            else
              [
                (include { nixos.networking.hostName = "from-rel-stage"; })
              ];
        };

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
