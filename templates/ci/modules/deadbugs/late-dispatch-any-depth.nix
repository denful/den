# A policy registered two entity levels above the scope that binds its
# arguments still fires there. Late dispatch offered only the parent's and the
# sibling's registrations, so an environment's `{ host, user }` policy never
# reached the users of its hosts.
{ denTest, lib, ... }:
let
  # flake → environment → host → user.
  envTopology =
    { den, ... }:
    {
      den.schema.environment.isEntity = true;
      den.schema.host.parent = "environment";
      den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
      den.aspects.tux.homeManager.home.stateVersion = "25.11";
      den.policies.to-env = _: [
        (den.lib.policy.resolve.to "environment" { environment.name = "prod"; })
      ];
      den.policies.env-to-hosts =
        { environment, ... }:
        [
          (den.lib.policy.resolve.to "host" { host = den.hosts.x86_64-linux.igloo; })
          (den.lib.policy.instantiate den.hosts.x86_64-linux.igloo)
        ];
      den.schema.flake.includes = [ den.policies.to-env ];
      den.schema.flake-system.excludes = [
        den.policies.system-to-os-outputs
        den.policies.system-to-hm-outputs
      ];
    };
  envPolicyCell =
    policy:
    denTest (
      { den, config, ... }:
      let
        igloo = config.flake.nixosConfigurations.igloo.config;
      in
      {
        imports = [ (envTopology { inherit den; }) ];
        den.policies.env-pol = policy den;
        den.schema.environment.includes = [
          den.policies.env-to-hosts
          den.policies.env-pol
        ];
        expr = {
          home = igloo.home-manager.users.tux.home.sessionVariables.ENVPOL or "<missing>";
          host = igloo.environment.etc.env-tux.text or "<missing>";
        };
        expected = {
          home = "igloo";
          host = "igloo";
        };
      }
    );
  envPolicyBody = host: user: {
    nixos.environment.etc."env-${user.name}".text = host.name;
    homeManager.home.sessionVariables.ENVPOL = host.name;
  };

  # envTopology plus a guest of igloo: cuda (a host-like entity, parent kind
  # host, with two users) binds `host` to itself. The guest is a bounded entity
  # (#694): its subtree's content stays at its own scopes, never in igloo's
  # config, so the cells read it there (guestValues).
  guestTopology =
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
    in
    {
      imports = [ (envTopology { inherit den; }) ];
      den.hosts.x86_64-linux.cuda = {
        intoAttr = [ ];
        users = {
          pingu = { };
          gentoo = { };
        };
      };
      den.schema.guest-kind = {
        isEntity = true;
        parent = "host";
        # The walks are bounded either way (#694); `isolated` tells the loss
        # check this guest never merged into igloo on main, either.
        isolated = true;
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
    };
  # Values `f` reads from the attrset modules collected for `class` at the
  # guest's tree scopes (guest-kind under an environment), from the pipeline
  # state, before any host instantiates them.
  guestValues =
    lib: den: class: f:
    let
      st = (den.lib.aspects.resolveWithState class (den.lib.resolveEntity "flake" { })).state;
      imports = (st.scopedClassImports or (_: { })) null;
      scopes = builtins.filter (sid: lib.hasInfix "guest-kind=" sid && lib.hasInfix "environment=" sid) (
        builtins.attrNames imports
      );
    in
    lib.unique (
      lib.concatMap (
        sid:
        lib.concatMap (e: lib.optionals (builtins.isAttrs e.module) (f e.module)) (
          imports.${sid}.${class} or [ ]
        )
      ) scopes
    );
  # igloo's config with the guest's etc entries beside it: the view the cells
  # assert on, wherever the content now lands.
  withGuest = lib: den: config: {
    environment.etc =
      config.flake.nixosConfigurations.igloo.config.environment.etc
      // lib.genAttrs (guestValues lib den "nixos" (m: builtins.attrNames (m.environment.etc or { }))) (
        _: { }
      );
  };
  etcNames =
    lib: prefix: cfg:
    builtins.filter (lib.hasPrefix prefix) (builtins.attrNames cfg.environment.etc);

  # A policy carried to tux by a late include (registered at tux after its own
  # dispatch, so only the fresh-registration re-pass runs it), igloo with two
  # users. Reads the variable it sets in tux's home-manager.
  lateCarriedCell =
    var: mkPol:
    denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.hosts.x86_64-linux.igloo.users.pingu.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.pingu.homeManager.home.stateVersion = "25.11";
        den.policies.carrier =
          { host, user, ... }:
          lib.optional (user.name == "tux") (
            den.lib.policy.include {
              name = "carried";
              includes = [ (den.lib.policy.mkPolicy "carried-${var}" (mkPol den)) ];
            }
          );
        den.schema.host.includes = [ den.policies.carrier ];
        expr =
          config.flake.nixosConfigurations.igloo.config.home-manager.users.tux.home.sessionVariables.${var}
            or "<missing>";
        expected = "x";
      }
    );
  # Environments prod and dev; igloo in prod; igloo's guest cuda (two users,
  # so the guest fans out) rebinds `environment` to dev. Each environment
  # registers its own policy through its aspect.
  rebindFixture =
    {
      den,
      lib,
      config,
      withIdHash,
      devFirst,
      guestIdHash ? true,
    }:
    let
      env =
        name:
        {
          inherit name;
          aspect = den.aspects."${name}-env";
        }
        // lib.optionalAttrs withIdHash { id_hash = "environment:${name}"; };
      prod = env "prod";
      dev = env "dev";
      # An ad-hoc guest record may carry no id_hash.
      guest =
        (
          if guestIdHash then
            config.den.hosts.x86_64-linux.cuda
          else
            builtins.removeAttrs config.den.hosts.x86_64-linux.cuda [ "id_hash" ]
        )
        // {
          intoAttr = [ ];
        };
      envPolicy =
        prefix:
        {
          environment,
          host,
          user,
          ...
        }:
        [
          (den.lib.policy.include {
            # Named per user: anonymous content from sibling scopes shares one
            # identity and merges once into the host.
            name = "${prefix}-${user.name}";
            nixos.environment.etc."${prefix}-${environment.name}-${host.name}-${user.name}".text = "x";
          })
        ];
    in
    {
      den.schema.environment.isEntity = true;
      den.schema.host.parent = "environment";
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.hosts.x86_64-linux.cuda = {
        intoAttr = [ ];
        users = {
          pingu = { };
          gentoo = { };
        };
      };
      den.policies.to-env = _: [
        (den.lib.policy.resolve.to "environment" {
          environment = if devFirst then dev else prod;
        })
        (den.lib.policy.resolve.to "environment" {
          environment = if devFirst then prod else dev;
        })
      ];
      den.policies.env-to-hosts =
        { environment, ... }:
        lib.optionals (environment.name == "prod") [
          (den.lib.policy.resolve.to "host" { host = den.hosts.x86_64-linux.igloo; })
          (den.lib.policy.instantiate den.hosts.x86_64-linux.igloo)
        ];
      den.schema.flake.includes = [ den.policies.to-env ];
      den.schema.flake-system.excludes = [
        den.policies.system-to-os-outputs
        den.policies.system-to-hm-outputs
      ];
      den.schema.environment.includes = [ den.policies.env-to-hosts ];
      den.schema.guest-kind = {
        isEntity = true;
        parent = "host";
        # The walks are bounded either way (#694); `isolated` tells the loss
        # check this guest never merged into igloo on main, either.
        isolated = true;
        includes = [ den.policies.host-to-users ];
      };
      den.policies.to-guest =
        { host, ... }:
        lib.optionals (host.name == "igloo") [
          (den.lib.policy.resolve.to "guest-kind" {
            guest-kind = guest;
            host = guest;
            environment = dev;
          })
        ];
      den.schema.host.includes = [ den.policies.to-guest ];
      den.policies.prod-pol = envPolicy "pp";
      den.policies.dev-pol = envPolicy "dp";
      den.aspects.prod-env.includes = [ den.policies.prod-pol ];

      den.aspects.dev-env.includes = [ den.policies.dev-pol ];
    };
  # The env-policy entries in igloo's config.
  envEtc =
    lib: cfg:
    builtins.filter (n: lib.hasPrefix "pp-" n || lib.hasPrefix "dp-" n) (
      builtins.attrNames cfg.environment.etc
    );
  # dev's rule opts the guest's user gentoo into host-aspects; the projection
  # carries cuda's homeManager content to gentoo. With dev declared after
  # prod, the rule only runs in the re-pass.
  # A policy registered at the guest (a tree ancestor of its users) and at dev
  # (their bound environment) fires once per user in either order. Provides
  # are not deduplicated, so the list counts firings.
  bothRegisteredCell =
    devFirst:
    denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [
          (rebindFixture {
            inherit
              den
              lib
              config
              devFirst
              ;
            withIdHash = true;
          })
        ];
        den.policies.both-pol =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              module.boot.kernelModules = [ "both-${user.name}" ];
            })
          ];
        den.aspects.cuda.includes = [ den.policies.both-pol ];
        den.aspects.dev-env.includes = [ den.policies.both-pol ];
        # Every provide the pipeline registered, read before any downstream
        # dedup: one per firing.
        expr =
          let
            st = (den.lib.aspects.resolveWithState "nixos" (den.lib.resolveEntity "flake" { })).state;
          in
          lib.sort lib.lessThan (
            lib.concatMap (p: p.module.boot.kernelModules or [ ]) (
              lib.concatLists (builtins.attrValues ((st.scopedProvides or (_: { })) null))
            )
          );
        expected = [
          "both-gentoo"
          "both-pingu"
        ];
      }
    );
  projectionCell =
    devFirst:
    denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [
          (rebindFixture {
            inherit
              den
              lib
              config
              devFirst
              ;
            withIdHash = true;
          })
        ];
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.hosts.x86_64-linux.cuda.users.gentoo.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.aspects.gentoo.homeManager.home.stateVersion = "25.11";
        den.aspects.cuda.homeManager.home.sessionVariables.PROJ = "cuda";
        den.policies.dev-pol = lib.mkForce (
          { environment, user, ... }:
          lib.optional (user.name == "gentoo") (
            den.lib.policy.include {
              name = "dev-proj-${user.name}";
              includes = [ den.batteries.host-aspects ];
            }
          )
        );
        # gentoo is the guest's user: its home lives at the guest's scope.
        expr = guestValues lib den "homeManager" (
          m: lib.optional (m ? home.sessionVariables.PROJ) m.home.sessionVariables.PROJ
        );
        expected = [ "cuda" ];
      }
    );
  rebindCell = withIdHash: devFirst: rebindCellWith { inherit withIdHash devFirst; };
  rebindCellWith =
    {
      withIdHash ? true,
      devFirst,
      guestIdHash ? true,
    }:
    denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [
          (rebindFixture {
            inherit
              den
              lib
              config
              withIdHash
              devFirst
              guestIdHash
              ;
          })
        ];
        expr = envEtc lib (withGuest lib den config);
        expected = [
          # The guest binds dev: dev's rule fires for its users, prod's does not.
          "dp-dev-cuda-gentoo"
          "dp-dev-cuda-pingu"
          # An ordinary host: prod's rule, as before.
          "pp-prod-igloo-tux"
        ];
      }
    );
in
{
  flake.tests.deadbugs.late-dispatch-any-depth = {

    test-environment-host-user-policy-reaches-user = envPolicyCell (
      den: { host, user, ... }: [ (den.lib.policy.include (envPolicyBody host user)) ]
    );

    # Two environments without id_hash, told apart by value: each registers
    # its own `{ host, user }` policy through its aspect, and each policy
    # reaches only the users of its own environment's host.
    test-environments-without-id-hash-keep-their-own-rules = denTest (
      { den, config, ... }:
      let
        etc =
          h:
          builtins.filter (n: lib.hasPrefix "pp-" n || lib.hasPrefix "dp-" n) (
            builtins.attrNames config.flake.nixosConfigurations.${h}.config.environment.etc
          );
        envPol =
          prefix:
          { host, user, ... }:
          [
            (den.lib.policy.include {
              name = "${prefix}-${user.name}";
              nixos.environment.etc."${prefix}-${host.name}-${user.name}".text = "x";
            })
          ];
      in
      {
        den.schema.environment.isEntity = true;
        den.schema.host.parent = "environment";
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.pingu = { };
        den.policies.to-env = _: [
          (den.lib.policy.resolve.to "environment" {
            environment = {
              name = "prod";
              aspect = den.aspects.prod-env;
            };
          })
          (den.lib.policy.resolve.to "environment" {
            environment = {
              name = "dev";
              aspect = den.aspects.dev-env;
            };
          })
        ];
        den.policies.env-to-hosts =
          { environment, ... }:
          let
            h =
              if environment.name == "prod" then den.hosts.x86_64-linux.igloo else den.hosts.x86_64-linux.iceberg;
          in
          [
            (den.lib.policy.resolve.to "host" { host = h; })
            (den.lib.policy.instantiate h)
          ];
        den.schema.flake.includes = [ den.policies.to-env ];
        den.schema.environment.includes = [ den.policies.env-to-hosts ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];
        den.policies.prod-pol = envPol "pp";
        den.policies.dev-pol = envPol "dp";
        den.aspects.prod-env.includes = [ den.policies.prod-pol ];
        den.aspects.dev-env.includes = [ den.policies.dev-pol ];
        expr = {
          igloo = etc "igloo";
          iceberg = etc "iceberg";
        };
        expected = {
          igloo = [ "pp-igloo-tux" ];
          iceberg = [ "dp-iceberg-pingu" ];
        };
      }
    );

    test-environment-policy-declaring-environment-reaches-user = envPolicyCell (
      den:
      {
        environment,
        host,
        user,
        ...
      }:
      [ (den.lib.policy.include (envPolicyBody host user)) ]
    );

    # A policy that binds only its own layer fires once, at the environment:
    # its content stays there and never reaches igloo, as it would if it fired
    # again at the host or the user. A guard only: the kind filter already keeps
    # an `{ environment }` policy off host and user scopes.
    test-environment-only-policy-fires-once = denTest (
      { den, config, ... }:
      let
        igloo = config.flake.nixosConfigurations.igloo.config;
      in
      {
        imports = [ (envTopology { inherit den; }) ];
        den.policies.env-own =
          { environment, ... }: [ (den.lib.policy.include { nixos.boot.kernelModules = [ "env-own" ]; }) ];
        den.schema.environment.includes = [
          den.policies.env-to-hosts
          den.policies.env-own
        ];
        expr = builtins.filter (m: m == "env-own") igloo.boot.kernelModules;
        expected = [ ];
      }
    );

    # A policy with no required entity argument passes the kind filter at every
    # scope. Registered at the environment, it fires there and must not fire
    # again at the host or the user. A guard: both the ancestor fired set and
    # the instance rule keep it from firing again.
    test-environment-no-arg-policy-fires-once = denTest (
      { den, config, ... }:
      let
        igloo = config.flake.nixosConfigurations.igloo.config;
      in
      {
        imports = [ (envTopology { inherit den; }) ];
        den.policies.env-noarg = _: [
          (den.lib.policy.include { nixos.boot.kernelModules = [ "env-noarg" ]; })
        ];
        den.schema.environment.includes = [
          den.policies.env-to-hosts
          den.policies.env-noarg
        ];
        expr = builtins.filter (m: m == "env-noarg") igloo.boot.kernelModules;
        expected = [ ];
      }
    );

    # A host with a single user: the late pass runs for one child too, so a
    # policy registered two levels above still reaches that user. Before, a
    # resolve with one schema child never ran the late pass.
    test-single-child-gets-late-pass = denTest (
      { den, config, ... }:
      let
        igloo = config.flake.nixosConfigurations.igloo.config;
      in
      {
        imports = [ (envTopology { inherit den; }) ];
        # No home-manager: igloo resolves a single schema child (tux).
        den.hosts.x86_64-linux.igloo.users.tux.classes = lib.mkForce [ "user" ];
        den.policies.env-single =
          { host, user, ... }:
          [ (den.lib.policy.include { nixos.environment.etc."single-${user.name}".text = host.name; }) ];
        den.schema.environment.includes = [
          den.policies.env-to-hosts
          den.policies.env-single
        ];
        expr = igloo.environment.etc.single-tux.text or "<missing>";
        expected = "igloo";
      }
    );

    # Guests are their own hosts: igloo's `{ host, user }` policy does not fire
    # at its guest's users, whose `host` is the guest. Offering every ancestor
    # reached them through igloo's registry two levels up.
    test-host-policy-stays-out-of-guest = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [ (guestTopology { inherit den lib config; }) ];
        den.policies.igloo-pol =
          { host, user, ... }:
          [
            (den.lib.policy.include {
              name = "ig-${user.name}";
              nixos.environment.etc."ig-${host.name}-${user.name}".text = "x";
            })
          ];
        # Registered on the host kind; the guest is a guest-kind, so only igloo
        # registers it.
        den.schema.host.includes = [ den.policies.igloo-pol ];
        den.schema.environment.includes = [ den.policies.env-to-hosts ];
        expr = etcNames lib "ig-" (withGuest lib den config);
        expected = [ "ig-igloo-tux" ];
      }
    );

    # An instance is the bound arguments' values, not their names: the
    # environment's policy, empty at igloo (`host = igloo`), is a new instance
    # at the guest (`host = cuda`) and fires there. A names-only check took it
    # for igloo's instance.
    test-rebound-argument-is-a-new-instance = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [ (guestTopology { inherit den lib config; }) ];
        den.policies.env-guest =
          {
            host ? null,
            ...
          }@ctx:
          lib.optional ((host.name or "") == "cuda" && !(ctx ? user)) (
            den.lib.policy.include { nixos.environment.etc.ev-cuda.text = "x"; }
          );
        den.schema.environment.includes = [
          den.policies.env-to-hosts
          den.policies.env-guest
        ];
        expr = etcNames lib "ev-" (withGuest lib den config);
        expected = [ "ev-cuda" ];
      }
    );

    # The fired set covers every ancestor: a policy that fired at the
    # environment does not fire again at tux, two levels down, even with more
    # of its optional arguments bound there. With the fired set taken from the
    # parent only (igloo, where it did not fire), it fired again at tux.
    test-fired-at-grandparent-not-again = denTest (
      { den, config, ... }:
      {
        imports = [ (envTopology { inherit den; }) ];
        den.policies.env-opt =
          {
            environment ? null,
            host ? null,
            user ? null,
            ...
          }:
          [ (den.lib.policy.include { nixos.boot.kernelModules = [ "env-opt" ]; }) ];
        den.schema.environment.includes = [
          den.policies.env-to-hosts
          den.policies.env-opt
        ];
        expr = builtins.filter (
          m: m == "env-opt"
        ) config.flake.nixosConfigurations.igloo.config.boot.kernelModules;
        expected = [ ];
      }
    );

    # The instance rule: a policy that returned nothing at the environment
    # (so it is not in the fired set) has the same instance at igloo and does
    # not fire again there.
    test-same-instance-does-not-fire-again = denTest (
      { den, config, ... }:
      {
        imports = [ (envTopology { inherit den; }) ];
        den.policies.env-branch =
          ctx:
          lib.optional (ctx ? host) (den.lib.policy.include { nixos.boot.kernelModules = [ "env-branch" ]; });
        den.schema.environment.includes = [
          den.policies.env-to-hosts
          den.policies.env-branch
        ];
        expr = builtins.filter (
          m: m == "env-branch"
        ) config.flake.nixosConfigurations.igloo.config.boot.kernelModules;
        expected = [ ];
      }
    );

    # A non-entity kind pushed onto the host's scope (the microvm template's
    # microvm-host) shares that scope: its policy runs there once, not again
    # when the host kind is dispatched at the same scope. Kind is not part of
    # an instance. The include is named per kind so a second firing shows.
    test-pushed-kind-policy-fires-once-at-host-scope = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.to-pushed = { host, ... }: [ (den.lib.policy.resolve.to "pushed" { inherit host; }) ];
        den.policies.pushed-pol =
          { host, ... }@ctx:
          [
            (den.lib.policy.include {
              name = "pushed-${ctx.__entityKind}";
              nixos.boot.kernelModules = [ "pushed-${ctx.__entityKind}" ];
            })
          ];
        den.schema.host.includes = [ den.policies.to-pushed ];
        den.schema.pushed.includes = [ den.policies.pushed-pol ];
        expr = builtins.filter (lib.hasPrefix "pushed-") igloo.boot.kernelModules;
        expected = [ "pushed-pushed" ];
      }
    );

    # A lone child's late pass keeps the fresh-registration re-pass: a
    # `to-hosts` reached through `<host>.provides.<user>` registers at the user
    # after the late include, and still lands.
    test-lone-child-late-include-provides-lands = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.provides.to-hosts.nixos.environment.etc.late-provided.text = "x";
        den.aspects.igloo.provides.tux.includes = [ den.aspects.feat ];
        expr = igloo.environment.etc ? late-provided;
        expected = true;
      }
    );

    # A policy applies where the scope's binding for its registrant's kind is
    # that registrant: a guest rebinding `environment` gets dev's rules, not
    # the tree environment's. Records matched by id_hash.
    test-guest-rebinding-environment-by-id-hash = rebindCell true true;

    # The same with ad-hoc records that carry no id_hash: matched by value.
    test-guest-rebinding-environment-by-value = rebindCell false true;

    # The bound environment resolves after the guest's subtree: the guest's
    # users are re-passed once dev resolves, so the order does not decide.
    test-guest-rebinding-environment-resolved-later = rebindCell true false;

    # A spawn reached through re-passed content runs in the re-pass: dev's
    # rule includes a complex forward (a spawned sub-pipeline) at the guest's
    # users, and dev resolves after the guest. Its forwarded content lands.
    test-both-registered-fires-once-bound-first = bothRegisteredCell true;
    test-both-registered-fires-once-bound-later = bothRegisteredCell false;
    test-projection-from-bound-rule = projectionCell true;
    test-projection-from-repassed-rule = projectionCell false;

    # id_hash is parent-blind: tux@igloo and tux@iceberg share one. A policy
    # registered at tux@iceberg (through iceberg's provides, resolved first)
    # stays there; the
    # bound search skips the kinds a scope's tree already binds.
    test-same-named-users-keep-their-own-rules = denTest (
      { den, config, ... }:
      let
        etc =
          h:
          builtins.filter (lib.hasPrefix "pa-") (
            builtins.attrNames config.flake.nixosConfigurations.${h}.config.environment.etc
          );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.policies.pa =
          { host, user, ... }:
          [
            (den.lib.policy.include {
              name = "pa-${host.name}-${user.name}";
              nixos.environment.etc."pa-${host.name}-${user.name}".text = "x";
            })
          ];
        den.aspects.iceberg.provides.tux.includes = [ den.policies.pa ];
        expr = {
          igloo = etc "igloo";
          iceberg = etc "iceberg";
        };
        expected = {
          igloo = [ ];
          iceberg = [ "pa-iceberg-tux" ];
        };
      }
    );

    # One host resolved under two environments has two scopes with one
    # id_hash. A policy registered only at igloo@dev stays out of
    # igloo@prod's users: their tree already binds `host`. A registration
    # applies to its own registering scope, not to every scope of the same
    # entity (§11a N1, ruled per scope).
    test-host-in-two-environments-keeps-scope-rules = denTest (
      { den, igloo, ... }:
      {
        den.schema.environment.isEntity = true;
        den.schema.host.parent = "environment";
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.to-env = _: [
          # dev first, so igloo@dev exists when igloo@prod's users pass.
          (den.lib.policy.resolve.to "environment" { environment.name = "dev"; })
          (den.lib.policy.resolve.to "environment" { environment.name = "prod"; })
        ];
        den.policies.env-to-hosts =
          { environment, ... }:
          [ (den.lib.policy.resolve.to "host" { host = den.hosts.x86_64-linux.igloo; }) ]
          ++ lib.optional (environment.name == "prod") (
            den.lib.policy.instantiate den.hosts.x86_64-linux.igloo
          );
        den.schema.flake.includes = [ den.policies.to-env ];
        den.schema.environment.includes = [ den.policies.env-to-hosts ];
        den.schema.flake-system.excludes = [
          den.policies.system-to-os-outputs
          den.policies.system-to-hm-outputs
        ];
        den.policies.pa =
          {
            environment,
            host,
            user,
            ...
          }:
          [
            (den.lib.policy.include {
              name = "pa-${environment.name}-${user.name}";
              nixos.environment.etc."pa-${environment.name}-${host.name}-${user.name}".text = "x";
            })
          ];
        den.policies.dev-registers =
          { environment, host, ... }:
          lib.optional (environment.name == "dev") (
            den.lib.policy.include {
              name = "dev-registers";
              includes = [ den.policies.pa ];
            }
          );
        den.schema.host.includes = [ den.policies.dev-registers ];
        expr = builtins.filter (lib.hasPrefix "pa-prod-") (builtins.attrNames igloo.environment.etc);
        expected = [ ];
      }
    );

    # A guest's ad-hoc record without an id_hash binds `host` to itself; igloo
    # carries one. They are different entities (different names), so it is
    # not an error, and the guest still gets dev's rules in either order.
    test-adhoc-guest-without-id-hash-dev-first = rebindCellWith {
      devFirst = true;
      guestIdHash = false;
    };
    test-adhoc-guest-without-id-hash-prod-first = rebindCellWith {
      devFirst = false;
      guestIdHash = false;
    };

    # A binding compared with a same-named record of the same kind where only
    # one side has an id_hash cannot be decided, so it is an error, not no
    # rules.
    test-binding-mixed-id-hash-is-an-error = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        imports = [
          (rebindFixture {
            inherit den lib config;
            withIdHash = true;
            devFirst = true;
          })
        ];
        den.policies.to-guest = lib.mkForce (
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to "guest-kind" {
              guest-kind = config.den.hosts.x86_64-linux.cuda // {
                intoAttr = [ ];
              };
              host = config.den.hosts.x86_64-linux.cuda // {
                intoAttr = [ ];
              };
              environment = {
                name = "dev";
                aspect = den.aspects.dev-env;
              };
            })
          ]
        );
        expr = envEtc lib (withGuest lib den config);
        expectedError = {
          type = "ThrownError";
          msg = "only one carries an id_hash";
        };
      }
    );

    # Records without id_hash that differ only in function values (rebuilt
    # with fresh lambdas) cannot be compared, so that is an error too.
    test-binding-differing-only-in-functions-is-an-error = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      let
        devWith = f: {
          name = "dev";
          aspect = den.aspects.dev-env;
          inherit f;
        };
      in
      {
        imports = [
          (rebindFixture {
            inherit den lib config;
            withIdHash = false;
            devFirst = true;
          })
        ];
        den.policies.to-env = lib.mkForce (_: [
          (den.lib.policy.resolve.to "environment" { environment = devWith (_: "dev"); })
          (den.lib.policy.resolve.to "environment" {
            environment = {
              name = "prod";
              aspect = den.aspects.prod-env;
            };
          })
        ]);
        den.policies.to-guest = lib.mkForce (
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to "guest-kind" {
              guest-kind = config.den.hosts.x86_64-linux.cuda // {
                intoAttr = [ ];
              };
              host = config.den.hosts.x86_64-linux.cuda // {
                intoAttr = [ ];
              };
              environment = devWith (_: "dev");
            })
          ]
        );
        expr = envEtc lib (withGuest lib den config);
        expectedError = {
          type = "ThrownError";
          msg = "differ only in function values";
        };
      }
    );

    test-repassed-content-spawns = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
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
        imports = [
          (rebindFixture {
            inherit den lib config;
            withIdHash = true;
            devFirst = false;
          })
        ];
        den.policies.dev-pol = lib.mkForce (
          {
            environment,
            host,
            user,
            ...
          }:
          [
            (den.lib.policy.include {
              name = "dev-fwd-${user.name}";
              includes = [ forwarded ];
              nix.settings.allowed-users = [ "dev-${user.name}" ];
            })
          ]
        );
        expr = lib.sort lib.lessThan (
          builtins.filter (lib.hasPrefix "dev-") (
            config.flake.nixosConfigurations.igloo.config.nix.settings.allowed-users
            # The guest is never instantiated, so its forward into nixos is
            # not applied; the content is read where it lands, in the nix
            # class at the guest's users.
            ++ guestValues lib den "nix" (m: m.settings.allowed-users or [ ])
          )
        );
        expected = [
          "dev-gentoo"
          "dev-pingu"
        ];
      }
    );

    # A policy registered at tux by a late include fires there, though no
    # ancestor registers it: whether an ancestor could have dispatched it is
    # only asked of ancestors at or below the farthest one registering it.
    test-late-carried-no-arg-policy-fires = lateCarriedCell "LATENOARG" (
      den: _: [ (den.lib.policy.include { homeManager.home.sessionVariables.LATENOARG = "x"; }) ]
    );

    test-late-carried-system-policy-fires = lateCarriedCell "LATESYS" (
      den:
      { system, ... }:
      [
        (den.lib.policy.include {
          homeManager.home.sessionVariables.LATESYS = if system == "x86_64-linux" then "x" else system;
        })
      ]
    );
  };
}
