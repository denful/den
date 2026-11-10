# Issue #694's transition defaults, until den.lib.migrations.removalDate. The
# suite runs with them off (test-support/end-state.nix); these cells turn them
# back on, as every config outside the suite has them.
#
# By default user-aspects and mutual-provider are on every entity kind, so
# nothing changes from before #694, and a host warns once for the host-class
# content that reaches it only through them. The warning is `lib.warn`, which a
# cell cannot read, so checkLost also hands the list it warns with to the
# host's `_module.args.denTransitionDefaultLost`; `warned` reads it.
{ denTest, lib, ... }:
let
  transition = {
    den.internal.transitionDefaults = lib.mkForce true;
  };
  # A placement-aware aspect: host-class content for a host placement, a home
  # part for a user placement.
  steam = {
    nixos.environment.etc.steam-host.text = "host";
    homeManager.home.sessionVariables.STEAM = "user";
  };
  homeUser = name: {
    den.hosts.x86_64-linux.igloo.users.${name}.classes = [ "homeManager" ];
    den.aspects.${name}.homeManager.home.stateVersion = "25.11";
  };
  hmOf = config: name: config.flake.nixosConfigurations.igloo.config.home-manager.users.${name};
  # What the host's transition-default warning lists, as aspect identities.
  warned =
    config:
    map (e: e.aspect) (
      config.flake.nixosConfigurations.igloo._module.args.denTransitionDefaultLost or [ ]
    );
  hostCtx =
    config: name:
    config.den.hosts.x86_64-linux.${name}.__resolveResult.scopeContexts."host=${name}" or { };
  keysWith =
    prefix: ctx:
    builtins.filter (k: builtins.substring 0 (builtins.stringLength prefix) k == prefix) (
      builtins.attrNames ctx
    );
  # One cell per #694 form: by default it still reaches the host, and the
  # warning lists it.
  formCell =
    extra: form: expectedAspect:
    denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [
          transition
          extra
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.probe.text = "x";
        den.policies.tux-to-hosts =
          { host, user, ... }: [ (den.lib.policy.include { nixos.environment.etc.probe.text = "x"; }) ];
        den.aspects.tux = form den;
        expr = {
          delivered = igloo.environment.etc ? probe;
          warned = builtins.elem expectedAspect (warned config);
        };
        expected = {
          delivered = true;
          warned = true;
        };
      }
    );
  form = formCell { };
in
{
  flake.tests.deadbugs.issue-694-migration = {

    # The issue's table, each form listed by the warning, and two more forms
    # that also reach the host only through a default: a user policy's bare
    # include, and `provides.to-hosts`.
    test-form-own-nixos-warned = form (_: { nixos.environment.etc.probe.text = "x"; }) "tux";
    test-form-include-warned = form (den: { includes = [ den.aspects.feat ]; }) "feat";
    test-form-function-warned = form (_: {
      includes = [
        (
          { user, ... }:
          {
            nixos.environment.etc.probe.text = "x";
          }
        )
      ];
    }) "tux/<anon>:0";
    test-form-function-module-warned = form (_: {
      nixos =
        { pkgs, ... }:
        {
          environment.etc.probe.text = "x";
        };
    }) "tux";
    test-form-os-warned = form (_: { os.environment.etc.probe.text = "x"; }) "os@tux";
    test-form-homemanager-classes-warned = formCell {
      den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
      den.default.homeManager.home.stateVersion = "25.11";
    } (_: { nixos.environment.etc.probe.text = "x"; }) "tux";
    test-form-policy-warned = form (den: {
      includes = [ den.policies.tux-to-hosts ];
    }) "<policy:tux-to-hosts>[1]";
    test-form-to-hosts-warned = form (_: {
      provides.to-hosts.nixos.environment.etc.probe.text = "x";
    }) "tux/to-hosts";

    # An import-tree root is listed without its store hash.
    test-import-tree-root-warned-readable = denTest (
      { den, config, ... }:
      let
        root = builtins.path {
          path = ../../non-dendritic/collide/a;
          name = "source";
        };
      in
      {
        imports = [ transition ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ (den.batteries.import-tree "${root}/disko") ];
        expr = {
          listed = builtins.elem "den/batteries/import-tree/import-tree(source/disko)" (warned config);
          hashed = builtins.any (lib.hasInfix builtins.storeDir) (warned config);
        };
        expected = {
          listed = true;
          hashed = false;
        };
      }
    );

    # Acknowledged, the warning lists nothing.
    test-acknowledged-warns-nothing = denTest (
      { den, config, ... }:
      {
        imports = [ transition ];
        den.migrations.user-host-content.acknowledged = true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos.environment.etc.probe.text = "x";
        expr = warned config;
        expected = [ ];
      }
    );

    # Guard: the removal date every message prints is a real date.
    test-removal-date-is-a-date = denTest (
      { den, ... }:
      {
        expr = builtins.match "[0-9]{4}-[0-9]{2}-[0-9]{2}" den.lib.migrations.removalDate != null;
        expected = true;
      }
    );

    # By default a user's own nixos still reaches the host, as does what it
    # provides to its hosts; the warning lists both.
    test-default-changes-nothing = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [ transition ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux = {
          nixos.environment.etc.own.text = "user";
          provides.to-hosts.nixos.environment.etc.provided.text = "user";
        };
        expr = {
          own = igloo.environment.etc.own.text or "<missing>";
          provided = igloo.environment.etc.provided.text or "<missing>";
          warned = warned config;
        };
        expected = {
          own = "user";
          provided = "user";
          warned = [
            "tux"
            "tux/to-hosts"
          ];
        };
      }
    );

    # The acknowledgement turns both defaults off: neither the user's own
    # nixos nor what it provides reaches the host.
    test-acknowledgement-turns-both-off = denTest (
      { den, igloo, ... }:
      {
        imports = [ transition ];
        den.migrations.user-host-content.acknowledged = true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux = {
          nixos.environment.etc.own.text = "user";
          provides.to-hosts.nixos.environment.etc.provided.text = "user";
        };
        expr = {
          own = igloo.environment.etc ? own;
          provided = igloo.environment.etc ? provided;
        };
        expected = {
          own = false;
          provided = false;
        };
      }
    );

    # Explicit batteries: the content arrives through them, so no warning.
    # Both host policies fire for each battery (default and explicit are two
    # policies, one publishing each acceptance key), but each delivery is one,
    # so the content lands once.
    test-explicit-include-no-warning = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [ transition ];
        den.schema.host.includes = [
          den.batteries.user-aspects
          den.batteries.mutual-provider
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux = {
          nixos.boot.kernelModules = [ "own" ];
          provides.to-hosts.nixos.boot.kernelModules = [ "provided" ];
        };
        expr = {
          modules = builtins.filter (m: m == "own" || m == "provided") igloo.boot.kernelModules;
          warned = warned config;
        };
        expected = {
          modules = [
            "own"
            "provided"
          ];
          warned = [ ];
        };
      }
    );

    # Excluding user-aspects stops its default: the user's own nixos stays
    # with it, while mutual-provider's default still delivers what it
    # provides, which the warning lists.
    test-excluding-user-aspects-stops-its-default = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [ transition ];
        den.schema.host.excludes = [ den.batteries.user-aspects ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux = {
          nixos.environment.etc.own.text = "user";
          provides.to-hosts.nixos.environment.etc.provided.text = "user";
        };
        expr = {
          own = igloo.environment.etc ? own;
          provided = igloo.environment.etc.provided.text or "<missing>";
          warned = warned config;
        };
        expected = {
          own = false;
          provided = "user";
          warned = [ "tux/to-hosts" ];
        };
      }
    );

    # Excluding mutual-provider stops its default: no acceptance key, and what
    # a user provides doesn't reach the host through it.
    test-excluding-mutual-provider-stops-its-default = denTest (
      { den, config, ... }:
      {
        imports = [ transition ];
        den.schema.host.excludes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = keysWith "den-mutual-provider/" (hostCtx config "igloo");
        expected = [ ];
      }
    );

    # Content mutual-provider's default delivers that the host also has
    # without it is not listed.
    test-default-delivery-already-on-host-not-listed = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [ transition ];
        den.schema.host.excludes = [ den.batteries.user-aspects ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.feat.text = "x";
        den.aspects.igloo.includes = [ den.aspects.feat ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.feat ];
        expr = {
          feat = igloo.environment.etc ? feat;
          warned = warned config;
        };
        expected = {
          feat = true;
          warned = [ ];
        };
      }
    );

    # The steam-shaped dual aspect placed on a user: by default unchanged
    # (the host part reaches the host), with a warning.
    test-dual-aspect-by-default = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [
          transition
          (homeUser "tux")
        ];
        den.aspects.steam = steam;
        den.aspects.tux.includes = [ den.aspects.steam ];
        expr = {
          host = igloo.environment.etc.steam-host.text or "<missing>";
          home = (hmOf config "tux").home.sessionVariables.STEAM or "<missing>";
          warned = warned config;
        };
        expected = {
          host = "host";
          home = "user";
          warned = [ "steam" ];
        };
      }
    );

    # The same, acknowledged: the host part stays with the user, the home
    # part applies.
    test-dual-aspect-acknowledged = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [
          transition
          (homeUser "tux")
        ];
        den.migrations.user-host-content.acknowledged = true;
        den.aspects.steam = steam;
        den.aspects.tux.includes = [ den.aspects.steam ];
        expr = {
          host = igloo.environment.etc ? steam-host;
          home = (hmOf config "tux").home.sessionVariables.STEAM or "<missing>";
        };
        expected = {
          host = false;
          home = "user";
        };
      }
    );

    # Host-placed: no warning.
    test-host-placed-no-warning = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [
          transition
          (homeUser "tux")
        ];
        den.aspects.steam = steam;
        den.aspects.igloo.includes = [ den.aspects.steam ];
        expr = {
          host = igloo.environment.etc.steam-host.text;
          warned = warned config;
        };
        expected = {
          host = "host";
          warned = [ ];
        };
      }
    );

    # A home-manager user's os-user-class-fwd hook content, accepted only by
    # default, reaches the host through the user's bucket; its own delivery
    # stands down, and is the end state's, so the warning doesn't list it.
    test-os-user-class-fwd-hook-not-listed = denTest (
      {
        den,
        igloo,
        config,
        ...
      }:
      {
        imports = [
          transition
          (homeUser "tux")
        ];
        den.aspects.os-user-class-fwd.nixos.environment.etc.hook.text = "hook";
        expr = {
          hook = igloo.environment.etc.hook.text or "<missing>";
          warned = builtins.elem "os-user-class-fwd" (warned config);
        };
        expected = {
          hook = "hook";
          warned = false;
        };
      }
    );

    # A standalone home binds a host it doesn't belong to: no transition
    # default acts there, so it publishes no default key. (It binds `user`
    # too, so the defaults' user guard already keeps them out; the `home`
    # guard states it.)
    test-standalone-home-publishes-no-default-key = denTest (
      { den, config, ... }:
      let
        ctxs = config.den.homes.x86_64-linux."tux@igloo".__resolveResult.scopeContexts or { };
        defaultKeys = lib.concatMap (
          ctx: builtins.filter (lib.hasInfix "/default/") (builtins.attrNames ctx)
        ) (builtins.attrValues ctxs);
      in
      {
        imports = [ transition ];
        den.hosts.x86_64-linux.igloo = { };
        den.homes.x86_64-linux."tux@igloo" = { };
        expr = {
          resolved = ctxs != { };
          inherit defaultKeys;
        };
        expected = {
          resolved = true;
          defaultKeys = [ ];
        };
      }
    );

    # A nested kind with its own class that doesn't copy the host's includes
    # (a guest that is its own host) still gets the transition default: its
    # scope publishes user-aspects' default acceptance for itself.
    test-guest-kind-gets-the-default = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        guest = config.den.hosts.x86_64-linux.cuda // {
          intoAttr = [ ];
        };
        st = (den.lib.aspects.resolveWithState "nixos" (den.lib.resolveEntity "flake" { })).state;
        ctxs = (st.scopeContexts or (_: { })) null;
        guestScope = lib.findFirst (
          sid: lib.hasInfix "guest-kind=cuda" sid && !(lib.hasInfix "user=" sid)
        ) null (builtins.attrNames ctxs);
      in
      {
        imports = [ transition ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.cuda = {
          intoAttr = [ ];
          users.pingu = { };
        };
        den.schema.guest-kind = {
          isEntity = true;
          parent = "host";
          includes = [ den.policies.host-to-users ];
        };
        den.policies.to-guest =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to "guest-kind" {
              guest-kind = guest;
              host = guest;
            })
          ];
        den.schema.host.includes = [ den.policies.to-guest ];
        expr = (ctxs.${guestScope} or { }) ? ${den.lib.acceptance.userAspectsDefaultKey guest};
        expected = true;
      }
    );
  };
}
