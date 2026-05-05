{ denTest, ... }:
{
  flake.tests.deadbugs-issue-297 = {

    test-mutual-host-owned = denTest (
      {
        den,
        lib,
        igloo, # igloo = nixosConfigurations.igloo.config
        tuxHm, # tuxHm = igloo.home-manager.users.tux
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              homeManager.home.keyboard.model = "denkbd";
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = tuxHm.home.keyboard.model;
        expected = "denkbd";
      }
    );

    test-mutual-host-included-statics = denTest (
      {
        den,
        lib,
        igloo, # igloo = nixosConfigurations.igloo.config
        tuxHm, # tuxHm = igloo.home-manager.users.tux
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];

        den.aspects.base.homeManager.home.keyboard.model = "denkbd";
        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [ den.aspects.base ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = tuxHm.home.keyboard.model;
        expected = "denkbd";
      }
    );

    test-mutual-host-owned-home-option = denTest (
      {
        den,
        lib,
        igloo, # igloo = nixosConfigurations.igloo.config
        tuxHm, # tuxHm = igloo.home-manager.users.tux
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];

        # Named aspect for dedup: policies fire per-user but the option
        # declaration should only be included once.
        den.aspects.igloo-foo-option.homeManager.options.foo = lib.mkOption { default = "foo"; };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include den.aspects.igloo-foo-option)
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];

        expr = tuxHm.foo;
        expected = "foo";
      }
    );

    test-mutual-host-owned-host-option = denTest (
      {
        den,
        lib,
        igloo, # igloo = nixosConfigurations.igloo.config
        tuxHm, # tuxHm = igloo.home-manager.users.tux
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];

        # NOTE: Under policies, use perHost for host-only options
        den.aspects.igloo.includes = [
          (den.lib.perHost {
            nixos.options.foo = lib.mkOption { default = "foo"; };
          })
        ];

        expr = igloo.foo;
        expected = "foo";
      }
    );

  };
}
