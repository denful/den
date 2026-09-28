# A `to-hosts` provide whose aspect is included by a policy that fires in a
# user scope's late pass registers after that pass read the registry. The
# user-scope cases are controls: their own dispatch registers in time.
{ denTest, ... }:
let
  consumer =
    { den, ... }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.aspects.consumer.provides.to-hosts.nixos =
        { user, ... }:
        {
          users.users.${user.name}.description = "X";
        };
    };
  t =
    extra:
    denTest (
      { den, igloo, ... }:
      {
        imports = [
          consumer
          (extra den)
        ];
        expr = igloo.users.users.tux.description;
        expected = "X";
      }
    );
in
{
  flake.tests.late-registered-to-hosts = {
    test-user-policy-include = t (den: {
      den.policies.p = { user, ... }: [ (den.lib.policy.include den.aspects.consumer) ];
      den.aspects.tux.includes = [ den.policies.p ];
    });
    test-user-to-users-relay = t (den: {
      den.aspects.relay.provides.to-users.includes = [ den.aspects.consumer ];
      den.aspects.tux.includes = [ den.aspects.relay ];
    });
    test-host-to-users-relay = t (den: {
      den.aspects.relay.provides.to-users.includes = [ den.aspects.consumer ];
      den.aspects.igloo.includes = [ den.aspects.relay ];
    });
    test-host-policy-include = t (den: {
      den.policies.p = { host, user, ... }: [ (den.lib.policy.include den.aspects.consumer) ];
      den.aspects.igloo.includes = [ den.policies.p ];
    });
    test-projection-chain = t (den: {
      den.aspects.relay.provides.to-hosts.includes = [ den.aspects.consumer ];
      den.aspects.igloo.provides.tux.includes = [ den.aspects.relay ];
    });
    test-projection-two-users = t (den: {
      den.hosts.x86_64-linux.igloo.users.pingu = { };
      den.aspects.igloo.provides.tux.includes = [ den.aspects.consumer ];
    });
    test-projection-via-relay-to-users = t (den: {
      den.aspects.relay.provides.to-users.includes = [ den.aspects.consumer ];
      den.aspects.igloo.provides.tux.includes = [ den.aspects.relay ];
    });
  };
}
