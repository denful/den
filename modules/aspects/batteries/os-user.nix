{ den, ... }:
let

  description = ''
    The `user` class is a lightweight user environment
    like `homeManager` without extra dependencies beyond nixpkgs.

    Provides a new `user` class that can be used for setting OS-level
    `users.users.<username>` on NixOS and nix-Darwin hosts.

    For example, the NixOS alice configuration:

      den.aspects.alice.nixos = { pkgs, ... }: {
        users.users.alice = {
          packages = [ pkgs.hello ];
        };
      };

    Becomes, with the `user` class:

      den.aspects.alice.user = { pkgs, ... }: {
         packages = [ pkgs.hello ];
         extraGroups = [ "wheel" ];
      };

    And Den will automatically forward all `user`-class
    definitions to the corresponding OS `users.users.<userName>`
    option level.

  '';

in
{
  den.classes.user.description = "Lightweight user environment forwarding to OS users.users";

  # Built-in policy: route user class content to the host's OS at
  # users.users.<userName>. Injects osConfig so user-class modules
  # can reference the parent NixOS/Darwin config.
  # The route's ensureEntry mechanism creates users.users.<name> even
  # when no user-class content exists (home-manager references the entry).
  den.default.includes = [ den.policies.user-to-host ];

  den.policies.user-to-host =
    { user, host, ... }:
    [
      (den.lib.policy.route {
        fromClass = "user";
        intoClass = host.class;
        path = [
          "users"
          "users"
          user.userName
        ];
        adaptArgs = args: args // { osConfig = args.config; };
      })
    ];
}
