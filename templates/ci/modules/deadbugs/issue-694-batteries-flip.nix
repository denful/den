# Issue #694, PR 2 cells that go green with the flip (PR 3): what the
# batteries deliver once the merge is bounded at each entity.
{ denTest, ... }:
let
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

in
{
  flake.tests.deadbugs.issue-694-batteries-flip = {

    # Included on a user, user-aspects accepts nothing: the user's own nixos
    # stays in the user.
    test-user-side-placement-inert = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.nixos.environment.etc.tux-own.text = "tux";
        expr = igloo.environment.etc ? tux-own;
        expected = false;
      }
    );

    # `users` filters which users' output the host accepts: tux's arrives,
    # pingu's does not.
    test-user-list-filters = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.igloo.includes = [ (den.batteries.user-aspects { users = [ "tux" ]; }) ];
        den.aspects.tux.nixos.environment.etc.tux-own.text = "tux";
        den.aspects.pingu.nixos.environment.etc.pingu-own.text = "pingu";
        expr = igloo.environment.etc ? tux-own;
        expected = true;
      }
    );

    # A user's own `os` comes through.
    test-os-comes-through = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.os.environment.etc.tux-os.text = "tux";
        expr = igloo.environment.etc.tux-os.text or "<missing>";
        expected = "tux";
      }
    );

    # Two identical includes accept once: the user's unkeyed content lands once.
    test-identical-includes-once = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [
          den.batteries.user-aspects
          den.batteries.user-aspects
        ];
        den.aspects.tux.nixos.boot.kernelModules = [ "tux-mod" ];
        expr = builtins.length (builtins.filter (m: m == "tux-mod") igloo.boot.kernelModules);
        expected = 1;
      }
    );

    # A user-scope provide (no receiver) comes through user-aspects: the
    # accepted user's scope is not a boundary, so its folded bucket merges.
    test-user-scope-provide-comes-through = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.policies.tux-local =
          { user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              module.environment.etc."local-${user.userName}".text = user.userName;
            })
          ];
        den.schema.user.includes = [ den.policies.tux-local ];
        expr = igloo.environment.etc.local-tux.text or "<missing>";
        expected = "tux";
      }
    );

    # A guest nested under an accepting host inherits the host's acceptance key
    # in its ctx, but the key names the host's id_hash, so the guest's users are
    # not accepted into the guest, and the guest's delivery carries none of
    # their own nixos.
    test-guest-under-accepting-host-receives-nothing = denTest (
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
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.pingu.nixos.environment.etc.pingu-own.text = "pingu";
        expr = igloo.microvm.vms.cuda.config.config.environment.etc ? pingu-own;
        expected = false;
      }
    );

    # The guest itself is not lifted under an accepting host: its own nixos
    # reaches igloo only through its delivery, never igloo's own config.
    test-guest-under-accepting-host-stays-bounded = denTest (
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
        # Not isolated, so only the entity boundary can keep the guest out.
        den.schema.guest-kind.isolated = lib.mkForce false;
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        expr = {
          igloo = builtins.elem "cuda-own" igloo.boot.kernelModules;
          guest = builtins.elem "cuda-own" igloo.microvm.vms.cuda.config.config.boot.kernelModules;
        };
        expected = {
          igloo = false;
          guest = true;
        };
      }
    );

    # Guests are their own hosts (§11a): igloo's policy and aspect function
    # apply to igloo's users only; a schema-registered policy also applies in
    # the guest, which registered it itself (host = guest).
    test-registrant-guest-rows = denTest (
      {
        den,
        lib,
        config,
        inputs,
        igloo,
        ...
      }:
      let
        mk =
          prefix:
          { host, user, ... }:
          {
            nixos.environment.etc."${prefix}-${host.name}-${user.name}".text = "x";
          };
        pick = etc: builtins.attrNames (lib.filterAttrs (n: _: builtins.match "[pas]-.*" n != null) etc);
      in
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
        den.policies.reg-host = { host, user, ... }@ctx: [ (den.lib.policy.include (mk "p" ctx)) ];
        den.policies.reg-schema = { host, user, ... }@ctx: [ (den.lib.policy.include (mk "s" ctx)) ];
        den.aspects.igloo.includes = [
          den.policies.reg-host
          (mk "a")
        ];
        den.schema.host.includes = [ den.policies.reg-schema ];
        expr = {
          igloo = pick igloo.environment.etc;
          guest = pick igloo.microvm.vms.cuda.config.config.environment.etc;
        };
        expected = {
          igloo = [
            "a-igloo-tux"
            "p-igloo-tux"
            "s-igloo-tux"
          ];
          guest = [ "s-cuda-pingu" ];
        };
      }
    );
  };
}
