# Issue #742: a collectSubtree route read the frozen phase-1 per-scope map, so
# content a complex forward wrote into its subtree (home-manager's per-user
# output, or any guarded / adapter forward) never reached the delivery target.
{ denTest, ... }:
let
  guestFixture =
    {
      den,
      lib,
      guestIncludes ? [ ],
    }:
    let
      guestEntity = {
        name = "guest";
        system = "x86_64-linux";
        class = "nixos";
        intoAttr = [ ];
        users = { };
        aspect = den.aspects.guest-aspect;
      };
      deliverPolicy = den.lib.policy.mkPolicy "deliver-iso" (
        { ... }@args:
        lib.optionals (!(args ? user) && !(args ? home)) [
          (den.lib.policy.route {
            fromClass = "nixos";
            intoClass = "nixos";
            collectSubtree = true;
            appendToParent = true;
            # A delivered guest is its own module system; the adapter a complex
            # forward emits must evaluate against the guest config, not igloo's.
            reinstantiate = true;
            path = [
              "microvm"
              "vms"
              "guest"
              "config"
            ];
          })
        ]
      );
      microvmSlot =
        { lib, ... }:
        {
          options.microvm.vms = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.config = lib.mkOption {
                  type = lib.types.submoduleWith {
                    modules = [
                      { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
                    ];
                  };
                  default = { };
                };
              }
            );
            default = { };
          };
        };
    in
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.schema.iso-kind = {
        isEntity = true;
        parent = "host";
        isolated = true;
        includes = guestIncludes;
      };
      den.policies.resolve-iso-child =
        { host, ... }:
        lib.optionals (host.name == "igloo") [
          (den.lib.policy.resolve.to.withIncludes "iso-kind" [ deliverPolicy ] {
            iso-kind = guestEntity;
          })
        ];
      den.schema.host.includes = [ den.policies.resolve-iso-child ];
      den.aspects.igloo.nixos.imports = [ microvmSlot ];
    };
in
{
  flake.tests.deadbugs.issue-742-subtree-route-complex-forward = {

    test-guarded-forward-reaches-guest-delivery = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        imports = [ (guestFixture { inherit den lib; }) ];
        den.classes.guest-extra.description = "guest-only forwarded class";
        den.aspects.guest-aspect = {
          nixos.boot.kernelModules = [ "guest-own" ];
          guest-extra.enable = true;
          # The guard makes this a complex forward (synthesize edge).
          includes = [
            (den._.forward {
              each = [ "guest" ];
              fromClass = _: "guest-extra";
              intoClass = _: "nixos";
              intoPath = _: [
                "services"
                "forwarded"
              ];
              fromAspect = _: den.aspects.guest-aspect;
              guard = _: true;
            })
          ];
        };

        expr = {
          own = lib.elem "guest-own" igloo.microvm.vms.guest.config.boot.kernelModules;
          forwarded = igloo.microvm.vms.guest.config.services.forwarded.enable or "<dropped>";
          leaked = igloo ? services.forwarded;
        };
        expected = {
          own = true;
          forwarded = true;
          leaked = false;
        };
      }
    );

    # The static resolve (den.lib.aspects.resolveImports) never materialized
    # policy.spawn requests, so host-aspects projected nothing onto the user.
    test-static-resolve-materializes-host-aspects = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        imports = den.lib.aspects.resolveImports "probe-cls" (
          den.lib.resolveEntity "host" { host = config.den.hosts.x86_64-linux.igloo; }
        );
        evaluated = lib.evalModules {
          modules = imports.imports ++ [
            { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
          ];
        };
      in
      {
        den.classes.probe-cls.description = "user class read by a static resolve";
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "probe-cls" ];
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        den.aspects.tux.probe-cls.own = "tux";
        # Only the host-aspects projection binds `user` while walking igloo's tree.
        den.aspects.igloo.includes = [
          # #694: the host-rooted flat resolve reads tux's class content only
          # where the host accepts tux.
          den.batteries.user-aspects
          (
            { user, ... }:
            {
              probe-cls.projected = user.name;
            }
          )
        ];

        expr = {
          own = evaluated.config.own or "<missing>";
          projected = evaluated.config.projected or "<missing>";
        };
        expected = {
          own = "tux";
          projected = "tux";
        };
      }
    );

    # The issue's own repro: the user is the resolve root, with its host in
    # context, so the spawn has no parent scope unless the static resolve seeds it.
    test-static-resolve-of-root-user-projects-host-aspects = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        imports = den.lib.aspects.resolveImports "probe-cls" (
          den.lib.resolveEntity "user" {
            host = config.den.hosts.x86_64-linux.igloo;
            user = config.den.hosts.x86_64-linux.igloo.users.tux;
          }
        );
        evaluated = lib.evalModules {
          modules = imports.imports ++ [
            { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
          ];
        };
      in
      {
        den.classes.probe-cls.description = "user class read by a static resolve";
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "probe-cls" ];
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        den.aspects.tux.probe-cls.own = "tux";
        # Only the host-aspects projection binds `user` while walking igloo's tree.
        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              probe-cls.projected = user.name;
            }
          )
        ];

        expr = {
          own = evaluated.config.own or "<missing>";
          projected = evaluated.config.projected or "<missing>";
        };
        expected = {
          own = "tux";
          projected = "tux";
        };
      }
    );
  };
}
