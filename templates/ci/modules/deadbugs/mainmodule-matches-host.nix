# A host's `mainModule` is the config den builds for it: built on its own it
# carries the same host-class content as `nixosConfigurations`. It used to miss
# what a host delivered to its users and got back through them
# (`provides.to-users`, `provides.<user>`): the host-rooted walk didn't know its
# root was the host, so the host's own policies found no registrant.
#
# Each cell compares the markers that land in the two configs. Both lists always
# hold the base marker, so an expectation is never empty.
{ denTest, lib, ... }:
let
  marks =
    etc: builtins.sort (a: b: a < b) (builtins.filter (lib.hasPrefix "mark-") (builtins.attrNames etc));

  paths = {
    p1-host-includes =
      { den, ... }:
      {
        den.aspects.igloo.includes = [ den.aspects.probeX ];
      };
    p2-host-provides-to-users =
      { den, ... }:
      {
        den.aspects.igloo.provides.to-users.includes = [ den.aspects.probeX ];
      };
    p3-host-provides-tux =
      { den, ... }:
      {
        den.aspects.igloo.provides.tux.includes = [ den.aspects.probeX ];
      };
    p4-user-includes =
      { den, ... }:
      {
        den.aspects.tux.includes = [ den.aspects.probeX ];
      };
    p5-user-at-host =
      { den, ... }:
      {
        den.aspects."tux@igloo".includes = [ den.aspects.probeX ];
      };
    p6-nested-host-key =
      { den, ... }:
      {
        den.aspects.igloo.tux.includes = [ den.aspects.probeX ];
      };
    p7-host-includes-tux-host-aspects =
      { den, ... }:
      {
        den.aspects.igloo.includes = [ den.aspects.probeX ];
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
      };
    p8-default-includes =
      { den, ... }:
      {
        den.default.includes = [ den.aspects.probeX ];
      };
    p9-schema-user-includes =
      { den, ... }:
      {
        den.schema.user.includes = [ den.aspects.probeX ];
      };
    # A host policy firing at user scope with no receiver is aimed at the host.
    r-aimed-provide =
      { den, ... }:
      {
        den.aspects.igloo.policies.aimed =
          { user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              module.environment.etc."mark-aimed-${user.name}".text = "y";
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.aimed ];
      };
    # `admits.default = "deny"` doesn't check the host's own to-users delivery
    # coming back (by design), so it lands in both builds.
    r-admits-deny =
      { den, ... }:
      {
        den.aspects.igloo.provides.to-users.includes = [ den.aspects.probeX ];
        den.aspects.igloo.admits.default = "deny";
      };
  };

  fixture =
    transition: path:
    { den, ... }:
    {
      imports = [ path ];
      den.internal.transitionDefaults = lib.mkForce transition;
      den.aspects.probeX.nixos.environment.etc."mark-x".text = "x";
      den.default.includes = [ den._.define-user ];
      den.default.nixos = {
        environment.etc."mark-base".text = "b";
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/null";
          fsType = "auto";
        };
      };
      den.schema.user.classes = [ "homeManager" ];
      den.hosts.x86_64-linux.igloo.users = {
        tux = { };
        pingu = { };
      };
    };

  cell =
    transition: path:
    denTest (
      { den, igloo, ... }:
      let
        h = den.hosts.x86_64-linux.igloo;
        fromMain =
          (h.instantiate {
            modules = [
              h.mainModule
              { nixpkgs.hostPlatform = h.system; }
            ];
          }).config;
      in
      {
        imports = [ (fixture transition path) ];
        expr = marks fromMain.environment.etc;
        expected = marks igloo.environment.etc;
      }
    );
in
{
  flake.tests.mainmodule-matches-host =
    lib.mapAttrs' (n: p: lib.nameValuePair "test-end-state-${n}" (cell false p)) paths
    # admits.default = "deny" refuses the transition default itself.
    // lib.mapAttrs' (n: p: lib.nameValuePair "test-transition-${n}" (cell true p)) (
      builtins.removeAttrs paths [ "r-admits-deny" ]
    )
    // {
      # An aimed provide refused by `admits.default = "deny"` throws in
      # mainModule as it does in nixosConfigurations.
      test-aimed-provide-admits-deny-throws = denTest (
        { den, ... }:
        let
          h = den.hosts.x86_64-linux.igloo;
          fromMain =
            (h.instantiate {
              modules = [
                h.mainModule
                { nixpkgs.hostPlatform = h.system; }
              ];
            }).config;
        in
        {
          imports = [ (fixture false paths.r-aimed-provide) ];
          den.aspects.igloo.admits.default = "deny";
          expr = marks fromMain.environment.etc;
          expectedError = {
            type = "ThrownError";
            msg = "den: delivery of";
          };
        }
      );

      # A standalone home's mainModule is its homeConfigurations config.
      test-home-mainmodule-matches = denTest (
        { den, config, ... }:
        let
          home = den.homes.x86_64-linux."tux@igloo";
          fromMain =
            (home.instantiate {
              pkgs = home.pkgs;
              modules = [ home.mainModule ];
            }).config;
          hmMarks =
            files:
            builtins.sort (a: b: a < b) (builtins.filter (lib.hasPrefix "mark-") (builtins.attrNames files));
        in
        {
          den.aspects.probeX.homeManager.home.file."mark-x".text = "x";
          den.aspects.igloo.provides.to-users.includes = [ den.aspects.probeX ];
          den.aspects.tux.homeManager.home.file."mark-base".text = "b";
          den.default.includes = [ den._.define-user ];
          den.hosts.x86_64-linux.igloo.users.tux = { };
          den.homes.x86_64-linux."tux@igloo" = { };
          expr = hmMarks fromMain.home.file;
          expected = hmMarks config.flake.homeConfigurations."tux@igloo".config.home.file;
        }
      );
    };
}
