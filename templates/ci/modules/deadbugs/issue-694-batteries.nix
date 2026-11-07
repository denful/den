# Issue #694, PR 2: the mutual-provider and user-aspects batteries. Their
# delivery parts stay inert until the flip (the old subtree merge still carries
# the content), so these cells cover what holds already: the gates and the
# acceptance keys the host publishes.
{ denTest, ... }:
let
  hostCtx =
    config: name:
    config.den.hosts.x86_64-linux.${name}.__resolveResult.scopeContexts."host=${name}" or { };
  # The provide edges in a resolve's trace, by the policy that emitted them.
  providers =
    result:
    map (e: e.annotations.providesPolicyName) (
      builtins.filter (e: (e.annotations or { }) ? providesPolicyName) result.edgeTrace
    );
  # mutual-provider's host delivery is a route reading what the provider emitted.
  provenanceRoutes =
    result:
    map (e: e.annotations.fromProvenance) (
      builtins.filter (e: (e.annotations or { }) ? fromProvenance) result.edgeTrace
    );
  keysWith =
    prefix: ctx:
    builtins.filter (k: builtins.substring 0 (builtins.stringLength prefix) k == prefix) (
      builtins.attrNames ctx
    );
in
{
  flake.tests.deadbugs.issue-694-batteries = {

    # A standalone home binds a host that is not its ancestor, so a provide to
    # it has no receiver; the battery stays inert there.
    test-standalone-home-provides-host-evaluates = denTest (
      { config, den, ... }:
      {
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.tux.homeManager.home = {
          username = "tux";
          homeDirectory = "/home/tux";
        };
        den.aspects.tux.provides.igloo.nixos.environment.etc.from-tux.text = "tux";
        expr = config.flake.homeConfigurations."tux@igloo".config.home.username;
        expected = "tux";
      }
    );

    # The same, with a declared igloo: the home binds the real record, which is
    # still not on its chain.
    test-bound-home-provides-host-evaluates = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.tux.homeManager.home = {
          username = "tux";
          homeDirectory = "/home/tux";
        };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.from-tux.text = "tux";
        expr = config.flake.homeConfigurations."tux@igloo".config.home.username;
        expected = "tux";
      }
    );

    # Default-included: the host publishes its acceptance key.
    # The battery is opt-in: without it a host publishes no key; included, it
    # publishes its own. (Its transition default: issue-694-migration.nix.)
    test-mutual-provider-key-published = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        expr = keysWith "den-mutual-provider/" (hostCtx config "igloo");
        expected = [ (den.lib.acceptance.mutualProviderKey config.den.hosts.x86_64-linux.igloo) ];
      }
    );
    test-mutual-provider-no-key-without-it = denTest (
      { config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = keysWith "den-mutual-provider/" (hostCtx config "igloo");
        expected = [ ];
      }
    );

    # An exclude of the default-included battery removes its key.
    test-mutual-provider-exclude-removes-key = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.host.excludes = [ den.batteries.mutual-provider ];
        expr = keysWith "den-mutual-provider/" (hostCtx config "igloo");
        expected = [ ];
      }
    );

    # Per-host opt-out, in both spellings: the excluding host publishes no key,
    # the other host still does.
    test-mutual-provider-per-host-exclude = denTest (
      { config, den, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.hosts.x86_64-linux.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = {
          igloo = keysWith "den-mutual-provider/" (hostCtx config "igloo");
          iceberg = builtins.length (keysWith "den-mutual-provider/" (hostCtx config "iceberg"));
        };
        expected = {
          igloo = [ ];
          iceberg = 1;
        };
      }
    );

    test-mutual-provider-aspect-exclude = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = keysWith "den-mutual-provider/" (hostCtx config "igloo");
        expected = [ ];
      }
    );

    # The callable form earlier configs used still evaluates.
    test-mutual-provider-callable-form = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ (den._.mutual-provider { }) ];
        den.aspects.igloo.nixos.environment.etc.marker.text = "ok";
        expr = igloo.environment.etc.marker.text;
        expected = "ok";
      }
    );

    # Two users' to-hosts evaluate together: the delivery is a provide, so no
    # forward reads another user's output (no delivery-edge cycle).
    test-two-users-to-hosts = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.from-tux.text = "tux";
        den.aspects.pingu.provides.to-hosts.nixos.environment.etc.from-pingu.text = "pingu";
        expr = [
          igloo.environment.etc.from-tux.text
          igloo.environment.etc.from-pingu.text
        ];
        expected = [
          "tux"
          "pingu"
        ];
      }
    );

    # Each argument set publishes its own key; two identical includes share one.
    test-user-aspects-keys = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.igloo.includes = [
          den.batteries.user-aspects
          (den.batteries.user-aspects { users = [ "tux" ]; })
          (den.batteries.user-aspects { users = [ "tux" ]; })
        ];
        expr = builtins.length (keysWith "den-user-aspects/" (hostCtx config "igloo"));
        expected = 2;
      }
    );

    # The acceptance key the default-on mutual-provider publishes is den-internal
    # context: a user's exact-match function still sees exactly { host, user }.
    # Resolved directly (as internal.ctx-transformation does): a flake-built
    # user scope also binds `system`.
    test-take-exactly-unaffected-by-acceptance = denTest (
      { den, funnyNames, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        # The host-rooted flat resolve reads tux's `funny` through user-aspects.
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.includes = [
          (den.lib.take.exactly (
            { host, user }:
            {
              funny.names = [ "${host.name}/${user.name}" ];
            }
          ))
        ];
        expr = funnyNames (den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; });
        expected = [ "igloo/tux" ];
      }
    );

    # B1: the os-user-class-fwd delivery is its own policy, so provide dedup
    # keeps it next to the home-manager host-module provide.
    test-hook-and-host-module-both-delivered = denTest (
      { config, den, ... }:
      let
        names = providers config.den.hosts.x86_64-linux.igloo.__resolveResult;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.os-user-class-fwd.nixos.environment.etc.hook.text = "hook";
        expr = {
          hostModule = builtins.elem "hm-user-detect" names;
          hook = builtins.elem "hm-os-user-class-fwd-host" names;
        };
        expected = {
          hostModule = true;
          hook = true;
        };
      }
    );

    # S3: a user's to-hosts emits its host delivery at the user scope on a
    # built host, and the home gate keeps a standalone home from emitting it.
    test-to-hosts-provide-emitted-and-home-gated = denTest (
      { config, den, ... }:
      let
        hasToHosts = names: builtins.any (n: builtins.match ".*to-hosts" n != null) names;
      in
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.tux.homeManager.home = {
          username = "tux";
          homeDirectory = "/home/tux";
        };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.probe.text = "from-tux";
        expr = {
          host = hasToHosts (provenanceRoutes config.den.hosts.x86_64-linux.igloo.__resolveResult);
          home = hasToHosts (provenanceRoutes config.den.homes.x86_64-linux."tux@igloo".__resolveResult);
        };
        expected = {
          host = true;
          home = false;
        };
      }
    );

    # Included on a user, the battery publishes nothing.
    test-user-aspects-user-side-publishes-nothing = denTest (
      { config, den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ den.batteries.user-aspects ];
        expr = keysWith "den-user-aspects/" (
          config.den.hosts.x86_64-linux.igloo.__resolveResult.scopeContexts."host=igloo,user=tux" or { }
        );
        expected = [ ];
      }
    );
  };
}
