# Issue #694, spec §11a: a policy applies to the entity it is registered on.
# A host-registered `{ host, user }` policy applies to both relata: its include
# lands in full at the user, and the host-class part reaches the host.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-694-registrant = {

    test-host-policy-applies-to-both-relata = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.home.stateVersion = "25.11";
        den.policies.both =
          { host, user, ... }:
          [
            (den.lib.policy.include {
              nixos.environment.etc."both-${user.name}".text = host.name;
              homeManager.home.sessionVariables.BOTH = host.name;
            })
          ];
        den.aspects.igloo.includes = [ den.policies.both ];
        expr = {
          host = igloo.environment.etc.both-tux.text or "<missing>";
          home = igloo.home-manager.users.tux.home.sessionVariables.BOTH or "<missing>";
        };
        expected = {
          host = "igloo";
          home = "igloo";
        };
      }
    );

    # The same body as a host policy (igloo) and as a host aspect function
    # (iceberg) gives the same option values.
    test-host-policy-equals-host-aspect-function = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      let
        body =
          { host, user, ... }:
          {
            nixos.environment.etc."sym-${user.name}".text = user.name;
            nixos.users.users.${user.userName}.description = "sym ${user.name}";
          };
        values = h: {
          etc = h.environment.etc.sym-tux.text or "<missing>";
          description = h.users.users.tux.description;
        };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.policies.sym = { host, user, ... }@ctx: [ (den.lib.policy.include (body ctx)) ];
        den.aspects.igloo.includes = [ den.policies.sym ];
        den.aspects.iceberg.includes = [ body ];
        expr = values igloo == values iceberg && (values igloo).etc == "tux";
        expected = true;
      }
    );

    # den.default is every entity's include: its host-side registration applies
    # to the host, for a policy and an aspect function alike.
    test-default-policy-and-function-land = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.dflt =
          { host, user, ... }:
          [ (den.lib.policy.include { nixos.environment.etc."dp-${user.name}".text = "p"; }) ];
        den.default.includes = [
          den.policies.dflt
          (
            { host, user, ... }:
            {
              nixos.environment.etc."df-${user.name}".text = "f";
            }
          )
        ];
        expr = {
          policy = igloo.environment.etc.dp-tux.text or "<missing>";
          function = igloo.environment.etc.df-tux.text or "<missing>";
        };
        expected = {
          policy = "p";
          function = "f";
        };
      }
    );

    # Registered on the host and on the user: one instance, landing once.
    test-registered-on-both-sides-once = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.twice =
          { host, user, ... }: [ (den.lib.policy.include { nixos.boot.kernelModules = [ "twice-mod" ]; }) ];
        den.aspects.igloo.includes = [ den.policies.twice ];
        den.aspects.tux.includes = [ den.policies.twice ];
        expr = builtins.filter (m: m == "twice-mod") igloo.boot.kernelModules;
        expected = [ "twice-mod" ];
      }
    );

    # For a user the host accepts through user-aspects the boundary is already
    # lifted; the registrant route stands down, so unkeyed content lands once.
    # Pins the outcome only: with the stand-down removed it still lands once,
    # because assembly dedups the second copy by its location key.
    test-stands-down-under-user-aspects = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.acc =
          { host, user, ... }: [ (den.lib.policy.include { nixos.boot.kernelModules = [ "acc-mod" ]; }) ];
        den.aspects.igloo.includes = [
          den.batteries.user-aspects
          den.policies.acc
        ];
        expr = builtins.filter (m: m == "acc-mod") igloo.boot.kernelModules;
        expected = [ "acc-mod" ];
      }
    );

    # C6: a receiver-less provide from a host policy, firing at the user and
    # targeting the host's class, lands on the host.
    test-host-policy-receiverless-provide-reaches-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.prov =
          { host, user, ... }:
          [
            (den.lib.policy.provide {
              class = "nixos";
              module.environment.etc."prov-${user.name}".text = host.name;
            })
          ];
        den.aspects.igloo.includes = [ den.policies.prov ];
        expr = igloo.environment.etc.prov-tux.text or "<missing>";
        expected = "igloo";
      }
    );

    # D4 (wrapper order): a host policy including an aspect that carries
    # `to-hosts`. With mutual-provider in place both cross.
    test-host-policy-include-with-to-hosts-crosses = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feature = {
          nixos.environment.etc.own.text = "own";
          provides.to-hosts.nixos.environment.etc.provided.text = "provided";
        };
        den.policies.wrap = { host, user, ... }: [ (den.lib.policy.include den.aspects.feature) ];
        den.aspects.igloo.includes = [ den.policies.wrap ];
        expr = {
          own = igloo.environment.etc.own.text or "<missing>";
          provided = igloo.environment.etc.provided.text or "<missing>";
        };
        expected = {
          own = "own";
          provided = "provided";
        };
      }
    );

    # D4: with mutual-provider excluded on igloo, the `to-hosts` content is
    # gated by its own (innermost) provider and does not reach igloo.
    test-host-policy-include-to-hosts-gated-by-mutual-provider = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feature = {
          nixos.environment.etc.own.text = "own";
          provides.to-hosts.nixos.environment.etc.provided.text = "provided";
        };
        den.policies.wrap = { host, user, ... }: [ (den.lib.policy.include den.aspects.feature) ];
        den.aspects.igloo.includes = [ den.policies.wrap ];
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = igloo.environment.etc.provided.text or "<missing>";
        expected = "<missing>";
      }
    );

    # D5: the fold drops a shared fan-out copy only for the host that accepts
    # the user. tux on iceberg, not accepted there, keeps the content.
    # Pins the outcome: assembly's location-key dedup would also keep igloo's
    # copy single without the drop.
    test-shared-fanout-drop-keyed-to-accepting-host = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.default.includes = [
          (
            { host, user, ... }:
            {
              nixos.boot.kernelModules = [ "d5-${user.name}" ];
            }
          )
        ];
        expr = {
          igloo = builtins.filter (m: m == "d5-tux") igloo.boot.kernelModules;
          iceberg = builtins.filter (m: m == "d5-tux") iceberg.boot.kernelModules;
        };
        expected = {
          igloo = [ "d5-tux" ];
          iceberg = [ "d5-tux" ];
        };
      }
    );

    # C5a: a policy registered at a microvm-guest scope (which binds `host` and
    # `vm`, and no key named after its kind) has the nearest own entity as its
    # registrant: igloo. Pins the outcome: den links a scope to its own entity
    # through its kind's binding (push-scope's scopeByEntity), so a by-name
    # lookup and the identity rule agree here.
    test-microvm-guest-registered-policy-lands-on-host = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.schema.microvm-host.parent = "host";
        den.schema.microvm-guest.parent = "microvm-host";
        den.policies.to-microvm-host =
          { host, ... }:
          lib.optional (host.name == "igloo") (den.lib.policy.resolve.to "microvm-host" { inherit host; });
        den.policies.to-microvm-guest =
          { host, ... }:
          [
            (den.lib.policy.resolve.to "microvm-guest" {
              inherit host;
              vm.name = "g";
            })
          ];
        den.policies.guest-content =
          { host, vm, ... }:
          [ (den.lib.policy.include { nixos.environment.etc."vm-${vm.name}".text = host.name; }) ];
        den.schema.host.includes = [ den.policies.to-microvm-host ];
        den.schema.microvm-host.includes = [ den.policies.to-microvm-guest ];
        den.schema.microvm-guest.includes = [ den.policies.guest-content ];
        expr = igloo.environment.etc.vm-g.text or "<missing>";
        expected = "igloo";
      }
    );
  };
}
