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

  # Hosts receive what their users provide them (`provides.to-hosts`, see
  # alice.nix).
  den.schema.host.includes = [ den.batteries.mutual-provider ];

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
    #  # A plain function destructuring { host } binds host once at the host
    #  # scope (nixos-class content emits there):
    #     ({ host, ... }: { nixos.foo = [ 42 ]; })
    #  # Destructuring { host, user } fans out over the host's users and emits
    #  # on the host (one nixos contribution per user); the bound user is the
    #  # arg source, not the output target. At user scope both args are in-ctx
    #  # and it binds once:
    #     ({ host, user, ... }: { nixos.foo = [ 42 ]; })
    #  # Destructuring { home } binds home at standalone-home scope:
    #     ({ home, ... }: { homeManager.foo = [ 42 ]; })
  ];
}
