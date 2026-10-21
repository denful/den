# A `policy.exclude` returned by a policy listed in an aspect's `includes` must
# act like that aspect's own `excludes`: it covers everything the aspect
# includes, wherever the policy sits in the list. Before the fix the policy
# fired only at the scope's dispatch, after the static includes had passed the
# gate, and its exclude reached only what the policy itself included.
{ denTest, lib, ... }:
let
  fleet = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.quirks.secrets.description = "secret names";
    den.aspects.feat = {
      nixos.environment.etc.probe.text = "x";
      secrets = "feat-secret";
    };
    den.aspects.role.includes = [ den.aspects.feat ];
    den.aspects.reader.nixos =
      { secrets, ... }:
      {
        environment.etc.secrets.text = builtins.toJSON secrets;
      };
    den.policies.drop-feat = { host, ... }: [ (den.lib.policy.exclude den.aspects.feat) ];
  };
in
{
  flake.tests.deadbugs.policy-exclude-reaches-includer-subtree = {

    test-direct-include = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.igloo.includes = [
          den.policies.drop-feat
          den.aspects.feat
        ];
      }
      // {
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    test-through-role-policy-first = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.igloo.includes = [
          den.policies.drop-feat
          den.aspects.role
        ];
      }
      // {
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    test-through-role-policy-last = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.igloo.includes = [
          den.aspects.role
          den.policies.drop-feat
        ];
      }
      // {
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    test-quirk-emits-dropped = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.igloo.includes = [
          den.aspects.reader
          den.aspects.role
          den.policies.drop-feat
        ];
      }
      // {
        expr = igloo.environment.etc.secrets.text;
        expected = builtins.toJSON [ ];
      }
    );

    # control: the aspect-level exclude, which already worked
    test-aspect-excludes-through-role = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.igloo.includes = [ den.aspects.role ];
        den.aspects.igloo.excludes = [ den.aspects.feat ];
      }
      // {
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    # the exclude is the includer's: a sibling host keeps the aspect
    test-sibling-host-unaffected = denTest (
      { den, iceberg, ... }:
      lib.recursiveUpdate (fleet den) {
        den.hosts.x86_64-linux.iceberg.users.alice = { };
        den.aspects.igloo.includes = [
          den.policies.drop-feat
          den.aspects.role
        ];
        den.aspects.iceberg.includes = [ den.aspects.role ];
      }
      // {
        expr = iceberg.environment.etc ? probe;
        expected = true;
      }
    );

  };
}
