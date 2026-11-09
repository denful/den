# Issue #694, PR 4 (spec §12, §11a O2): a policy effect names its target, and a
# receiver decides what it admits.
#
#   1. `include.at <entity> <aspect>`: the head names its relatum; elsewhere it
#      is a delivery, resolved for the receiver's class.
#   2. Relatum-scoped excludes, matched by origin: excluding an aspect excludes
#      the policies originating from it, for instances where the entity is a
#      relatum.
#   3. `admits.deny` and `admits = { default = "deny"; allow = [ … ]; }`.
#   4. `policyEnforcement` and `den.lib.policy.strict`.
#   5. Stable origins for den's channels (the held excludability cells).
#   6. Stable identity for anonymous aspects.
#   7. The transition defaults are excluded with their batteries by origin.
{ denTest, lib, ... }:
let
  hmUser = {
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
    den.aspects.tux.homeManager.home.stateVersion = "25.11";
  };
  twoUsers = {
    den.hosts.x86_64-linux.igloo.users = {
      tux = { };
      pingu = { };
    };
  };
  # A host-registered { host, user } policy placing content on the user.
  hostPolicy = den: {
    den.policies.hp =
      { host, user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.HP = "x"; }) ];
    den.aspects.igloo.includes = [ den.policies.hp ];
  };
  # The finished pipeline state for igloo, which the unmatched-exclude
  # diagnostic reads (internal/unmatched-policy-exclude.nix).
  hostState =
    den:
    let
      fxLib = den.lib.aspects.fx;
      hostRoot = den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; };
    in
    (fxLib.pipeline.fxFullResolve {
      class = "nixos";
      ctx = fxLib.aspect.ctxFromHandlers (hostRoot.__scopeHandlers or { });
      self = den.lib.aspects.normalizeRoot hostRoot;
    }).state;
  # A user policy forwarding a user class into the host, naming the host as
  # receiver (the shape of makeHomeEnv's user arm).
  forwardToIgloo = forwardToIglooWith (f: f);
  forwardToIglooWith = shape: den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.aspects.tux.policies.fw =
      { host, user, ... }:
      [
        (den.lib.policy.include (
          shape (
            den.batteries.forward {
              each = [ true ];
              fromClass = _: "smug";
              intoClass = _: host.class;
              intoPath = _: [ ];
              fromAspect = _: den.lib.resolveEntity "user" { inherit host user; };
              receiver = host;
            }
          )
        ))
      ];
    den.aspects.tux.includes = [ den.aspects.tux.policies.fw ];
    den.aspects.tux.smug.environment.etc.fw.text = "x";
  };
  forgedToHosts =
    { den, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.schema.host.includes = [ den.batteries.mutual-provider ];
      den.aspects.tux.provides.to-hosts.nixos.environment.etc.real.text = "x";
      # Named as mutual-provider's per-user cross policy registers.
      den.policies."tux/to-hosts" =
        { host, user, ... }:
        [
          (den.lib.policy.provide {
            class = "nixos";
            receiver = host;
            module.environment.etc.forged.text = "x";
          })
        ];
      den.aspects.tux.includes = [ den.policies."tux/to-hosts" ];
    };
  # A user policy routing the user's own nixos bucket to its host.
  authorRoute =
    extra:
    { den, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.aspects.tux.nixos.environment.etc.own.text = "x";
      den.aspects.tux.policies.rt =
        { host, user, ... }:
        [
          (den.lib.policy.route (
            {
              fromClass = "nixos";
              intoClass = "nixos";
              receiver = host;
            }
            // extra
          ))
        ];
      den.aspects.tux.includes = [ den.aspects.tux.policies.rt ];
    };
  # An author's own home environment, built with den's factory.
  customHomeEnv =
    den:
    den.lib.home-env.makeHomeEnv {
      className = "smug";
      optionPath = "smug";
      getModule =
        { ... }:
        { lib, ... }:
        {
          options.smug.users = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submoduleWith {
                modules = [ { config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified; } ];
              }
            );
            default = { };
          };
        };
      forwardPathFn =
        { user, ... }:
        [
          "smug"
          "users"
          user.userName
        ];
    };
  customHomeEnvConfig = env: {
    den.schema.host.imports = [ env.hostConf ];
    den.schema.host.includes = [ env.battery ];
    den.schema.user.includes = [ env.userDetect ];
    den.classes.smug.description = "an author's home environment";
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "smug" ];
    den.aspects.tux.smug.FROM = "tux";
  };
  sameNamedOn =
    on:
    { den, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.schema.host.includes = [ den.batteries.mutual-provider ];
      den.aspects.tux.provides.to-hosts.nixos.environment.etc.real.text = "x";
      den.policies."tux/to-hosts" =
        { host, user, ... }:
        [
          (den.lib.policy.provide {
            class = "nixos";
            receiver = host;
            module.environment.etc.forged.text = "x";
          })
        ];
      imports = [ { den.aspects.${on}.includes = [ den.policies."tux/to-hosts" ]; } ];
    };
  userAspectsOnIgloo =
    { den, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.aspects.igloo.includes = [ den.batteries.user-aspects ];
      den.aspects.tux.nixos.environment.etc.ua.text = "x";
      den.aspects.tux.user.description = "tux";
    };
  hpOf = igloo: igloo.home-manager.users.tux.home.sessionVariables.HP or "<missing>";
  # A user-registered author delivery to the host.
  toIgloo = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.aspects.tux.policies.to-igloo =
      { host, user, ... }:
      [
        (den.lib.policy.provide {
          class = "nixos";
          receiver = host;
          module.environment.etc.ud.text = "x";
        })
      ];
    den.aspects.tux.includes = [ den.aspects.tux.policies.to-igloo ];
  };
in
{
  flake.tests.deadbugs.issue-694-pr4 = {

    # 1. include.at
    test-include-at-host-from-user-policy = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.policies.to-host =
          { host, user, ... }:
          [ (den.lib.policy.include.at host { nixos.environment.etc.at.text = user.name; }) ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-host ];
        expr = igloo.environment.etc.at.text or "<missing>";
        expected = "tux";
      }
    );
    test-include-at-user-from-host-policy = denTest (
      { den, igloo, ... }:
      {
        imports = [ hmUser ];
        den.policies.to-user =
          { host, user, ... }:
          [ (den.lib.policy.include.at user { homeManager.home.sessionVariables.AT = host.name; }) ];
        den.aspects.igloo.includes = [ den.policies.to-user ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.AT or "<missing>";
        expected = "igloo";
      }
    );

    # A user policy's plain include stays with the user; include.at host is
    # what moves it, and include.at the firing user is a plain include.
    test-include-at-firing-entity-is-plain-include = denTest (
      { den, igloo, ... }:
      {
        imports = [ hmUser ];
        den.aspects.tux.policies.here =
          { host, user, ... }:
          [
            (den.lib.policy.include.at user {
              nixos.environment.etc.here.text = "x";
              homeManager.home.sessionVariables.HERE = "x";
            })
          ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.here ];
        expr = {
          host = igloo.environment.etc ? here;
          home = igloo.home-manager.users.tux.home.sessionVariables.HERE or "<missing>";
        };
        expected = {
          host = false;
          home = "x";
        };
      }
    );
    # include.at host is a delivery: admits applies to it.
    test-include-at-host-is-admitted = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.policies.to-host =
          { host, user, ... }: [ (den.lib.policy.include.at host { nixos.environment.etc.at.text = "x"; }) ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-host ];
        den.aspects.igloo.admits.deny = [ den.aspects.tux.policies.to-host ];
        expr = igloo.environment.etc ? at;
        expected = false;
      }
    );

    # include.atClass gives the class to resolve for, overriding the target's:
    # a delivery to igloo resolved for homeManager carries the aspect's
    # homeManager part, not its nixos part.
    test-include-at-class-overrides-target-class = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.policies.to-host =
          { host, user, ... }:
          [
            (den.lib.policy.include.atClass "homeManager" host {
              homeManager.home.sessionVariables.HMC = "x";
              nixos.environment.etc.wrong.text = "x";
            })
          ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-host ];
        expr =
          let
            st = (den.lib.aspects.resolveWithState "nixos" (den.lib.resolveEntity "flake" { })).state;
            prov = builtins.filter (p: (p.__providePolicyName or null) == "to-host") (
              builtins.concatLists (builtins.attrValues ((st.scopedProvides or (_: { })) null))
            );
          in
          map (p: p.class) prov;
        expected = [ "homeManager" ];
      }
    );
    # A class-less target (an environment) with a given class lands; without
    # one it is an error naming the target.
    test-include-at-classless-target-with-class = denTest (
      { den, config, ... }:
      {
        den.schema.environment.isEntity = true;
        den.schema.host.parent = "environment";
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.to-env = _: [
          (den.lib.policy.resolve.to "environment" {
            environment = {
              name = "prod";
              id_hash = "environment:prod";
            };
          })
        ];
        den.policies.env-to-hosts =
          { environment, ... }:
          [
            (den.lib.policy.resolve.to "host" { host = den.hosts.x86_64-linux.igloo; })
            (den.lib.policy.instantiate den.hosts.x86_64-linux.igloo)
          ];
        den.schema.flake.includes = [ den.policies.to-env ];
        den.schema.environment.includes = [ den.policies.env-to-hosts ];
        den.policies.to-environment =
          { environment, host, ... }:
          [ (den.lib.policy.include.atClass "nixos" environment { nixos.environment.etc.env.text = "x"; }) ];
        den.aspects.igloo.includes = [ den.policies.to-environment ];
        expr =
          let
            st = (den.lib.aspects.resolveWithState "nixos" (den.lib.resolveEntity "flake" { })).state;
            prov = builtins.concatLists (builtins.attrValues ((st.scopedProvides or (_: { })) null));
          in
          builtins.any (p: (p.receiver.name or null) == "prod" && p.class == "nixos") prov;
        expected = true;
      }
    );
    test-include-at-classless-target-without-class-errors = denTest (
      { den, config, ... }:
      {
        den.schema.environment.isEntity = true;
        den.schema.host.parent = "environment";
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.to-env = _: [
          (den.lib.policy.resolve.to "environment" {
            environment = {
              name = "prod";
              id_hash = "environment:prod";
            };
          })
        ];
        den.policies.env-to-hosts =
          { environment, ... }:
          [
            (den.lib.policy.resolve.to "host" { host = den.hosts.x86_64-linux.igloo; })
            (den.lib.policy.instantiate den.hosts.x86_64-linux.igloo)
          ];
        den.schema.flake.includes = [ den.policies.to-env ];
        den.schema.environment.includes = [ den.policies.env-to-hosts ];
        den.policies.to-environment =
          { environment, host, ... }:
          [ (den.lib.policy.include.at environment { nixos.environment.etc.env.text = "x"; }) ];
        den.aspects.igloo.includes = [ den.policies.to-environment ];
        expr = config.flake.nixosConfigurations.igloo.config.environment.etc ? env;
        expectedError = {
          type = "ThrownError";
          msg = "include.at names prod, which has no class";
        };
      }
    );
    # The head names one of the instance's relata: a host the policy doesn't
    # bind is refused.
    test-include-at-non-relatum-refused = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg = { };
        den.policies.cross =
          { host, user, ... }:
          [
            (den.lib.policy.include.at den.hosts.x86_64-linux.iceberg { nixos.environment.etc.x.text = "x"; })
          ];
        den.aspects.igloo.includes = [ den.policies.cross ];
        expr = igloo.environment.etc ? x;
        expectedError = {
          type = "ThrownError";
          msg = "include.at names iceberg, which is not one of this policy instance's relata";
        };
      }
    );

    # 2 and 5. Origin-matched excludes: den's channels, host side and user side.
    test-define-user-excluded-host-side = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ den.batteries.define-user ];
        den.aspects.igloo.excludes = [ den.batteries.define-user ];
        expr = igloo.users.users.tux.isNormalUser or false;
        expected = false;
      }
    );
    test-primary-user-excluded-host-side = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ den.batteries.primary-user ];
        den.aspects.igloo.excludes = [ den.batteries.primary-user ];
        expr = builtins.elem "wheel" (igloo.users.users.tux.extraGroups or [ ]);
        expected = false;
      }
    );
    test-user-shell-excluded-host-side = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ (den.batteries.user-shell "fish") ];
        den.aspects.igloo.excludes = [ den.batteries.user-shell ];
        expr = igloo.programs.fish.enable;
        expected = false;
      }
    );
    test-user-shell-excluded-user-side = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.includes = [ (den.batteries.user-shell "fish") ];
        den.schema.user.excludes = [ den.batteries.user-shell ];
        expr = igloo.programs.fish.enable;
        expected = false;
      }
    );
    # Excluding a shared aspect on a host reaches the policies it carries for
    # that host's users (widens #613 for policies); its content is unchanged.
    test-shared-aspect-excluded-on-host-removes-its-policy = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.policies.tools-to-host =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc."tools-${user.name}".text = "x";
            })
          ];
        den.aspects.tools.includes = [ den.policies.tools-to-host ];
        den.aspects.tux.includes = [ den.aspects.tools ];
        den.aspects.igloo.excludes = [ den.aspects.tools ];
        expr = igloo.environment.etc ? tools-tux;
        expected = false;
      }
    );
    # A sub-aspect originates from its aspect: excluding `tools` on the host
    # reaches the policy of `tools.provides.extra` included directly.
    test-origin-exclude-reaches-sub-aspect = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.policies.extra-to-host =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc."extra-${user.name}".text = "x";
            })
          ];
        den.aspects.tools.provides.extra.includes = [ den.policies.extra-to-host ];
        den.aspects.tux.includes = [ den.aspects.tools.provides.extra ];
        den.aspects.igloo.excludes = [ den.aspects.tools ];
        expr = igloo.environment.etc ? extra-tux;
        expected = false;
      }
    );
    # A host-registered policy reaches users only through late dispatch: a
    # user's exclude of the aspect it came from removes it there, for that
    # user only.
    test-origin-exclude-applies-in-late-dispatch = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.policies.tools-to-host =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc."tools-${user.name}".text = "x";
            })
          ];
        den.aspects.tools.includes = [ den.policies.tools-to-host ];
        den.aspects.igloo.includes = [ den.aspects.tools ];
        den.aspects.tux.excludes = [ den.aspects.tools ];
        expr = {
          tux = igloo.environment.etc ? tools-tux;
          pingu = igloo.environment.etc ? tools-pingu;
        };
        expected = {
          tux = false;
          pingu = true;
        };
      }
    );
    # The match stops at a path boundary: excluding `tools` leaves `toolsx`
    # (a sibling whose name only starts the same) and its policy alone.
    test-origin-match-stops-at-path-boundary = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.policies.toolsx-to-host =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc."toolsx-${user.name}".text = "x";
            })
          ];
        den.aspects.toolsx.includes = [ den.policies.toolsx-to-host ];
        den.aspects.tools.nixos.environment.etc.tools.text = "x";
        den.aspects.tux.includes = [
          den.aspects.tools
          den.aspects.toolsx
        ];
        den.aspects.igloo.excludes = [ den.aspects.tools ];
        expr = igloo.environment.etc ? toolsx-tux;
        expected = true;
      }
    );
    # Only an exclude whose entity is a relatum applies: iceberg's exclude of
    # define-user leaves igloo's tux defined.
    test-origin-exclude-on-other-host-not-applied = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.tux.includes = [ den.batteries.define-user ];
        den.aspects.iceberg.excludes = [ den.batteries.define-user ];
        expr = {
          igloo = igloo.users.users.tux.isNormalUser or false;
          iceberg = iceberg.users.users.tux.isNormalUser or false;
        };
        expected = {
          igloo = true;
          iceberg = false;
        };
      }
    );
    # A policy named like the provides mechanism (`tux/to-hosts`) is its own
    # record, beside the real `provides.to-hosts` that mutual-provider
    # delivers: each is matched by its own origin, never by the shared name.
    # A same-named author policy and den's provides policy both land, in
    # either registration order: included on the user (registered beside it)
    # and on the host (merged with it by late dispatch).
    test-same-named-policy-on-user-both-land = denTest (
      { den, igloo, ... }:
      {
        imports = [ (sameNamedOn "tux") ];
        expr = {
          forged = igloo.environment.etc ? forged;
          real = igloo.environment.etc ? real;
        };
        expected = {
          forged = true;
          real = true;
        };
      }
    );
    test-same-named-policy-on-host-both-land = denTest (
      { den, igloo, ... }:
      {
        imports = [ (sameNamedOn "igloo") ];
        expr = {
          forged = igloo.environment.etc ? forged;
          real = igloo.environment.etc ? real;
        };
        expected = {
          forged = true;
          real = true;
        };
      }
    );
    # Excluding a provided aspect on the host stops its delivery, and leaves
    # the user's other provides.
    test-host-exclude-of-provided-aspect-stops-delivery = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.real.text = "x";
        den.aspects.tux.provides.igloo.nixos.environment.etc.named.text = "x";
        den.aspects.igloo.excludes = [ den.aspects.tux.provides.to-hosts ];
        expr = {
          real = igloo.environment.etc ? real;
          named = igloo.environment.etc ? named;
        };
        expected = {
          real = false;
          named = true;
        };
      }
    );
    # A policy's `exclude` effect naming a policy record removes it (the
    # shape a downstream battery uses to drop user-to-host on one host
    # class); it is matched by the policy's identity.
    test-policy-exclude-effect-removes-policy = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.tux.user.description = "tux";
        den.policies.drop-user-to-host = {
          __isPolicy = true;
          name = "drop-user-to-host";
          fn =
            { host, ... }:
            lib.optional (host.name == "igloo") (den.lib.policy.exclude den.policies.user-to-host);
        };
        den.default.includes = [ den.policies.drop-user-to-host ];
        expr = igloo.users.users.tux.description or "<absent>";
        expected = "<absent>";
      }
    );
    # O5 for den's provides policies: a provider reached twice delivers once,
    # and a parametric provider once per user.
    test-shared-provider-reached-twice-delivers-once = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.shared.provides.to-hosts.nixos.boot.kernelModules = [ "sh" ];
        den.aspects.tux.includes = [ den.aspects.shared ];
        den.schema.user.includes = [ den.aspects.shared ];
        expr = builtins.filter (m: m == "sh") igloo.boot.kernelModules;
        expected = [ "sh" ];
      }
    );
    test-parametric-provider-delivers-once-per-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.shared.provides.to-hosts =
          { host, user, ... }:
          {
            nixos.boot.kernelModules = [ "p-${user.name}" ];
          };
        den.schema.user.includes = [ den.aspects.shared ];
        expr = lib.sort (a: b: a < b) (builtins.filter (lib.hasPrefix "p-") igloo.boot.kernelModules);
        expected = [
          "p-pingu"
          "p-tux"
        ];
      }
    );
    # Control: both land.
    test-forged-to-hosts-both-land = denTest (
      { den, igloo, ... }:
      {
        imports = [ forgedToHosts ];
        expr = {
          forged = igloo.environment.etc ? forged;
          real = igloo.environment.etc ? real;
        };
        expected = {
          forged = true;
          real = true;
        };
      }
    );
    test-forged-to-hosts-name-keeps-own-origin = denTest (
      { den, igloo, ... }:
      {
        imports = [ forgedToHosts ];
        den.aspects.igloo.admits.deny = [ den.policies."tux/to-hosts" ];
        expr = {
          forged = igloo.environment.etc ? forged;
          real = igloo.environment.etc ? real;
        };
        expected = {
          forged = false;
          real = true;
        };
      }
    );
    test-forged-to-hosts-battery-deny-withholds-only-real = denTest (
      { den, igloo, ... }:
      {
        imports = [ forgedToHosts ];
        den.aspects.igloo.admits.deny = [ den.batteries.mutual-provider ];
        expr = {
          forged = igloo.environment.etc ? forged;
          real = igloo.environment.etc ? real;
        };
        expected = {
          forged = true;
          real = false;
        };
      }
    );

    # Den's own delivery fields are read only from den's deliveries: an
    # author route or provide that sets them is an ordinary delivery.
    test-author-route-stand-down-ignored = denTest (
      { den, igloo, ... }:
      {
        imports = [ (authorRoute { __standDown = true; }) ];
        expr = igloo.environment.etc ? own;
        expected = true;
      }
    );
    test-author-provide-stand-down-ignored = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.policies.sd =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc.sd.text = "x";
              __standDown = true;
            })
          ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.sd ];
        expr = igloo.environment.etc ? sd;
        expected = true;
      }
    );
    # A provenance token on an author route is ignored: the route moves the
    # whole bucket, not only what mutual-provider tagged.
    test-author-route-provenance-token-ignored = denTest (
      { den, igloo, ... }:
      {
        imports = [ (authorRoute { __fromProvenance = "tux/to-hosts"; }) ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.tagged.text = "x";
        expr = {
          own = igloo.environment.etc ? own;
          tagged = igloo.environment.etc ? tagged;
        };
        expected = {
          own = true;
          tagged = true;
        };
      }
    );
    # 3. admits
    test-admits-deny-withholds-channel = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.igloo.admits.deny = [ den.policies.user-to-host ];
        den.aspects.tux.user.description = "tux";
        den.aspects.pingu.includes = [ (den.batteries.user-shell "fish") ];
        expr = {
          description = igloo.users.users.tux.description or "<absent>";
          # Positive control: another channel still lands.
          shell = igloo.programs.fish.enable;
        };
        expected = {
          description = "<absent>";
          shell = true;
        };
      }
    );
    test-admits-default-allow-lands-author-provide = denTest (
      { den, igloo, ... }:
      {
        imports = [ (toIgloo den) ];
        expr = igloo.environment.etc ? ud;
        expected = true;
      }
    );
    test-admits-default-deny-refuses-by-name = denTest (
      { den, igloo, ... }:
      {
        imports = [ (toIgloo den) ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? ud;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    test-admits-default-deny-allow-lands = denTest (
      { den, igloo, ... }:
      {
        imports = [ (toIgloo den) ];
        den.aspects.igloo.admits = {
          default = "deny";
          allow = [ den.aspects.tux.policies.to-igloo ];
        };
        expr = igloo.environment.etc ? ud;
        expected = true;
      }
    );
    test-admits-deny-beats-allow = denTest (
      { den, igloo, ... }:
      {
        imports = [ (toIgloo den) ];
        den.schema.host.admits.allow = [ den.aspects.tux.policies.to-igloo ];
        den.aspects.igloo.admits.deny = [ den.aspects.tux.policies.to-igloo ];
        expr = igloo.environment.etc ? ud;
        expected = false;
      }
    );
    # A host can tighten a fleet default but not loosen it.
    test-admits-default-deny-not-loosened = denTest (
      { den, igloo, ... }:
      {
        imports = [ (toIgloo den) ];
        den.schema.host.admits.default = "deny";
        den.aspects.igloo.admits.default = "allow";
        expr = igloo.environment.etc ? ud;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    # Den's channels land under default-deny.
    test-admits-default-deny-keeps-channels = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.aspects.igloo.admits.default = "deny";
        den.aspects.tux.user.description = "tux";
        expr = igloo.users.users.tux.description;
        expected = "tux";
      }
    );

    # Den's home environments are its channels, by record: home-manager lands
    # on a default-deny host.
    test-admits-default-deny-keeps-home-manager = denTest (
      { den, igloo, ... }:
      {
        imports = [ hmUser ];
        den.aspects.igloo.admits.default = "deny";
        den.aspects.tux.homeManager.home.sessionVariables.HM = "x";
        expr = igloo.home-manager.users.tux.home.sessionVariables.HM or "<missing>";
        expected = "x";
      }
    );
    # The channel list can't be extended by config: a definition at den's key
    # has no effect.
    test-admits-channel-list-not-writable = denTest (
      { den, igloo, ... }:
      {
        imports = [ (toIgloo den) ];
        den.internal.channelPolicies.maid = [ den.aspects.tux.policies.to-igloo ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? ud;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    test-admits-channel-list-not-writable-registry-policy = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.mine =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc.mine.text = "x";
            })
          ];
        den.aspects.tux.includes = [ den.policies.mine ];
        den.internal.channelPolicies.maid = [ den.policies.mine ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? mine;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    # An environment an author builds with den's makeHomeEnv is not one of
    # den's channels: refused on a default-deny host unless allowed.
    test-admits-default-deny-refuses-custom-home-env = denTest (
      { den, igloo, ... }:
      let
        env = customHomeEnv den;
      in
      {
        imports = [ (customHomeEnvConfig env) ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.smug.users.tux.FROM or "<missing>";
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    test-admits-allows-custom-home-env = denTest (
      { den, igloo, ... }:
      let
        env = customHomeEnv den;
      in
      {
        imports = [ (customHomeEnvConfig env) ];
        den.aspects.igloo.admits = {
          default = "deny";
          allow = env.battery.includes ++ env.userDetect.includes;
        };
        expr = igloo.smug.users.tux.FROM or "<missing>";
        expected = "tux";
      }
    );
    # The receiver's own kind decides: a user-kind deny withholds a delivery
    # to a user, and a host-kind deny doesn't apply to it.
    test-admits-receiver-kind-layer = denTest (
      { den, igloo, ... }:
      let
        toUser = name: {
          den.policies."to-${name}" =
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "homeManager";
                receiver = user;
                module.home.sessionVariables.${lib.toUpper name} = "x";
              })
            ];
          den.aspects.igloo.includes = [ den.policies."to-${name}" ];
        };
      in
      {
        imports = [
          hmUser
          (toUser "a")
          (toUser "b")
        ];
        den.schema.user.admits.deny = [ den.policies.to-a ];
        den.schema.host.admits.deny = [ den.policies.to-b ];
        expr = {
          a = igloo.home-manager.users.tux.home.sessionVariables.A or "<missing>";
          b = igloo.home-manager.users.tux.home.sessionVariables.B or "<missing>";
        };
        expected = {
          a = "<missing>";
          b = "x";
        };
      }
    );
    # A registrant's own host-class part is its content, not a delivery: it
    # lands on a default-deny host (§11a R7).
    test-admits-default-deny-keeps-registrant-part = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.hostwide =
          { host, user, ... }:
          [ (den.lib.policy.include { nixos.environment.etc."hw-${user.name}".text = "x"; }) ];
        den.aspects.igloo.includes = [ den.policies.hostwide ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? hw-tux;
        expected = true;
      }
    );
    # A delivery marked like one of den's channels isn't one: den's channels
    # are known by definition site.
    test-admits-default-deny-refuses-forged-channel-marker = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.policies.to-igloo =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc.ud.text = "x";
              __denChannel = true;
            })
          ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-igloo ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? ud;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    # The registrant's part is told apart by construction, not by a field on
    # the delivery: an author provide carrying `__registrantPart` is refused.
    # A same-named author policy on the host displaces den's provides policy
    # to a qualified registry key; the denial still names it as written.
    test-admits-denial-names-displaced-policy-as-written = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.real.text = "x";
        den.aspects.igloo.includes = [
          (den.lib.policy.mkPolicy "tux/to-hosts" ({ host, user, ... }: [ ]))
        ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? real;
        expectedError = {
          type = "ThrownError";
          msg = "den: delivery of `tux/to-hosts` from tux denied on igloo: `admits.default = \"deny\"`; to admit it, add `den.batteries.mutual-provider` to `admits.allow`";
        };
      }
    );
    # An author's delivery names its policy as the entry to allow.
    test-admits-denial-names-source-and-policy = denTest (
      { den, igloo, ... }:
      {
        imports = [ (toIgloo den) ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? ud;
        expectedError = {
          type = "ThrownError";
          msg = "delivery of `[^`]*to-igloo` from tux denied on igloo.*add the policy `[^`]*to-igloo`";
        };
      }
    );
    test-admits-default-deny-refuses-forged-registrant-part = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.policies.to-igloo =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc.ud.text = "x";
              __registrantPart = true;
            })
          ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-igloo ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? ud;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    test-admits-deny-withholds-forged-registrant-part = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.policies.to-igloo =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc.ud.text = "x";
              __registrantPart = true;
            })
          ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-igloo ];
        den.aspects.igloo.admits.deny = [ den.aspects.tux.policies.to-igloo ];
        expr = igloo.environment.etc ? ud;
        expected = false;
      }
    );
    # mutual-provider's delivery is matched by the battery (§11a R7): allowed
    # it lands on a default-deny host, denied it is withheld, and neither
    # allowed nor default it is refused.
    test-admits-allows-mutual-provider = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.mp.text = "x";
        den.aspects.igloo.admits = {
          default = "deny";
          allow = [ den.batteries.mutual-provider ];
        };
        expr = igloo.environment.etc ? mp;
        expected = true;
      }
    );
    test-admits-denies-mutual-provider = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.mp.text = "x";
        den.aspects.tux.user.description = "tux";
        den.aspects.igloo.admits.deny = [ den.batteries.mutual-provider ];
        expr = {
          mp = igloo.environment.etc ? mp;
          # Positive control: the user's own delivery still lands.
          description = igloo.users.users.tux.description or "<absent>";
        };
        expected = {
          mp = false;
          description = "tux";
        };
      }
    );
    test-admits-default-deny-refuses-unallowed-mutual-provider = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.mp.text = "x";
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? mp;
        # The message names the source and the battery to allow.
        expectedError = {
          type = "ThrownError";
          msg = "from tux denied on igloo.*add `den.batteries.mutual-provider` to `admits.allow`";
        };
      }
    );
    # The transition default's delivery is the battery's too. user-aspects'
    # default is excluded: its lift isn't gated by admits in this release.
    test-admits-denies-mutual-provider-default = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.mp.text = "x";
        den.aspects.igloo.excludes = [ den.batteries.user-aspects ];
        den.aspects.igloo.admits.deny = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? mp;
        expected = false;
      }
    );
    # Control: without the deny, the default delivers it.
    test-admits-mutual-provider-default-delivers = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.mp.text = "x";
        den.aspects.igloo.excludes = [ den.batteries.user-aspects ];
        expr = igloo.environment.etc ? mp;
        expected = true;
      }
    );
    # A forward naming a receiver is a delivery to it (§11a R7).
    test-admits-default-deny-refuses-forward-to-receiver = denTest (
      { den, igloo, ... }:
      {
        imports = [ (forwardToIgloo den) ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? fw;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    # The forward item itself, not wrapped in `includes`.
    test-admits-default-deny-refuses-forward-item-to-receiver = denTest (
      { den, igloo, ... }:
      {
        imports = [ (forwardToIglooWith (f: builtins.head f.includes) den) ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? fw;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    # Nested deeper in the policy include.
    test-admits-default-deny-refuses-nested-forward-to-receiver = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (forwardToIglooWith (f: {
            name = "wrap";
            includes = [ f ];
          }) den)
        ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? fw;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );
    # The walk for a forward visits a named aspect once: a policy including an
    # aspect on an include cycle still evaluates.
    test-admits-forward-walk-survives-include-cycle = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.cya.includes = [ den.aspects.cyb ];
        den.aspects.cyb.includes = [ den.aspects.cya ];
        den.aspects.cyb.nixos.environment.etc.cy.text = "x";
        den.policies.pc = { host, ... }: [ (den.lib.policy.include den.aspects.cya) ];
        den.aspects.igloo.includes = [ den.policies.pc ];
        expr = igloo.environment.etc ? cy;
        expected = true;
      }
    );
    test-admits-deny-withholds-forward-to-receiver = denTest (
      { den, igloo, ... }:
      {
        imports = [ (forwardToIgloo den) ];
        den.aspects.igloo.admits.deny = [ den.aspects.tux.policies.fw ];
        expr = igloo.environment.etc ? fw;
        expected = false;
      }
    );
    # Control: allowed, the forward lands.
    test-admits-allows-forward-to-receiver = denTest (
      { den, igloo, ... }:
      {
        imports = [ (forwardToIgloo den) ];
        den.aspects.igloo.admits = {
          default = "deny";
          allow = [ den.aspects.tux.policies.fw ];
        };
        expr = igloo.environment.etc ? fw;
        expected = true;
      }
    );
    # Origins match by value: of two policies named `deliver`, only the one
    # allowed lands; the other is refused.
    test-admits-same-name-matched-by-value = denTest (
      { den, igloo, ... }:
      let
        deliver =
          file:
          den.lib.policy.mkPolicy "deliver" (
            { host, user, ... }:
            [
              (den.lib.policy.provide {
                class = "nixos";
                receiver = host;
                module.environment.etc.${file}.text = "x";
              })
            ]
          );
        allowedOne = deliver "allowed";
        otherOne = deliver "other";
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.tux.includes = [ allowedOne ];
        den.aspects.pingu.includes = [ otherOne ];
        den.aspects.igloo.admits = {
          default = "deny";
          allow = [ allowedOne ];
        };
        expr = igloo.environment.etc ? other;
        expectedError = {
          type = "ThrownError";
          msg = "denied on igloo";
        };
      }
    );

    # user-aspects' lift is not an effect admits checks, so the battery reads
    # the host's admits itself (§11a R7): on a default-deny host it must be
    # allowed by record; denied, the host accepts nothing and the content
    # stays with its users.
    test-admits-default-deny-refuses-unallowed-user-aspects = denTest (
      { den, igloo, ... }:
      {
        imports = [ userAspectsOnIgloo ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? ua;
        expectedError = {
          type = "ThrownError";
          msg = "igloo includes den.batteries.user-aspects but admits.default = \"deny\" and it is not in admits.allow";
        };
      }
    );
    test-admits-allows-user-aspects = denTest (
      { den, igloo, ... }:
      {
        imports = [ userAspectsOnIgloo ];
        den.aspects.igloo.admits = {
          default = "deny";
          allow = [ den.batteries.user-aspects ];
        };
        expr = igloo.environment.etc ? ua;
        expected = true;
      }
    );
    test-admits-denies-user-aspects = denTest (
      { den, igloo, ... }:
      {
        imports = [ userAspectsOnIgloo ];
        den.aspects.igloo.admits.deny = [ den.batteries.user-aspects ];
        expr = {
          ua = igloo.environment.etc ? ua;
          # Positive control: den's channels still deliver.
          description = igloo.users.users.tux.description or "<absent>";
        };
        expected = {
          ua = false;
          description = "tux";
        };
      }
    );
    # The schema layer gates it too.
    test-admits-schema-default-deny-refuses-unallowed-user-aspects = denTest (
      { den, igloo, ... }:
      {
        imports = [ userAspectsOnIgloo ];
        den.schema.host.admits.default = "deny";
        expr = igloo.environment.etc ? ua;
        expectedError = {
          type = "ThrownError";
          msg = "and it is not in admits.allow";
        };
      }
    );
    # The transition default is the battery: on a default-deny host it needs
    # the same allow, and with the defaults off nothing is required.
    test-admits-default-deny-refuses-user-aspects-default = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos.environment.etc.ua.text = "x";
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        den.aspects.igloo.admits.default = "deny";
        expr = igloo.environment.etc ? ua;
        expectedError = {
          type = "ThrownError";
          msg = "igloo receives users' content through the transition default \\(den.batteries.user-aspects\\) but admits.default = \"deny\"; add den.batteries.user-aspects to admits.allow, or set den.migrations.user-host-content.acknowledged = true";
        };
      }
    );
    test-admits-allows-user-aspects-default = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos.environment.etc.ua.text = "x";
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        den.aspects.igloo.admits = {
          default = "deny";
          allow = [ den.batteries.user-aspects ];
        };
        expr = igloo.environment.etc ? ua;
        expected = true;
      }
    );
    test-admits-default-deny-without-defaults-needs-nothing = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos.environment.etc.ua.text = "x";
        den.aspects.tux.user.description = "tux";
        den.aspects.igloo.admits.default = "deny";
        expr = {
          ua = igloo.environment.etc ? ua;
          description = igloo.users.users.tux.description;
        };
        expected = {
          ua = false;
          description = "tux";
        };
      }
    );

    # 4. policyEnforcement
    test-enforcement-lenient-user-excludes = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (hostPolicy den)
        ];
        den.aspects.tux.excludes = [ den.policies.hp ];
        expr = hpOf igloo;
        expected = "<missing>";
      }
    );
    test-enforcement-strict-schema-blocks-user-exclude = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (hostPolicy den)
        ];
        den.schema.host.policyEnforcement = "strict";
        den.aspects.tux.excludes = [ den.policies.hp ];
        expr = hpOf igloo;
        expected = "x";
      }
    );
    test-enforcement-policy-strict-blocks-user-exclude = denTest (
      { den, igloo, ... }:
      {
        imports = [ hmUser ];
        den.policies.hp = den.lib.policy.strict (
          { host, user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.HP = "x"; }) ]
        );
        den.aspects.igloo.includes = [ den.policies.hp ];
        den.aspects.tux.excludes = [ den.policies.hp ];
        expr = hpOf igloo;
        expected = "x";
      }
    );
    test-enforcement-lenient-overrides-policy-strict = denTest (
      { den, igloo, ... }:
      {
        imports = [ hmUser ];
        den.policies.hp = den.lib.policy.strict (
          { host, user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.HP = "x"; }) ]
        );
        den.aspects.igloo.includes = [ den.policies.hp ];
        den.aspects.igloo.policyEnforcement = "lenient";
        den.aspects.tux.excludes = [ den.policies.hp ];
        expr = hpOf igloo;
        expected = "<missing>";
      }
    );
    test-enforcement-host-lenient-cannot-loosen-fleet-strict = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (hostPolicy den)
        ];
        den.schema.host.policyEnforcement = "strict";
        den.aspects.igloo.policyEnforcement = "lenient";
        den.aspects.tux.excludes = [ den.policies.hp ];
        expr = hpOf igloo;
        expected = "x";
      }
    );
    # Under "strict" the registrant itself may still exclude.
    test-enforcement-strict-registrant-may-exclude = denTest (
      { den, igloo, ... }:
      {
        imports = [
          hmUser
          (hostPolicy den)
        ];
        den.schema.host.policyEnforcement = "strict";
        den.aspects.igloo.excludes = [ den.policies.hp ];
        expr = hpOf igloo;
        expected = "<missing>";
      }
    );
    # A policy carried by a host policy's include registers at the user but
    # inherits the host as its registrant (§11a C4): under "strict" the host
    # may exclude it, the user may not.
    test-enforcement-strict-inherited-registrant = denTest (
      { den, igloo, ... }:
      {
        imports = [ hmUser ];
        den.policies.inner =
          { host, user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.IN = "x"; }) ];
        den.policies.outer =
          { host, user, ... }:
          [
            (den.lib.policy.include {
              name = "carrier";
              includes = [ den.policies.inner ];
            })
          ];
        den.aspects.igloo.includes = [ den.policies.outer ];
        den.schema.host.policyEnforcement = "strict";
        den.aspects.igloo.excludes = [ den.policies.inner ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.IN or "<missing>";
        expected = "<missing>";
      }
    );
    # policy.strict on a two-sided registration has no effect: every relatum
    # is a registrant, so tux may still exclude it.
    test-enforcement-policy-strict-two-sided-no-effect = denTest (
      { den, igloo, ... }:
      {
        imports = [ hmUser ];
        den.policies.both = den.lib.policy.strict (
          { host, user, ... }: [ (den.lib.policy.include { homeManager.home.sessionVariables.BOTH = "x"; }) ]
        );
        den.default.includes = [ den.policies.both ];
        den.aspects.tux.excludes = [ den.policies.both ];
        expr = igloo.home-manager.users.tux.home.sessionVariables.BOTH or "<missing>";
        expected = "<missing>";
      }
    );
    # den.default is registered on both sides, so it stays user-excludable
    # under a fleet "strict".
    test-enforcement-den-default-stays-user-excludable = denTest (
      { den, igloo, ... }:
      {
        imports = [ twoUsers ];
        den.schema.host.policyEnforcement = "strict";
        den.schema.user.excludes = [ den.policies.user-to-host ];
        den.aspects.tux.user.description = "tux";
        expr = igloo.users.users.tux.description or "<absent>";
        expected = "<absent>";
      }
    );

    # Different values from one definition position (a `map`) are different
    # content: the one only the user has stays listed.
    test-anonymous-aspect-same-position-different-value-listed = denTest (
      { den, config, ... }:
      let
        mk = x: { nixos.boot.kernelModules = [ x ]; };
      in
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ (mk "on-host") ];
        den.schema.user.includes = [ (mk "user-only") ];
        expr = builtins.length (
          config.flake.nixosConfigurations.igloo._module.args.denTransitionDefaultLost or [ ]
        );
        expected = 1;
      }
    );
    # 6. An anonymous aspect included on the host and on its users is one
    # aspect, whatever its position: the host's copy covers the user's, so the
    # transition warning doesn't list it (F2: positional `<anon>:N` identities
    # differed between the two scopes).
    test-anonymous-aspect-identity-is-stable = denTest (
      { den, config, ... }:
      let
        anon = {
          nixos.boot.kernelModules = [ "anon" ];
        };
      in
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ anon ];
        den.schema.user.includes = [
          { nixos.boot.kernelModules = [ "other" ]; }
          anon
        ];
        # Only the user-only aspect is listed.
        expr = builtins.length (
          config.flake.nixosConfigurations.igloo._module.args.denTransitionDefaultLost or [ ]
        );
        expected = 1;
      }
    );

    # 7. A transition default is a policy named below its battery's path: the
    # battery's exclude reaches it by origin, and an explicit include of the
    # battery is not deduplicated against it, even on den.default beside it.
    test-default-form-not-deduplicated-against-explicit-include = denTest (
      { den, config, ... }:
      let
        ctx = config.den.hosts.x86_64-linux.igloo.__resolveResult.scopeContexts."host=igloo" or { };
        id = config.den.hosts.x86_64-linux.igloo.id_hash;
        has =
          prefix:
          builtins.any (k: builtins.substring 0 (builtins.stringLength prefix) k == prefix) (
            builtins.attrNames ctx
          );
      in
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          den.batteries.user-aspects
          den.batteries.mutual-provider
        ];
        expr = {
          userAspects = has "den-user-aspects/${id}/";
          userAspectsDefault = ctx ? "den-user-aspects/default/${id}";
          mutualProvider = ctx ? "den-mutual-provider/${id}";
          mutualProviderDefault = ctx ? "den-mutual-provider/default/${id}";
        };
        expected = {
          userAspects = true;
          userAspectsDefault = true;
          mutualProvider = true;
          mutualProviderDefault = true;
        };
      }
    );
    # An exclude in an aspect the host includes is not on den.default's
    # include tree, so the gate never meets the defaults; origin matching
    # stops both. user-aspects is an aspect exclude, mutual-provider a policy
    # exclude.
    test-off-tree-exclude-stops-default-forms = denTest (
      { den, config, ... }:
      let
        ctx = config.den.hosts.x86_64-linux.igloo.__resolveResult.scopeContexts."host=igloo" or { };
        id = config.den.hosts.x86_64-linux.igloo.id_hash;
      in
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.no-defaults.excludes = [
          den.batteries.user-aspects
          den.batteries.mutual-provider
        ];
        den.aspects.igloo.includes = [ den.aspects.no-defaults ];
        expr = {
          userAspectsDefault = ctx ? "den-user-aspects/default/${id}";
          mutualProviderDefault = ctx ? "den-mutual-provider/default/${id}";
        };
        expected = {
          userAspectsDefault = false;
          mutualProviderDefault = false;
        };
      }
    );
    # The pairing is by value, not by name: an author policy named below a
    # battery survives the battery's exclude, and the exclude, which does
    # suppress the battery, is not reported as suppressing nothing.
    test-policy-named-below-battery-survives-its-exclude = denTest (
      { den, igloo, ... }:
      let
        mine = den.lib.policy.mkPolicy "mutual-provider/mine" (
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc.mine.text = "x";
            })
          ]
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.aspects.tux.includes = [ mine ];
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = {
          mine = igloo.environment.etc ? mine;
          messages = den.lib.aspects.fx.handlers.unmatchedRawRefExcludes (hostState den);
        };
        expected = {
          mine = true;
          messages = [ ];
        };
      }
    );
    # An author policy named exactly as the battery is still its own record:
    # the battery's exclude leaves it.
    test-policy-named-as-battery-survives-its-exclude = denTest (
      { den, igloo, ... }:
      let
        mine = den.lib.policy.mkPolicy "mutual-provider" (
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc.mine.text = "x";
            })
          ]
        );
      in
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ mine ];
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc ? mine;
        expected = true;
      }
    );
    # A policy exclude names one record: excluding the policy `tools` leaves
    # the policies the aspect `tools` carries.
    test-policy-exclude-leaves-namesake-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.tools = { host, ... }: [ ];
        den.policies.tools-to-host =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              receiver = host;
              module.environment.etc.tt.text = "x";
            })
          ];
        den.aspects.tools.includes = [ den.policies.tools-to-host ];
        den.aspects.tux.includes = [ den.aspects.tools ];
        den.aspects.igloo.includes = [ den.policies.tools ];
        den.aspects.igloo.excludes = [ den.policies.tools ];
        expr = igloo.environment.etc ? tt;
        expected = true;
      }
    );
    # A battery and its default are one exclude entry: excluding the battery
    # while only its default registers suppresses the default, so it is not
    # reported as suppressing nothing.
    test-default-form-exclude-not-unmatched = denTest (
      { den, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = den.lib.aspects.fx.handlers.unmatchedRawRefExcludes (hostState den);
        expected = [ ];
      }
    );
    # The same with no user scope below the host.
    test-default-form-exclude-not-unmatched-no-users = denTest (
      { den, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = den.lib.aspects.fx.handlers.unmatchedRawRefExcludes (hostState den);
        expected = [ ];
      }
    );
    # Control: without the default, the same exclude suppresses nothing, and
    # says so once.
    test-default-form-exclude-unmatched-without-default = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = den.lib.aspects.fx.handlers.unmatchedRawRefExcludes (hostState den);
        expected = [
          "den: exclude in aspect 'igloo' names policy 'mutual-provider', which never registered in this resolution — the exclude suppresses nothing"
        ];
      }
    );
  };
}
