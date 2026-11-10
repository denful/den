# Issue #694, PR 3: a user's host-class content stays in the user. Each form in
# the issue's reproduction table no longer reaches the host; each sanctioned
# channel still delivers.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-694-flip = {

    # The issue's table, one cell per form.
    test-direct-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos.environment.etc.probe.text = "from-tux";
        expr = igloo.environment.etc.probe.text or "<not delivered>";

        expected = "<not delivered>";
      }
    );

    test-included-feature-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.probe.text = "from-tux";
        den.aspects.tux.includes = [ den.aspects.feat ];
        expr = igloo.environment.etc.probe.text or "<not delivered>";

        expected = "<not delivered>";
      }
    );

    test-parametric-user-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux =
          { user, ... }:
          {
            nixos.environment.etc.probe.text = "from-${user.name}";
          };
        expr = igloo.environment.etc.probe.text or "<not delivered>";

        expected = "<not delivered>";
      }
    );

    test-function-module-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.nixos =
          { pkgs, ... }:
          {
            environment.etc.probe.text = "from-tux";
          };
        expr = igloo.environment.etc.probe.text or "<not delivered>";

        expected = "<not delivered>";
      }
    );

    test-os-class = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.os.environment.etc.probe.text = "from-tux";
        expr = igloo.environment.etc.probe.text or "<not delivered>";

        expected = "<not delivered>";
      }
    );

    test-homemanager-classes-direct-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.nixos.environment.etc.probe.text = "from-tux";
        expr = igloo.environment.etc.probe.text or "<not delivered>";

        expected = "<not delivered>";
      }
    );

    # The legacy pattern: a user-authored `policies.to-hosts` that includes
    # nixos at the user's scope. It stays with the user.
    test-user-policy-to-hosts-stays-in-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.policies.to-hosts =
          { host, user, ... }:
          [ (den.lib.policy.include { nixos.environment.etc.probe.text = "from-tux"; }) ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-hosts ];
        expr = igloo.environment.etc.probe.text or "<not delivered>";
        expected = "<not delivered>";
      }
    );

    # Records a fact for the acceptance design, fixes nothing: a policy the
    # author writes on tux and the policy `tux.provides.to-hosts` compiles to
    # register under one name, `tux/to-hosts`, so a policy's name cannot tell
    # them apart.
    test-policy-name-collides-with-provides = denTest (
      { den, config, ... }:
      let
        withPolicy =
          (den.lib.aspects.resolveWithState "nixos" (
            den.lib.resolveEntity "host" { host = config.den.hosts.x86_64-linux.igloo; }
          )).state;
        names = builtins.concatMap builtins.attrNames (
          builtins.attrValues ((withPolicy.scopedAspectPolicies or (_: { })) null)
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.policies.to-hosts = { host, user, ... }: [ ];
        den.aspects.tux.includes = [ den.aspects.tux.policies.to-hosts ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.probe.text = "tux";
        expr = builtins.length (builtins.filter (n: n == "tux/to-hosts") names);
        # Both register at the user scope under the same key; the registry
        # merges them, so one name stands for two policies.
        expected = 1;
      }
    );

    # Controls: each sanctioned channel still delivers, with den's batteries
    # on and nothing authored for the host.
    test-sanctioned-channels-deliver = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux = {
          includes = [
            den.batteries.define-user
            den.batteries.primary-user
            (den.batteries.user-shell "fish")
            (den.batteries.unfree [ "tux-unfree" ])
          ];
          user.description = "tux";
          homeManager.home.sessionVariables.FROM = "tux";
        };
        expr = {
          description = igloo.users.users.tux.description;
          normal = igloo.users.users.tux.isNormalUser;
          wheel = builtins.elem "wheel" igloo.users.users.tux.extraGroups;
          fish = igloo.programs.fish.enable;
          unfree = igloo.unfree.packages;
          hm = igloo.home-manager.users.tux.home.sessionVariables.FROM;
        };
        expected = {
          description = "tux";
          normal = true;
          wheel = true;
          fish = true;
          unfree = [ "tux-unfree" ];
          hm = "tux";
        };
      }
    );

    # A user's `provides.to-hosts` reaches the host through mutual-provider.
    test-to-hosts-delivers = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.probe.text = "from-tux";
        expr = igloo.environment.etc.probe.text;
        expected = "from-tux";
      }
    );

    # A parametric `provides.to-hosts` delivers too: its include is named
    # after the owner's policy (`<policy:tux/to-hosts>`).
    test-parametric-to-hosts-delivers = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts =
          { host, ... }:
          {
            nixos.environment.etc.probe.text = host.name;
          };
        expr = igloo.environment.etc.probe.text;
        expected = "igloo";
      }
    );

    # S7: with `users = [ "tux" ]`, a second user's host-class content does
    # not reach the host.
    test-user-list-excludes-second-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.igloo.includes = [ (den.batteries.user-aspects { users = [ "tux" ]; }) ];
        den.aspects.pingu.nixos.environment.etc.pingu-own.text = "pingu";
        expr = igloo.environment.etc ? pingu-own;
        expected = false;
      }
    );

    # The fix: user-aspects on the host restores the old behaviour.
    test-user-aspects-restores = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.nixos.environment.etc.probe.text = "from-tux";
        expr = igloo.environment.etc.probe.text;
        expected = "from-tux";
      }
    );

    # C11: a `{ host }` function in den.default also fires at each user scope;
    # the host scope carries the same aspect, so it is not a loss.
    test-default-host-function-no-loss = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          (
            { host, ... }:
            {
              nixos.environment.etc."host-${host.name}".text = host.name;
            }
          )
        ];
        expr = igloo.environment.etc.host-igloo.text;
        expected = "igloo";
      }
    );

    # A `{ host, user }` function in den.default: den.default is every entity's
    # include, so its host-side registration applies to the host (§11a).
    test-default-host-user-function-lands = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [
          (
            { host, user, ... }:
            {
              nixos.environment.etc."user-${user.name}".text = user.name;
            }
          )
        ];
        expr = igloo.environment.etc.user-tux.text;
        expected = "tux";
      }
    );

    # (a′): an instantiate registered at a host's own scope is bounded at that
    # host. A user's content of the instantiated class does not reach it.
    test-host-scope-instantiate-bounded = denTest (
      {
        den,
        lib,
        config,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.settings.description = "settings fragments";
        den.policies.settings-capture =
          { host, ... }:
          [
            (den.lib.policy.instantiate {
              name = "${host.name}-settings";
              class = "settings";
              instantiate =
                { modules, ... }:
                (lib.evalModules {
                  modules = modules ++ [
                    { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
                  ];
                }).config;
              intoAttr = [
                "settingsOf"
                host.name
              ];
            })
          ];
        den.schema.host.includes = [ den.policies.settings-capture ];
        den.aspects.igloo.settings.fromHost = "igloo";
        den.aspects.tux.settings.fromUser = "tux";
        expr = config.flake.settingsOf.igloo ? fromUser;
        expected = false;
      }
    );

    # The `isolated` alias still bounds a kind-scope with no own entity, and a
    # named delivery still crosses it.
    test-isolated-alias-delivery-crosses = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.user.isolated = true;
        den.aspects.tux.user.description = "tux";
        expr = igloo.users.users.tux.description;
        expected = "tux";
      }
    );
  };
}
