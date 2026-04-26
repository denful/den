{ lib, den, ... }:
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

  fwd =
    { user, host }:
    den.provides.forward {
      each = lib.singleton user;
      fromClass = _: "user";
      intoClass = _: host.class;
      intoPath = _: [
        "users"
        "users"
        user.userName
      ];
      fromAspect = _: user.aspect;
      fromCtx = _: { inherit host user; };
      adaptArgs = args: args // { osConfig = args.config; };
    };

in
{
  den.entityIncludes.user = [ fwd ];

  den.classes.user.description = "Lightweight user environment forwarding to OS users.users";
}
