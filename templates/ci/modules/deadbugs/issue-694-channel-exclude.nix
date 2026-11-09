# Issue #694: den's channels that carry a user's settings to its host can be
# switched off by excluding them by name. Each has a control that keeps the
# channel. Host-side revocation of define-user, primary-user and user-shell
# lands with receiver acceptance (PR 4).
{ denTest, ... }:
let
  freeform =
    lib:
    lib.types.submoduleWith {
      modules = [ { config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified; } ];
    };
  mockHjem =
    { lib, ... }:
    {
      options.hjem.users = lib.mkOption {
        type = lib.types.attrsOf (freeform lib);
        default = { };
      };
    };
  mockMaid =
    { lib, ... }:
    {
      options.users.users = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.maid = lib.mkOption {
              type = freeform lib;
              default = { };
            };
          }
        );
      };
    };
  # A user-side exclude of the env's user arm by name.
  excludeUserArm =
    lib: config: n:
    lib.concatMap (
      i: lib.filter (j: (j.name or null) == n) (i.includes or [ ])
    ) config.den.schema.user.includes;
  twoUsers = {
    den.hosts.x86_64-linux.igloo.users = {
      tux = { };
      pingu = { };
    };
  };
in
{
  flake.tests.deadbugs.issue-694-channel-exclude = {

    # user-to-host: the `user` class into users.users.<name>.
    test-user-to-host-control = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.user.description = "tux";
        expr = igloo.users.users.tux.description;
        expected = "tux";
      }
    );
    test-user-to-host-excluded-host-side = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.igloo.excludes = [ den.policies.user-to-host ];
        den.aspects.tux.user.description = "tux";
        expr = igloo.users.users.tux.description or "<absent>";
        expected = "<absent>";
      }
    );
    test-user-to-host-excluded-user-side = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.schema.user.excludes = [ den.policies.user-to-host ];
        den.aspects.tux.user.description = "tux";
        expr = igloo.users.users.tux.description or "<absent>";
        expected = "<absent>";
      }
    );

    # define-user: the account entry.
    test-define-user-control = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ den.batteries.define-user ];
        expr = igloo.users.users.tux.isNormalUser;
        expected = true;
      }
    );
    test-define-user-excluded-user-side = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ den.batteries.define-user ];
        den.schema.user.excludes = [ den.batteries.define-user ];
        expr = igloo.users.users.tux.isNormalUser;
        expected = false;
      }
    );

    # primary-user: wheel.
    test-primary-user-control = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ den.batteries.primary-user ];
        expr = builtins.elem "wheel" igloo.users.users.tux.extraGroups;
        expected = true;
      }
    );
    test-primary-user-excluded-user-side = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ den.batteries.primary-user ];
        den.schema.user.excludes = [ den.batteries.primary-user ];
        expr = builtins.elem "wheel" igloo.users.users.tux.extraGroups;
        expected = false;
      }
    );

    # user-shell: programs.<shell>.enable.
    test-user-shell-control = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ (den.batteries.user-shell "fish") ];
        expr = igloo.programs.fish.enable;
        expected = true;
      }
    );

    # The home-manager forward: home-manager.users.<name>. Its two arms are the
    # host battery and the user-side detector, both named policies on the
    # schema includes.
    test-hm-forward-control = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.homeManager.home.sessionVariables.FROM = "tux";
        expr = igloo.home-manager.users.tux.home.sessionVariables.FROM;
        expected = "tux";
      }
    );
    test-hm-forward-excluded-host-side = denTest (
      {
        den,
        lib,
        config,
        igloo,
        ...
      }:
      let
        # The battery's arms are unnamed wrappers around named policies.
        policiesNamed =
          n: incs: lib.concatMap (i: lib.filter (j: (j.name or null) == n) (i.includes or [ ])) incs;
        selected =
          policiesNamed "host-to-hm-users" config.den.schema.host.includes
          ++ policiesNamed "hm-user-detect" config.den.schema.user.includes;
      in
      {
        imports = [ twoUsers ];
        den.aspects.igloo.excludes = selected;
        den.aspects.tux.homeManager.home.sessionVariables.FROM = "tux";
        expr = {
          selected = builtins.length selected;
          # The host battery is excluded too, so igloo gets no home-manager
          # option at all.
          delivered = igloo ? home-manager;
        };
        expected = {
          selected = 2;
          delivered = false;
        };
      }
    );
    test-hm-forward-excluded-user-side = denTest (
      {
        den,
        lib,
        config,
        igloo,
        ...
      }:
      let
        policiesNamed =
          n: incs: lib.concatMap (i: lib.filter (j: (j.name or null) == n) (i.includes or [ ])) incs;
        selected = policiesNamed "hm-user-detect" config.den.schema.user.includes;
      in
      {
        imports = [ twoUsers ];
        den.schema.user.excludes = selected;
        den.aspects.tux.homeManager.home.sessionVariables.FROM = "tux";
        expr = {
          selected = builtins.length selected;
          # The user arm is off; the host arm still forwards for host.users
          # users, so tux's home-manager config still arrives, and the host
          # keeps the home-manager module (the host arm imports it itself).
          delivered = igloo.home-manager.users ? tux;
        };
        expected = {
          selected = 1;
          delivered = true;
        };
      }
    );

    # The host arm imports each home environment's NixOS module itself, so a
    # user-side exclude of the user arm leaves the host with the module.
    test-hm-module-kept-when-user-arm-excluded = denTest (
      {
        den,
        lib,
        config,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.user.excludes = excludeUserArm lib config "hm-user-detect";
        expr = igloo ? home-manager;
        expected = true;
      }
    );
    test-hjem-module-kept-when-user-arm-excluded = denTest (
      {
        den,
        lib,
        config,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "hjem" ];
          hjem.module = mockHjem;
        };
        den.schema.user.excludes = excludeUserArm lib config "hjem-user-detect";
        expr = igloo ? hjem;
        expected = true;
      }
    );
    test-maid-module-kept-when-user-arm-excluded = denTest (
      {
        den,
        lib,
        config,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "maid" ];
          nix-maid.module = mockMaid;
        };
        den.schema.user.excludes = excludeUserArm lib config "maid-user-detect";
        expr = (igloo.users.users.tux or { }) ? maid;
        expected = true;
      }
    );
  };
}
