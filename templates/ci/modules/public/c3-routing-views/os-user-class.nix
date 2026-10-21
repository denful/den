{ denTest, ... }:
{
  flake.tests.os-user = {

    test-forwards-user-description = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.user.description = "pinguino";

        expr = igloo.users.users.tux.description;
        expected = "pinguino";
      }
    );

    test-forwards-os-args = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.user =
          { pkgs, ... }:
          {
            description = lib.getName pkgs.hello;
          };

        expr = igloo.users.users.tux.description;
        expected = "hello";
      }
    );

    test-forwards-mergeable-option = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # via user class
        den.aspects.tux.user =
          { pkgs, ... }:
          {
            packages = [ pkgs.hello ];
          };

        # via user nixos
        den.aspects.tux.nixos =
          { pkgs, ... }:
          {
            users.users.tux.packages = [ pkgs.vim ];
          };

        # via host nixos
        den.aspects.igloo.nixos =
          { pkgs, ... }:
          {
            users.users.tux.packages = [ pkgs.tmux ];
          };

        expr = lib.sort (a: b: a < b) (
          lib.filter (
            name:
            lib.elem name [
              "hello"
              "vim"
              "tmux"
            ]
          ) (map lib.getName igloo.users.users.tux.packages)
        );
        expected = [
          "hello"
          "tmux"
          "vim"
        ];
      }
    );

    test-user-class-from-parametric-include = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux = {
          user.description = "owned-description";
          includes = [
            (
              { host, ... }:
              lib.optionalAttrs (host.class == "nixos") {
                user.extraGroups = [ "wheel" ];
              }
            )
          ];
        };

        expr = igloo.users.users.tux.extraGroups;
        expected = [ "wheel" ];
      }
    );
  };
}
