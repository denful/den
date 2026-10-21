# Producer-class resolution for the DEFERRED (__configThunk) path: a pipe
# config-thunk must resolve against the PRODUCING class module + scope, not the
# consuming one. Same-host; the cross-host eager path is covered by pipe-broadcast.
{ denTest, lib, ... }:
{
  flake.tests.pipe-config-scope = {

    # Host-PRODUCED config-thunk (reads a nixos field) CONSUMED in a home (a
    # different class). Must resolve against the host's nixos config (producing
    # class), not the home config — which would throw `networking missing`.
    test-host-produced-consumed-in-home = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.dev.description = "device";

        den.aspects.set-hostname.nixos =
          { host, ... }:
          {
            networking.hostName = host.name;
          };
        den.policies.bind-dev =
          { host, ... }:
          let
            inherit (den.lib.policy) pipe;
          in
          [ (pipe.from "dev" [ ]) ];
        den.schema.host.includes = [
          den.aspects.set-hostname
          den.policies.bind-dev
        ];

        # PRODUCED at host scope, reads a NIXOS field.
        den.aspects.igloo.dev = { config, ... }: [ "h:${config.networking.hostName}" ];

        # CONSUMED in tux's home (different class) via pure-consumer inheritance.
        den.aspects.tux.homeManager =
          { dev, ... }:
          {
            home.sessionVariables.DEV = builtins.head dev;
          };

        expr = tuxHm.home.sessionVariables.DEV;
        expected = "h:igloo";
      }
    );

    # Same-scope same-class (the common case) keeps working: a user-produced
    # config-thunk reading a HOME field, consumed in the same user's home.
    test-user-produced-consumed-in-own-home = denTest (
      {
        den,
        tuxHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.dev.description = "device";

        den.aspects.tux = {
          dev = { config, ... }: [ "u:${config.home.username}" ];
          homeManager =
            { dev, ... }:
            {
              home.sessionVariables.DEV = builtins.head dev;
            };
        };

        expr = tuxHm.home.sessionVariables.DEV;
        expected = "u:tux";
      }
    );

    # User-PRODUCED config-thunk reading a HOME field, exposed up and CONSUMED in
    # the host's nixos (cross-class user→host). Resolves against the producer's
    # home-manager config — the user's own home, not the consuming host config.
    test-user-produced-consumed-in-host = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.dev.description = "device";

        den.policies.expose-dev =
          { user, ... }: [ (den.lib.policy.pipe.from "dev" [ den.lib.policy.pipe.expose ]) ];
        den.schema.user.includes = [ den.policies.expose-dev ];

        # PRODUCED at the user node, reads a HOME field.
        den.aspects.tux.dev = { config, ... }: [ "u:${config.home.username}" ];

        den.aspects.igloo.nixos =
          { dev, ... }:
          {
            networking.domain = builtins.head dev;
          };

        expr = igloo.networking.domain;
        expected = "u:tux";
      }
    );
  };
}
