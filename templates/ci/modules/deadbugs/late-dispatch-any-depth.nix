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

    # The new path's re-fire risk: a policy with no required entity argument
    # passes the kind filter at every scope. Registered at the environment, it
    # fires there and must not fire again at the host or the user. With the
    # fired set taken from the parent only, it fired again at tux and its
    # content reached igloo through tux.
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
  };
}
