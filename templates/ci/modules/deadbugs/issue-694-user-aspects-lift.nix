# Issue #694: user-aspects lifts the entity boundary for the users a host
# accepts, so everything an accepted user emits for the host reaches it as on
# main. Each cell has a twin without the battery, where the bounded merge keeps
# the content in the user.
{ denTest, lib, ... }:
let
  listSlot =
    name:
    { lib, ... }:
    {
      options.${name}.items = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

  # A custom class the user authors, routed into the host class at the user's
  # scope (no receiver).
  customClassRoute =
    { den, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.classes.extra.description = "a user-authored custom class";
      den.policies.extra-to-host =
        { host, user, ... }:
        [
          (den.lib.policy.route {
            fromClass = "extra";
            intoClass = host.class;
            path = [ "combo-box" ];
          })
        ];
      den.schema.user.includes = [ den.policies.extra-to-host ];
      den.aspects.igloo.nixos.imports = [ (listSlot "combo-box") ];
      den.aspects.tux.extra.items = [ "from-tux" ];
    };

  # A forward from a custom class the user authors into the host class.
  customClassForward =
    { den, ... }:
    let
      forwarded =
        { class, aspect-chain }:
        den.provides.forward {
          each = [ "nixos" ];
          fromClass = _: "nix";
          intoClass = lib.id;
          intoPath = _: [ "nix" ];
          fromAspect = _: lib.head aspect-chain;
        };
    in
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.aspects.tux = {
        includes = [ forwarded ];
        nix.settings.allowed-users = [ "tux" ];
      };
    };
in
{
  flake.tests.deadbugs.issue-694-user-aspects-lift = {

    test-custom-class-route-reaches-host = denTest (
      { den, igloo, ... }:
      {
        imports = [ (customClassRoute { inherit den; }) ];
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        expr = igloo.combo-box.items;
        expected = [ "from-tux" ];
      }
    );

    test-custom-class-route-bounded-without = denTest (
      { den, igloo, ... }:
      {
        imports = [ (customClassRoute { inherit den; }) ];
        expr = igloo.combo-box.items;
        expected = [ ];
      }
    );

    test-forward-reaches-host = denTest (
      { den, igloo, ... }:
      {
        imports = [ (customClassForward { inherit den; }) ];
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        expr = builtins.elem "tux" igloo.nix.settings.allowed-users;
        expected = true;
      }
    );

    test-forward-bounded-without = denTest (
      { den, igloo, ... }:
      {
        imports = [ (customClassForward { inherit den; }) ];
        expr = builtins.elem "tux" igloo.nix.settings.allowed-users;
        expected = false;
      }
    );

    # Accepted on igloo, not on iceberg: the same user's content reaches igloo
    # and stays bounded at iceberg.
    test-accepted-on-one-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.nixos.environment.etc.tux-own.text = "tux";
        expr = igloo.environment.etc.tux-own.text or "<missing>";
        expected = "tux";
      }
    );

    test-not-accepted-on-other-host = denTest (
      { den, iceberg, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.nixos.environment.etc.tux-own.text = "tux";
        expr = iceberg.environment.etc ? tux-own;
        expected = false;
      }
    );

    # The deprecated `isolated` alias still withholds the user, as on main.
    test-isolated-user-stays-isolated = denTest (
      { den, igloo, ... }:
      {
        den.schema.user.isolated = true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.nixos.environment.etc.tux-own.text = "tux";
        expr = igloo.environment.etc ? tux-own;
        expected = false;
      }
    );

    # An accepted user's content lands once. The os-user-class-fwd hook and
    # mutual-provider stand down for it; their modules are keyed, so a second
    # copy would dedup too, and this cell pins the outcome only.
    test-accepted-user-lands-once = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.provides.to-hosts.nixos.boot.kernelModules = [ "to-hosts-mod" ];
        den.aspects.tux.os.boot.kernelModules = [ "os-mod" ];
        expr = lib.sort (a: b: a < b) (
          builtins.filter (
            m:
            builtins.elem m [
              "to-hosts-mod"
              "os-mod"
            ]
          ) igloo.boot.kernelModules
        );
        expected = [
          "os-mod"
          "to-hosts-mod"
        ];
      }
    );

    # The same for a home-manager user, whose os-user-class-fwd hook is live.
    test-accepted-hm-user-hook-once = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.tux.user.extraGroups = [ "probe-grp" ];
        expr = builtins.filter (g: g == "probe-grp") igloo.users.users.tux.extraGroups;
        expected = [ "probe-grp" ];
      }
    );

    # The D cells' twins (internal.ctx-transformation, the issue-742 static
    # resolve, issue-694-batteries take-exactly carry the battery): without it,
    # a host-rooted flat resolve of a custom class is bounded at the host.
    test-flat-custom-class-bounded-without = denTest (
      { den, funnyNames, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [
          (den.lib.take.exactly (
            { host, user }:
            {
              funny.names = [ "${host.name}/${user.name}" ];
            }
          ))
        ];
        expr = funnyNames (den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; });
        expected = [ ];
      }
    );

    test-static-resolve-bounded-without = denTest (
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
        # The host-aspects projection emits at tux's scope too.
        expected = {
          own = "<missing>";
          projected = "<missing>";
        };
      }
    );

    # An entity resolved per user (as class-module-partial-apply does) is lifted
    # only for a user the host accepts: igloo accepts pingu, not tux, so the
    # entity bound to tux stays bounded.
    test-per-user-entity-of-unaccepted-user-bounded = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.policies.host-to-per-user-probe =
          { host, ... }:
          map (user: den.lib.policy.resolve.to "per-user-probe" { inherit user; }) (
            builtins.attrValues host.users
          );
        den.schema.per-user-probe.includes = [
          (
            { user, ... }:
            {
              nixos.environment.etc."probe-${user.name}".text = user.name;
            }
          )
        ];
        den.schema.host.includes = [
          (den.batteries.user-aspects { users = [ "pingu" ]; })
          den.policies.host-to-per-user-probe
        ];
        expr = {
          pingu = igloo.environment.etc ? probe-pingu;
          tux = igloo.environment.etc ? probe-tux;
        };
        expected = {
          pingu = true;
          tux = false;
        };
      }
    );
    # With no user accepted, the per-user entities stay bounded and the loss
    # check names them.
    test-per-user-entity-unaccepted-loss-reported = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.policies.host-to-per-user-probe =
          { host, ... }:
          map (user: den.lib.policy.resolve.to "per-user-probe" { inherit user; }) (
            builtins.attrValues host.users
          );
        den.schema.per-user-probe.includes = [
          (
            { user, ... }:
            {
              nixos.environment.etc."probe-${user.name}".text = user.name;
            }
          )
        ];
        den.schema.host.includes = [
          den.policies.host-to-per-user-probe
        ];
        expr = igloo.environment.etc ? probe-tux;
        expected = false;
      }
    );
  };
}
