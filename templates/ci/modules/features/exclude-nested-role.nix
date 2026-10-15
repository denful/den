# A policy.exclude in a host's includes removes an aspect reached through a
# role the same host includes.
{ denTest, lib, ... }:
{
  flake.tests.exclude-nested-role = {

    test-exclude-direct-include = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.probe.text = "feat";
        den.policies.drop-feat = { host, ... }: [ (den.lib.policy.exclude den.aspects.feat) ];
        den.aspects.igloo.includes = [
          den.policies.drop-feat
          den.aspects.feat
        ];
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    test-exclude-through-role = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.probe.text = "feat";
        den.aspects.role.includes = [ den.aspects.feat ];
        den.policies.drop-feat = { host, ... }: [ (den.lib.policy.exclude den.aspects.feat) ];
        den.aspects.igloo.includes = [
          den.policies.drop-feat
          den.aspects.role
        ];
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    test-exclude-through-role-policy-last = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.probe.text = "feat";
        den.aspects.role.includes = [ den.aspects.feat ];
        den.policies.drop-feat = { host, ... }: [ (den.lib.policy.exclude den.aspects.feat) ];
        den.aspects.igloo.includes = [
          den.aspects.role
          den.policies.drop-feat
        ];
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    # The excluded aspect's quirk emits must go too, not only its class content.
    test-exclude-drops-quirk-emits = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items.description = "Items";
        den.aspects.feat.items = [ "from-feat" ];
        den.aspects.consumer.nixos =
          { items, ... }:
          {
            networking.hostName = lib.concatStringsSep "-" ([ "h" ] ++ items);
          };
        den.aspects.role.includes = [ den.aspects.feat ];
        den.policies.drop-feat = { host, ... }: [ (den.lib.policy.exclude den.aspects.feat) ];
        den.aspects.igloo.includes = [
          den.policies.drop-feat
          den.aspects.role
          den.aspects.consumer
        ];
        expr = igloo.networking.hostName;
        expected = "h";
      }
    );
    test-aspect-excludes-through-role = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.probe.text = "feat";
        den.aspects.role.includes = [ den.aspects.feat ];
        den.aspects.igloo.includes = [ den.aspects.role ];
        den.aspects.igloo.excludes = [ den.aspects.feat ];
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    test-aspect-excludes-drops-quirk-emits = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.items.description = "Items";
        den.aspects.feat.items = [ "from-feat" ];
        den.aspects.consumer.nixos =
          { items, ... }:
          {
            networking.hostName = lib.concatStringsSep "-" ([ "h" ] ++ items);
          };
        den.aspects.role.includes = [ den.aspects.feat ];
        den.aspects.igloo.includes = [
          den.aspects.role
          den.aspects.consumer
        ];
        den.aspects.igloo.excludes = [ den.aspects.feat ];
        expr = igloo.networking.hostName;
        expected = "h";
      }
    );
  };
}
