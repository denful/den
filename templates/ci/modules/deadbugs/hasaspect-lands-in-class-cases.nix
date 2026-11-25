# Cases beside the delivery-path oracle (hasaspect-lands-in-class.nix), each
# pinning one part of the rule with expectations read from where markers land:
# forwards, per-user nests, provides identity, content-free roles, guards and
# standalone homes.
{ denTest, lib, ... }:
let
  b = v: if v then "T" else "f";

  base =
    transition:
    { den, ... }:
    {
      den.internal.transitionDefaults = lib.mkForce transition;
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [ den._.define-user ];
      den.schema.user.classes = [ "homeManager" ];
      den.hosts.x86_64-linux.igloo.users = {
        tux = { };
        pingu = { };
      };
    };

  # Readers for `ref`: host scope (nixos) and each user's homeManager.
  readers =
    { den, ... }:
    ref: {
      den.default.includes = [
        {
          nixos =
            { host, ... }:
            {
              environment.etc."r-host".text = b (host.hasAspect (ref den));
            };
          homeManager =
            { host, user, ... }:
            {
              home.file."r-host".text = b (host.hasAspect (ref den));
              home.file."r-user".text = b (user.hasAspect (ref den));
            };
        }
      ];
    };

  answers =
    igloo:
    let
      hm = u: igloo.home-manager.users.${u}.home.file;
    in
    {
      host = lib.concatStringsSep "," (
        lib.unique (lib.splitString "\n" (igloo.environment.etc."r-host".text or "-"))
      );
      tux_host = (hm "tux")."r-host".text or "-";
      tux_user = (hm "tux")."r-user".text or "-";
      pingu_host = (hm "pingu")."r-host".text or "-";
      pingu_user = (hm "pingu")."r-user".text or "-";
    };

  # `want`: the expected answers, each paired with the marker it must track.
  check =
    igloo: want:
    let
      got = answers igloo;
    in
    builtins.attrNames (lib.filterAttrs (k: v: got.${k} != v) want);

  both = name: mk: {
    "test-end-state-${name}" = mk false;
    "test-transition-${name}" = mk true;
  };
in
{
  flake.tests.hasaspect-lands-in-class-cases =

    # A forward from a host aspect into the host's nixos at a nested path lands
    # in the host's class, so it counts (owner ruling, "forwards count").
    both "nested-forward-into-host" (
      transition:
      denTest (
        { den, igloo, ... }:
        let
          on = igloo.networking.firewall.allowedTCPPorts == [ 4242 ];
        in
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.fw))
          ];
          den.classes.firewall.description = "firewall rules";
          den.aspects.fw.firewall.allowedTCPPorts = [ 4242 ];
          den.aspects.igloo.includes = [
            den.aspects.fw
            (
              { host, ... }:
              den._.forward {
                each = [ host ];
                fromClass = _: "firewall";
                intoClass = _: "nixos";
                intoPath = _: [
                  "networking"
                  "firewall"
                ];
                fromAspect = _: den.aspects.fw;
              }
            )
          ];
          expr = {
            lands = on;
            wrong = check igloo {
              host = b on;
              tux_host = b on;
              pingu_host = b on;
            };
          };
          expected = {
            lands = true;
            wrong = [ ];
          };
        }
      )
    )

    # A user's home content nests into the host's nixos at that user's path;
    # it is the user's, so host false and that user true.
    // both "per-user-nest" (
      transition:
      denTest (
        { den, igloo, ... }:
        let
          inTux = igloo.home-manager.users.tux.home.file ? "mark-x";
        in
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.probeX))
          ];
          den.aspects.probeX.homeManager.home.file."mark-x".text = "x";
          den.aspects.tux.includes = [ den.aspects.probeX ];
          expr = {
            lands = inTux;
            wrong = check igloo {
              host = "f";
              tux_host = "f";
              pingu_host = "f";
              tux_user = b inTux;
              pingu_user = "f";
            };
          };
          expected = {
            lands = true;
            wrong = [ ];
          };
        }
      )
    )

    # `A.provides.to-users` is its own identity: A with no content of its own
    # isn't on the host or the users, while what its provide includes is where
    # it lands (owner ruling).
    // both "provides-to-users-is-not-the-aspect" (
      transition:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.A))
          ];
          den.aspects.probeX = {
            nixos.environment.etc."mark-x".text = "x";
            homeManager.home.file."mark-x".text = "x";
          };
          den.aspects.A.provides.to-users.includes = [ den.aspects.probeX ];
          den.aspects.igloo.includes = [ den.aspects.A ];
          expr = {
            x = igloo.environment.etc ? "mark-x";
            wrong = check igloo {
              host = "f";
              tux_host = "f";
              tux_user = "f";
              pingu_host = "f";
              pingu_user = "f";
            };
          };
          expected = {
            x = true;
            wrong = [ ];
          };
        }
      )
    )
    // both "provides-to-users-includes-count" (
      transition:
      denTest (
        { den, igloo, ... }:
        let
          hostX = igloo.environment.etc ? "mark-x";
          tuxX = igloo.home-manager.users.tux.home.file ? "mark-x";
        in
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.probeX))
          ];
          den.aspects.probeX = {
            nixos.environment.etc."mark-x".text = "x";
            homeManager.home.file."mark-x".text = "x";
          };
          den.aspects.A.provides.to-users.includes = [ den.aspects.probeX ];
          den.aspects.igloo.includes = [ den.aspects.A ];
          expr = {
            lands = [
              hostX
              tuxX
            ];
            wrong = check igloo {
              host = b hostX;
              tux_host = b hostX;
              tux_user = b tuxX;
            };
          };
          expected = {
            lands = [
              true
              true
            ];
            wrong = [ ];
          };
        }
      )
    )
    // both "provides-user-is-not-the-aspect" (
      transition:
      denTest (
        { den, igloo, ... }:
        let
          hostX = igloo.environment.etc ? "mark-x";
          tuxX = igloo.home-manager.users.tux.home.file ? "mark-x";
          pinguX = igloo.home-manager.users.pingu.home.file ? "mark-x";
        in
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.probeX))
          ];
          den.aspects.probeX = {
            nixos.environment.etc."mark-x".text = "x";
            homeManager.home.file."mark-x".text = "x";
          };
          den.aspects.A.provides.tux.includes = [ den.aspects.probeX ];
          den.aspects.igloo.includes = [ den.aspects.A ];
          expr = {
            lands = [
              hostX
              tuxX
              pinguX
            ];
            wrong = check igloo {
              host = b hostX;
              tux_user = b tuxX;
              pingu_user = b pinguX;
            };
          };
          expected = {
            lands = [
              true
              true
              false
            ];
            wrong = [ ];
          };
        }
      )
    )

    # A content-free role counts through what it includes: on the host when it
    # aggregates nixos content, on the user (not the host) when only homeManager.
    // both "content-free-role-nixos" (
      transition:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.roles.workstation))
          ];
          den.aspects.gui.nixos.environment.etc."mark-gui".text = "g";
          den.aspects.roles.workstation.includes = [ den.aspects.gui ];
          den.aspects.igloo.includes = [ den.aspects.roles.workstation ];
          expr = check igloo {
            host = "T";
            tux_host = "T";
          };
          expected = [ ];
        }
      )
    )
    // both "content-free-role-home-only" (
      transition:
      denTest (
        { den, igloo, ... }:
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.roles.shell))
          ];
          den.aspects.fish.homeManager.programs.fish.enable = true;
          den.aspects.roles.shell.includes = [ den.aspects.fish ];
          den.aspects.tux.includes = [ den.aspects.roles.shell ];
          expr = check igloo {
            host = "f";
            tux_host = "f";
            tux_user = "T";
            pingu_user = "f";
          };
          expected = [ ];
        }
      )
    )

    # A guard deciding an include from hasAspect (includeIf, the guard-time
    # reader, which this change leaves alone) changes what lands, with no cycle.
    // both "guard-reads-walk" (
      transition:
      denTest (
        { den, igloo, ... }:
        {
          imports = [ (base transition) ];
          den.aspects.feature.nixos.environment.etc."mark-feature".text = "f";
          den.aspects.extra.nixos.environment.etc."mark-extra".text = "e";
          den.aspects.absent.nixos = { };
          den.aspects.never.nixos.environment.etc."mark-never".text = "n";
          den.aspects.igloo.includes = [
            den.aspects.feature
            (den.lib.aspects.fx.includes.includeIf (ctx: ctx.hasAspect den.aspects.feature) [
              den.aspects.extra
            ])
            (den.lib.aspects.fx.includes.includeIf (ctx: ctx.hasAspect den.aspects.absent) [
              den.aspects.never
            ])
          ];
          expr = builtins.filter (lib.hasPrefix "mark-") (builtins.attrNames igloo.environment.etc);
          expected = [
            "mark-extra"
            "mark-feature"
          ];
        }
      )
    )

    # The registry form (`den.hosts.<s>.<h>.hasAspect`) keeps its answer, the
    # host's resolved tree with its users; the finalized query
    # (den.lib.__hasLandedAspect) gives the in-context answer, what lands.
    // both "registry-form-unchanged-finalized-query-agrees" (
      transition:
      denTest (
        { den, igloo, ... }:
        let
          h = den.hosts.x86_64-linux.igloo;
          reg = r: b (h.hasAspect r);
          late = r: b (den.lib.__hasLandedAspect { entity = h; } r);
          xLands = b (igloo.environment.etc ? "mark-x");
        in
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.probeX))
          ];
          den.aspects.probeX = {
            nixos.environment.etc."mark-x".text = "x";
            homeManager.home.file."mark-x".text = "x";
          };
          den.aspects.hostOwn.nixos.environment.etc."mark-own".text = "o";
          den.aspects.igloo.includes = [ den.aspects.hostOwn ];
          den.aspects.tux.includes = [ den.aspects.probeX ];
          expr = {
            registry = [
              (reg den.aspects.hostOwn)
              (reg den.aspects.probeX)
            ];
            late = [
              (late den.aspects.hostOwn)
              (late den.aspects.probeX)
            ];
            inContext = (answers igloo).host;
          };
          expected = {
            registry = [
              "T"
              "T"
            ];
            late = [
              "T"
              xLands
            ];
            inContext = xLands;
          };
        }
      )
    )

    # A guest host nested under igloo (an isolated entity kind with its own
    # class): its nixos content stays out of igloo's, so igloo doesn't have it.
    // both "nested-host-content-stays-in-guest" (
      transition:
      denTest (
        { den, igloo, ... }:
        let
          guestEntity = {
            name = "guest";
            system = "x86_64-linux";
            class = "nixos";
            intoAttr = [ ];
            users = { };
            aspect = den.aspects.guest-aspect;
          };
          leaks = lib.elem "guest-only-module" igloo.boot.kernelModules;
        in
        {
          imports = [
            (base transition)
            (readers { inherit den; } (d: d.aspects.guest-feature))
          ];
          den.schema.iso-kind = {
            isEntity = true;
            parent = "host";
            isolated = true;
          };
          den.policies.resolve-iso-child =
            { host, ... }:
            lib.optionals (host.name == "igloo") [
              (den.lib.policy.resolve.to "iso-kind" { iso-kind = guestEntity; })
            ];
          den.schema.host.includes = [ den.policies.resolve-iso-child ];
          den.aspects.guest-feature.nixos.boot.kernelModules = [ "guest-only-module" ];
          den.aspects.guest-aspect.includes = [ den.aspects.guest-feature ];
          expr = {
            inherit leaks;
            host = (answers igloo).host;
          };
          expected = {
            leaks = false;
            host = b leaks;
          };
        }
      )
    )

    # A custom entity kind under the flake root, read by a binding the
    # include function captures, so this pins the walk's answer: false for
    # both, though `probe` is included for acme only and its dns content
    # lands. The kind isn't instantiated, so it has no landing index entry.
    // {
      test-custom-kind = denTest (
        { den, config, ... }:
        {
          options.den.organizations = lib.mkOption {
            type = lib.types.attrsOf (
              den.lib.schema.mkInstanceType { strict = den.schema.organization.isStrict; } den.schema.organization
            );
            default = { };
          };
          config = {
            den.schema.organization.inherits = [ den.schema.conf ];
            den.organizations = {
              acme = { };
              globex = { };
            };
            den.policies.to-organizations =
              _:
              lib.mapAttrsToList (
                _: organization: den.lib.policy.resolve.to "organization" { inherit organization; }
              ) config.den.organizations;
            den.classes.dns.description = "dns records";
            den.aspects.probe.dns.records.probe = "x";
            den.schema.organization.includes = [
              (
                { organization, ... }:
                lib.optionalAttrs (organization.name == "acme") { includes = [ den.aspects.probe ]; }
              )
              (
                { organization, ... }:
                {
                  dns.records.${organization.name} = b (organization.hasAspect den.aspects.probe);
                }
              )
            ];
            den.policies.collect-dns = _: [
              (den.lib.policy.instantiate {
                name = "dns";
                class = "dns";
                instantiate =
                  { modules, ... }:
                  (lib.evalModules {
                    modules = modules ++ [
                      {
                        options.records = lib.mkOption {
                          type = lib.types.attrsOf lib.types.str;
                          default = { };
                        };
                      }
                    ];
                  }).config.records;
                intoAttr = [ "dns" ];
              })
            ];
            den.schema.flake.includes = [
              den.policies.to-organizations
              den.policies.collect-dns
            ];
            expr = config.flake.dns;
            expected = {
              acme = "f";
              globex = "f";
              probe = "x";
            };
          };
        }
      );
    }

    // {
      # A standalone home answers about its own class.
      test-standalone-home = denTest (
        { den, config, ... }:
        let
          files = config.flake.homeConfigurations.tux.config.home.file;
        in
        {
          den.default.homeManager.home.stateVersion = "25.11";
          den.default.includes = [ den._.define-user ];
          den.homes.x86_64-linux.tux = { };
          den.aspects.probeX.homeManager.home.file."mark-x".text = "x";
          den.aspects.other.nixos.environment.etc."mark-o".text = "o";
          den.aspects.tux.includes = [
            den.aspects.probeX
            den.aspects.other
            {
              homeManager =
                { home, ... }:
                {
                  home.file."r-x".text = b (home.hasAspect den.aspects.probeX);
                  home.file."r-o".text = b (home.hasAspect den.aspects.other);
                };
            }
          ];
          expr = {
            x = files."r-x".text;
            o = files."r-o".text;
          };
          expected = {
            x = "T";
            o = "f";
          };
        }
      );
    };
}
