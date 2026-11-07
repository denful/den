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
  # host, with two users) binds `host` to itself. Not isolated, so on main's
  # semantics the guest's subtree merges into igloo and its users' content
  # is readable in igloo's config.
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
in
{
  flake.tests.deadbugs.late-dispatch-any-depth = {

    test-environment-host-user-policy-reaches-user = envPolicyCell (
      den: { host, user, ... }: [ (den.lib.policy.include (envPolicyBody host user)) ]
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
        expr = etcNames lib "ig-" config.flake.nixosConfigurations.igloo.config;
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
        expr = etcNames lib "ev-" config.flake.nixosConfigurations.igloo.config;
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
