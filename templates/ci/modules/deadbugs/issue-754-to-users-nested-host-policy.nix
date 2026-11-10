# Reported in GitHub #754: a `{ host }` policy nested in an aspect a host hands
# its users (`provides.to-users`) registers at the user after its dispatch ran,
# and late dispatch's entity-kind filter dropped it. unfree's host half is such
# a policy, so its packages never reached the host's unfree list. A scope's own
# late registrations are exempt from that filter.
{ denTest, ... }:
let
  setup = den: {
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
    den.aspects.tux.homeManager.home.stateVersion = "25.11";
    den.aspects.igloo.includes = [ den.aspects.dev ];
    den.aspects.dev.provides.to-users.includes = [ den.aspects.carrier ];
  };
in
{
  flake.tests.deadbugs.issue-754-to-users-nested-host-policy = {
    test-unfree-host-half-reaches-host = denTest (
      { den, igloo, ... }:
      {
        imports = [ (setup den) ];
        den.aspects.carrier.includes = [ (den.batteries.unfree [ "fixture-unfree" ]) ];
        expr = igloo.unfree.packages;
        expected = [ "fixture-unfree" ];
      }
    );
    test-author-host-policy-reaches-host = denTest (
      { den, igloo, ... }:
      {
        imports = [ (setup den) ];
        den.aspects.carrier.includes = [
          (den.lib.policy.mkPolicy "nested-host" (
            { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.nested-host.text = host.name; }) ]
          ))
        ];
        expr = igloo.environment.etc.nested-host.text or null;
        expected = "igloo";
      }
    );
  };
}
