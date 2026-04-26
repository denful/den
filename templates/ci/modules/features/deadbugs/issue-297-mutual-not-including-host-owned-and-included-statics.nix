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
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.schema.user.includes = [ den.provides.mutual-provider ];

        den.aspects.igloo.provides.to-users.homeManager.home.keyboard.model = "denkbd";

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
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.schema.user.includes = [ den.provides.mutual-provider ];

        den.aspects.base.homeManager.home.keyboard.model = "denkbd";
        den.aspects.igloo.provides.to-users.includes = [ den.aspects.base ];

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
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.schema.user.includes = [ den.provides.mutual-provider ];

        den.aspects.igloo.provides.to-users.homeManager.options.foo = lib.mkOption { default = "foo"; };

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
        den.schema.user.includes = [ den.provides.mutual-provider ];

        # NOTE: this causes an error: Option already defined!
        # This is because mutuality includes host configs again.
        # den.aspects.igloo.nixos.options.foo = lib.mkOption { default = "foo"; };
        # NOTE: Under mutuality, use perHost
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
