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
  };
}
