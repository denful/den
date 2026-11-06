# Issue #694, PR 1: a delivery names its receiver (`receiver = <entity record>`)
# and lands in that entity's scope instead of in its source's bucket. These cells
# cover the topologies the receiver walk has to resolve, the collapsed entity
# pushes that needed their own scope id, and den's channels moved onto it.
{ denTest, ... }:
let
  # A guest kind shaped like nix-config's: the guest scope rebinds `host` to the
  # guest record, so its delivery names the parent record explicitly.
  guestFixture =
    {
      den,
      lib,
      config,
      inputs,
      guestUsers ? { },
    }:
    let
      deliverPolicyFor =
        parentHost:
        den.lib.policy.mkPolicy "deliver-guest" (
          { ... }@args:
          lib.optionals (!(args ? user) && !(args ? home)) [
            (den.lib.policy.route {
              fromClass = "nixos";
              intoClass = "nixos";
              collectSubtree = true;
              receiver = parentHost;
              reinstantiate = true;
              path = [
                "microvm"
                "vms"
                "cuda"
                "config"
              ];
            })
          ]
        );
      # The delivery target re-instantiates the collected nixos as its own
      # NixOS system, as microvm.nix's eval-config does. Read `.config.config`.
      microvmSlot =
        { lib, ... }:
        {
          options.microvm.vms = lib.mkOption {
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.config = lib.mkOption {
                  default = null;
                  type = lib.types.nullOr (
                    lib.mkOptionType {
                      name = "reinstantiated NixOS config";
                      merge =
                        _loc: defs:
                        inputs.nixpkgs.lib.nixosSystem {
                          modules = [
                            {
                              nixpkgs.hostPlatform = "x86_64-linux";
                              system.stateVersion = "25.11";
                            }
                          ]
                          ++ map (d: d.value) defs;
                        };
                    }
                  );
                };
              }
            );
          };
        };
      guestRecord = config.den.hosts.x86_64-linux.cuda // {
        intoAttr = [ ];
      };
    in
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.hosts.x86_64-linux.cuda = {
        intoAttr = [ ];
        users = guestUsers;
      };
      # As nix-config's guest kind: it takes part in what a host does
      # (host-to-users, the home-manager battery).
      den.schema.guest-kind = {
        isEntity = true;
        parent = "host";
        isolated = true;
        includes = config.den.schema.host.includes;
      };
      den.policies.resolve-guest =
        { host, ... }:
        lib.optionals (host.name == "igloo") [
          (den.lib.policy.resolve.to.withIncludes "guest-kind" [ (deliverPolicyFor host) ] {
            guest-kind = guestRecord;
            host = guestRecord;
          })
        ];
      den.schema.host.includes = [ den.policies.resolve-guest ];
      den.aspects.igloo.nixos.imports = [ microvmSlot ];
      den.aspects.cuda.nixos.boot.kernelModules = [ "cuda-own" ];
    };

  # The microvm template's topology: host → microvm-host (collapsed, binds only
  # `host`) → microvm-guest (binds `host` and `vm`).
  microvmFixture =
    { den, lib, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      # As in the template: only `includes`, so a routing kind.
      den.schema.microvm-host.parent = "host";
      # Isolated, so only a delivery that names its receiver reaches igloo.
      den.schema.microvm-guest = {
        parent = "microvm-host";
        isolated = true;
      };
      den.policies.to-microvm-host =
        { host, ... }:
        lib.optional (host.name == "igloo") (den.lib.policy.resolve.to "microvm-host" { inherit host; });
      den.policies.to-microvm-guest =
        { host, ... }:
        [
          (den.lib.policy.resolve.to "microvm-guest" {
            inherit host;
            vm.name = "g";
          })
        ];
      den.policies.guest-delivers =
        { host, vm, ... }:
        [
          (den.lib.policy.provide {
            class = "nixos";
            path = [
              "environment"
              "etc"
              "vm-${vm.name}"
              "text"
            ];
            module = "from-guest";
            receiver = host;
          })
        ];
      den.schema.host.includes = [ den.policies.to-microvm-host ];
      den.schema.microvm-host.includes = [ den.policies.to-microvm-guest ];
      den.schema.microvm-guest.includes = [ den.policies.guest-delivers ];
    };
in
{
  flake.tests.deadbugs.issue-694-receiver = {

    # §3 row 1: a user's receiver = host resolves to the host scope. The user
    # is isolated, so the old merge cannot carry it there instead.
    test-user-route-reaches-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.user.isolated = true;
        den.aspects.tux.user.description = "tux the penguin";

        expr = igloo.users.users.tux.description;
        expected = "tux the penguin";
      }
    );

    # §3 row 3: the microvm guest's own scope and microvm-host's have no own
    # entity; the walk passes over both to the real host.
    test-microvm-guest-delivers-to-real-host = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        imports = [ (microvmFixture { inherit den lib; }) ];
        expr = igloo.environment.etc."vm-g".text;
        expected = "from-guest";
      }
    );

    # C4: the microvm-host push (a routing kind) lands on the host's scope id
    # and no longer overwrites the host's kind there.
    test-collapsed-push-keeps-host-kind = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        kinds = config.den.hosts.x86_64-linux.igloo.__resolveResult.scopeEntityKind;
      in
      {
        imports = [ (microvmFixture { inherit den lib; }) ];
        expr = kinds."host=igloo" or null;
        expected = "host";
      }
    );

    # §3 row 2 and C1: the guest's delivery names the parent record and lands
    # at microvm.vms.<name>.config on the parent.
    test-guest-delivery-names-parent = denTest (
      {
        den,
        lib,
        config,
        inputs,
        igloo,
        ...
      }:
      {
        imports = [
          (guestFixture {
            inherit
              den
              lib
              config
              inputs
              ;
          })
        ];
        expr = {
          delivered = lib.elem "cuda-own" igloo.microvm.vms.cuda.config.config.boot.kernelModules;
          leaked = lib.elem "cuda-own" igloo.boot.kernelModules;
        };
        expected = {
          delivered = true;
          leaked = false;
        };
      }
    );

    # §3 row 2: a user inside the guest sees `host` = the guest, so its
    # account reaches the guest, which the delivery carries to the parent.
    test-guest-user-account-reaches-guest = denTest (
      {
        den,
        lib,
        config,
        inputs,
        igloo,
        ...
      }:
      {
        imports = [
          (guestFixture {
            inherit
              den
              lib
              config
              inputs
              ;
            guestUsers.pingu = { };
          })
        ];
        den.aspects.pingu.includes = [ den.batteries.define-user ];
        expr = {
          inGuest = igloo.microvm.vms.cuda.config.config.users.users.pingu.isNormalUser or "<missing>";
          onParent = igloo.users.users ? pingu;
        };
        expected = {
          inGuest = true;
          onParent = false;
        };
      }
    );

    # C5: a home-manager user inside the guest — the guest delivery carries
    # the forward that now lands in the guest's scope.
    test-guest-hm-user-carried = denTest (
      {
        den,
        lib,
        config,
        inputs,
        igloo,
        ...
      }:
      {
        imports = [
          (guestFixture {
            inherit
              den
              lib
              config
              inputs
              ;
            guestUsers.pingu.classes = [ "homeManager" ];
          })
        ];
        den.aspects.pingu.homeManager.home.sessionVariables.GUEST = "yes";
        expr = {
          carried =
            igloo.microvm.vms.cuda.config.config.home-manager.users.pingu.home.sessionVariables.GUEST
              or "<missing>";
          onParent = igloo.home-manager.users ? pingu;
        };
        expected = {
          carried = "yes";
          onParent = false;
        };
      }
    );

    # C6: two users' provides from one battery policy stay separate.
    test-two-users-shells-and-unfree = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux.classes = [ "homeManager" ];
          pingu.classes = [ "homeManager" ];
        };
        # One policy, fired at both user scopes.
        den.policies.per-user-etc =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              module.environment.etc."u-${user.userName}".text = user.userName;
              receiver = host;
            })
          ];
        den.schema.user.includes = [ den.policies.per-user-etc ];
        den.aspects.tux.includes = [
          (den.batteries.user-shell "fish")
          (den.batteries.unfree [ "tux-unfree" ])
        ];
        den.aspects.pingu.includes = [
          (den.batteries.user-shell "zsh")
          (den.batteries.unfree [ "pingu-unfree" ])
        ];
        expr = {
          fish = igloo.programs.fish.enable;
          zsh = igloo.programs.zsh.enable;
          tuxShell = igloo.users.users.tux.shell.pname or null;
          pinguShell = igloo.users.users.pingu.shell.pname or null;
          unfree = lib.sort (a: b: a < b) igloo.unfree.packages;
          perUser = [
            igloo.environment.etc.u-tux.text
            igloo.environment.etc.u-pingu.text
          ];
        };
        expected = {
          fish = true;
          zsh = true;
          tuxShell = "fish";
          pinguShell = "zsh";
          unfree = [
            "pingu-unfree"
            "tux-unfree"
          ];
          perUser = [
            "tux"
            "pingu"
          ];
        };
      }
    );

    # C7: users resolved by a policy (no host.users entry) still get the
    # home-manager NixOS module, as in fleet-demo.
    test-policy-resolved-user-gets-hm-module = denTest (
      {
        den,
        lib,
        config,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.home-manager.enable = true;
        # The record comes from elsewhere; igloo declares no users.
        den.hosts.x86_64-linux.registry.users.tux.classes = [ "homeManager" ];
        den.policies.registry-users =
          { host, ... }:
          lib.optional (host.name == "igloo") (
            den.lib.policy.resolve.to "user" {
              user = config.den.hosts.x86_64-linux.registry.users.tux;
            }
          );
        den.schema.host.includes = [ den.policies.registry-users ];
        den.aspects.tux.homeManager.home.sessionVariables.FLEET = "yes";
        expr = igloo.home-manager.users.tux.home.sessionVariables.FLEET or "<missing>";
        expected = "yes";
      }
    );

    # A WSL host pushes the routing kind `wsl-host` onto its own scope; an
    # unkeyed `den.default` `{ host }` function must still apply once.
    test-wsl-host-no-duplicate-default = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        # No users: a `{ host }` function re-applied at a user scope is the
        # separate den.default duplicate (#694 §8), not this one.
        den.hosts.x86_64-linux.igloo = {
          wsl.enable = true;
          wsl.module =
            { lib, ... }:
            {
              options.wsl = lib.mkOption {
                type = lib.types.lazyAttrsOf lib.types.anything;
                default = { };
              };
            };
        };
        den.default.includes = [
          (
            { host, ... }:
            {
              nixos =
                { pkgs, ... }:
                {
                  environment.etc.default-host.text = "once";
                };
            }
          )
        ];
        expr = {
          # `environment.etc.<n>.text` is unique: a second definition would throw.
          text = igloo.environment.etc.default-host.text;
          wsl = igloo.wsl.enable or false;
        };
        expected = {
          text = "once";
          wsl = true;
        };
      }
    );

    # An entity kind resolved with no binding that names it would share its
    # parent's node; it is refused by name rather than merged into it.
    test-entity-push-without-binding-refused = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.bare-kid = {
          isEntity = true;
          parent = "host";
        };
        den.policies.to-bare-kid =
          { host, ... }:
          lib.optional (host.name == "igloo") (den.lib.policy.resolve.to "bare-kid" { inherit host; });
        den.schema.host.includes = [ den.policies.to-bare-kid ];
        expr = igloo.networking.hostName;
        expectedError = {
          type = "ThrownError";
          msg = "entity kind 'bare-kid' was resolved at scope";
        };
      }
    );

    # A host-side include of a user battery fans out over the host's users;
    # the users' account settings still reach them.
    test-host-included-primary-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.primary-user ];
        expr = {
          normal = igloo.users.users.tux.isNormalUser;
          groups = builtins.sort (a: b: a < b) igloo.users.users.tux.extraGroups;
        };
        expected = {
          normal = true;
          groups = [
            "networkmanager"
            "wheel"
          ];
        };
      }
    );

    # Two users with the same unfree list deliver it once.
    test-identical-unfree-lists-once = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux.classes = [ "homeManager" ];
          pingu.classes = [ "homeManager" ];
        };
        den.aspects.tux.includes = [ (den.batteries.unfree [ "shared" ]) ];
        den.aspects.pingu.includes = [ (den.batteries.unfree [ "shared" ]) ];
        expr = igloo.unfree.packages;
        expected = [ "shared" ];
      }
    );

    # A user-rooted static resolve binds its host but builds no host scope: a
    # delivery to that host is dropped there rather than failing the walk, and
    # the user's own content still resolves.
    test-root-binds-receiver-not-built = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        resolved = den.lib.aspects.resolveImports "nixos" (
          den.lib.resolveEntity "user" {
            host = config.den.hosts.x86_64-linux.igloo;
            user = config.den.hosts.x86_64-linux.igloo.users.tux;
          }
        );
        evaluated = lib.evalModules {
          modules = resolved.imports ++ [
            { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
          ];
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos.ownMarker = "tux";
        den.policies.tux-to-host =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              module.toHost = "delivered";
              receiver = host;
            })
          ];
        den.schema.user.includes = [ den.policies.tux-to-host ];
        expr = {
          own = evaluated.config.ownMarker or "<missing>";
          dropped = evaluated.config ? toHost;
        };
        expected = {
          own = "tux";
          dropped = false;
        };
      }
    );

    # A host whose class is not an OS gets none of the account or shell
    # settings, as on main.
    test-non-os-host-gets-no-account-settings = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        mods =
          (den.lib.aspects.resolve "systemManager" (
            den.lib.resolveEntity "host" { host = config.den.hosts.x86_64-linux.sm; }
          )).imports;
        cfg =
          (lib.evalModules {
            modules = mods ++ [
              { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
            ];
          }).config;
      in
      {
        den.classes.systemManager.description = "a non-OS host class";
        den.hosts.x86_64-linux.sm = {
          class = "systemManager";
          intoAttr = [ ];
          users.tux = { };
        };
        den.aspects.tux.includes = [
          den.batteries.define-user
          den.batteries.primary-user
          (den.batteries.user-shell "fish")
        ];
        # `user-to-host` still makes the account entry, as on main; the
        # batteries add nothing to it and no shell.
        expr = {
          account = builtins.attrNames (cfg.users.users.tux or { });
          programs = cfg ? programs;
        };
        expected = {
          account = [ ];
          programs = false;
        };
      }
    );

    # On darwin, primary-user writes `system.primaryUser` and no nixos-only
    # account options.
    test-darwin-primary-user-no-nixos-account = denTest (
      { den, apple, ... }:
      {
        den.hosts.aarch64-darwin.apple.users.tux = { };
        den.aspects.tux.includes = [ den.batteries.primary-user ];
        expr = {
          primary = apple.system.primaryUser;
          normal = apple.users.users.tux ? isNormalUser;
        };
        expected = {
          primary = "tux";
          normal = false;
        };
      }
    );

    # A receiver that is not on the source's chain fails loudly.
    test-unknown-receiver-throws = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.bad-receiver =
          { user, host, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              module.environment.etc.bad.text = "x";
              receiver = {
                name = "nowhere";
                id_hash = "nowhere";
              };
            })
          ];
        den.schema.user.includes = [ den.policies.bad-receiver ];
        expr = igloo.environment.etc.bad.text;
        expectedError = {
          type = "ThrownError";
          msg = "is not an entity on the chain";
        };
      }
    );
  };
}
