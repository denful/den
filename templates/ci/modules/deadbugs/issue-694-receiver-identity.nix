# #694 receivers named per entity, on a guest of igloo (a microvm-shaped kind
# whose subtree #746 delivers into igloo at microvm.vms.cuda.config). id_hash
# is parent-blind, so the same user name on the host and in its guest must
# still be two deliveries; a guest record without an id_hash is matched by
# value, and a receiver that is not a record is an error.
{ denTest, ... }:
let
  guestFx =
    {
      den,
      lib,
      config,
      inputs,
      guestUsers ? { },
      stripId ? false,
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
      base = config.den.hosts.x86_64-linux.cuda;
      guestRecord = (if stripId then builtins.removeAttrs base [ "id_hash" ] else base) // {
        intoAttr = [ ];
      };
    in
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.hosts.x86_64-linux.cuda = {
        intoAttr = [ ];
        users = guestUsers;
      };
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
    };
in
{
  flake.tests.deadbugs.issue-694-receiver-identity = {

    # Same user name on the host and in its guest: two provides, one key.
    test-same-user-on-host-and-guest-both-get-account = denTest (
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
          (guestFx {
            inherit
              den
              lib
              config
              inputs
              ;
            guestUsers.tux = { };
          })
        ];
        den.aspects.tux.includes = [ den.batteries.define-user ];
        expr = {
          inGuest = igloo.microvm.vms.cuda.config.config.users.users.tux.isNormalUser or "<missing>";
          onParent = igloo.users.users.tux.isNormalUser or "<missing>";
        };
        expected = {
          inGuest = true;
          onParent = true;
        };
      }
    );

    # Control: distinct names, same fixture.
    test-distinct-users-control = denTest (
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
          (guestFx {
            inherit
              den
              lib
              config
              inputs
              ;
            guestUsers.pingu = { };
          })
        ];
        den.aspects.tux.includes = [ den.batteries.define-user ];
        den.aspects.pingu.includes = [ den.batteries.define-user ];
        expr = {
          inGuest = igloo.microvm.vms.cuda.config.config.users.users.pingu.isNormalUser or "<missing>";
          onParent = igloo.users.users.tux.isNormalUser or "<missing>";
        };
        expected = {
          inGuest = true;
          onParent = true;
        };
      }
    );

    # Same user, home-manager on both: the guest's HM module import and forward.
    test-same-user-hm-on-host-and-guest = denTest (
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
          (guestFx {
            inherit
              den
              lib
              config
              inputs
              ;
            guestUsers.tux.classes = [ "homeManager" ];
          })
        ];
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.sessionVariables.PROBE = "yes";
        expr = {
          inGuest =
            igloo.microvm.vms.cuda.config.config.home-manager.users.tux.home.sessionVariables.PROBE
              or "<missing>";
          onParent = igloo.home-manager.users.tux.home.sessionVariables.PROBE or "<missing>";
        };
        expected = {
          inGuest = "yes";
          onParent = "yes";
        };
      }
    );

    # By-value receiver: the guest record carries no id_hash.
    test-by-value-guest-receives = denTest (
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
          (guestFx {
            inherit
              den
              lib
              config
              inputs
              ;
            guestUsers.pingu = { };
            stripId = true;
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

    # By-value receiver whose name equals one of its users' names.
    test-by-value-guest-named-like-its-user = denTest (
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
          (guestFx {
            inherit
              den
              lib
              config
              inputs
              ;
            guestUsers.cuda = { };
            stripId = true;
          })
        ];
        den.aspects.cuda.includes = [ den.batteries.define-user ];
        expr = igloo.microvm.vms.cuda.config.config.users.users.cuda.isNormalUser or "<missing>";
        expected = true;
      }
    );

    # The non-record receiver error.
    test-non-record-receiver-is-an-error = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.str-receiver =
          { user, host, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              module.environment.etc.bad.text = "x";
              receiver = "igloo";
            })
          ];
        den.schema.user.includes = [ den.policies.str-receiver ];
        expr = igloo.environment.etc.bad.text;
        expectedError = {
          type = "ThrownError";
          msg = "is not an entity record";
        };
      }
    );
  };
}
