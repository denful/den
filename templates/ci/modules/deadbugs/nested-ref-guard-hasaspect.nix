# A `policy.when` guard's `host.hasAspect` must recognise a nested sub-aspect
# the same as a `provides` child. A nested key reaches the guard as a content
# wrapper carrying only `__aspectChain`, which keyed as `<anon>` and never
# matched, so the guarded user half was silently dropped.
{ denTest, ... }:
{
  flake.tests.nested-ref-guard-hasaspect =
    let
      subs = {
        host-part.nixos =
          { host, ... }:
          {
            networking.nameservers = [ host.name ];
          };
        user-part.nixos =
          { user, ... }:
          {
            networking.nameservers = [ user.name ];
          };
      };
      mkAspect =
        viaProvides: den:
        {
          includes = [
            (den.lib.policy.when (
              {
                user ? null,
                ...
              }:
              user == null
            ) den.aspects.feature.host-part)
            (den.lib.policy.when (
              {
                host,
                user ? null,
                ...
              }:
              user != null && host.hasAspect den.aspects.feature.host-part
            ) den.aspects.feature.user-part)
          ];
        }
        // (if viaProvides then { provides = subs; } else subs);
      mutual =
        viaProvides:
        denTest (
          { den, igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.aspects.feature = mkAspect viaProvides den;
            den.aspects.igloo.includes = [ den.aspects.feature ];
            den.aspects.tux.includes = [ den.aspects.feature ];
            expr = igloo.networking.nameservers;
            expected = [
              "tux"
              "igloo"
            ];
          }
        );
      hostOptedOut =
        viaProvides:
        denTest (
          { den, igloo, ... }:
          {
            den.hosts.x86_64-linux.igloo.users.tux = { };
            den.aspects.feature = mkAspect viaProvides den;
            den.aspects.tux.includes = [ den.aspects.feature ];
            expr = igloo.networking.nameservers;
            expected = [ ];
          }
        );
    in
    {
      test-nested-mutual = mutual false;
      test-nested-host-opted-out = hostOptedOut false;
      test-provides-mutual = mutual true;
      test-provides-host-opted-out = hostOptedOut true;
    };
}
