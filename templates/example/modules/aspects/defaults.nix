{
  config,
  # deadnix: skip # enable <den/brackets> syntax for demo.
  __findFile ? __findFile,
  den,
  ...
}:
{
  # Lets also configure some defaults using aspects.
  # These are global static settings.
  den.default = {
    darwin.system.stateVersion = 6;
    nixos.system.stateVersion = "25.05";
    homeManager.home.stateVersion = "25.05";
  };

  # These are functions that produce configs
  den.default.includes = [
    # Automatically set hostname
    <den/hostname>

    # Automatically create the user on host.
    <den/define-user>

    # Disable booting when running on CI on all NixOS hosts.
    (if config ? _module.args.CI then <eg/ci-no-boot> else { })

    # NOTE: be cautious when adding fully parametric functions to defaults.
    # defaults are included on EVERY host/user/home, and IF you are not careful
    # you could be duplicating config values. For example:
    #
    #  # This will append 42 into foo option for the {host} and for EVERY {host,user}
    #     ({ host, ... }: { nixos.foo = [ 42 ]; }) # DO-NOT-DO-THIS.
    #
    #  # Instead try to be explicit if a function is intended for ONLY { host }
    #     den.lib.perHost ({ host }: { nixos.foo = [ 42 ]; })
    #  # Or for { host, user } ONLY:
    #     den.lib.perUser ({ host, user }: { nixos.foo = [ 42 ]; })
    #  # Or for standalone homes ({ home }) ONLY:
    #     den.lib.perHome ({ home }: { homeManager.foo = [ 42 ]; })
  ];
}
