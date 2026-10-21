# `excludes = [ [ policy ] ]` type-checked and excluded NOTHING, in silence.
#
# `providerType`'s check names a list of policy records as a valid element, so
# the value was admitted; `excludeIdentity` had no list arm, so `identity.key`
# reduced it to "<anon>" and matched no policy. The same value in `includes`
# flattens and delivers, so the two disagreed over a shape their shared type
# calls valid — the silent no-op #3c5b5227 closed for bare strings, still open
# over the shape that commit's own type admits.
#
# Three arms in one run, because no single cell discriminates both directions:
# over-excluding is visible, under-excluding is silent. Arm three is why the
# other two are not vacuous — without a firing policy they pass on a marker that
# never existed.
{ denTest, ... }:
{
  flake.tests.list-element-exclude = {
    # The fixed direction: a list-wrapped policy reference must exclude.
    test-list-element-exclude = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.add-marker = _: [
          (den.lib.policy.include {
            nixos.environment.variables.LIST_EXCLUDE_MARKER = "yes";
          })
        ];
        den.aspects.igloo = {
          includes = [ den.policies.add-marker ];
          excludes = [ [ den.policies.add-marker ] ];
        };

        expr = igloo.environment.variables.LIST_EXCLUDE_MARKER or "absent";
        expected = "absent";
      }
    );

    # Control A — the record form already worked. If this reddens, the fix broke
    # the path it was meant to leave alone.
    test-control-record-exclude = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.add-marker = _: [
          (den.lib.policy.include {
            nixos.environment.variables.LIST_EXCLUDE_MARKER = "yes";
          })
        ];
        den.aspects.igloo = {
          includes = [ den.policies.add-marker ];
          excludes = [ den.policies.add-marker ];
        };

        expr = igloo.environment.variables.LIST_EXCLUDE_MARKER or "absent";
        expected = "absent";
      }
    );

    # Control B — with nothing excluded the marker must actually fire.
    test-control-no-exclude = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.add-marker = _: [
          (den.lib.policy.include {
            nixos.environment.variables.LIST_EXCLUDE_MARKER = "yes";
          })
        ];
        den.aspects.igloo = {
          includes = [ den.policies.add-marker ];
        };

        expr = igloo.environment.variables.LIST_EXCLUDE_MARKER or "absent";
        expected = "yes";
      }
    );
  };
}
