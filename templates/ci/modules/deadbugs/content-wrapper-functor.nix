{ denTest, ... }:
{
  flake.tests.deadbugs.content-wrapper-functor = {

    # Bug 2: multiple files defining den.aspects.system.base.nixos
    # with a mix of attrsets and a function
    test-multi-def-merge-mixed = denTest (
      { den, igloo, ... }:
      {
        imports = [
          { den.aspects.system.base.nixos.console.keyMap = "fr"; }
          {
            den.aspects.system.base.nixos.nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
          { den.aspects.system.base.nixos = { pkgs, ... }: { }; }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.system ];
        den.aspects.system.includes = [ den.aspects.system.base ];

        expr = {
          hasKeyMap = igloo.console.keyMap == "fr";
          hasFlakes = builtins.elem "flakes" igloo.nix.settings.experimental-features;
        };
        expected = {
          hasKeyMap = true;
          hasFlakes = true;
        };
      }
    );

    # Bug 2 variant: all attrsets, no functions
    test-multi-def-merge-attrsets-only = denTest (
      { den, igloo, ... }:
      {
        imports = [
          { den.aspects.system.base.nixos.console.keyMap = "fr"; }
          {
            den.aspects.system.base.nixos.nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.system ];
        den.aspects.system.includes = [ den.aspects.system.base ];

        expr = {
          hasKeyMap = igloo.console.keyMap == "fr";
          hasFlakes = builtins.elem "flakes" igloo.nix.settings.experimental-features;
        };
        expected = {
          hasKeyMap = true;
          hasFlakes = true;
        };
      }
    );

    # Bug 3: parametric aspect without provides
    test-parametric-without-provides = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.wm.gnome-autologin = username: {
          nixos.services.displayManager.autoLogin = {
            enable = true;
            user = username;
          };
        };

        den.aspects.igloo.includes = [
          (den.aspects.wm.gnome-autologin "benjamin")
        ];

        expr = igloo.services.displayManager.autoLogin.user;
        expected = "benjamin";
      }
    );
  };
}
