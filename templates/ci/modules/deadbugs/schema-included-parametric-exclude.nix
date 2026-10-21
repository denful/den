# A parametric nested aspect (`den.aspects.a.b = { host, ... }: …`) included
# through a schema kind (`den.schema.host.includes`) reaches the pipeline as a
# functor-bearing wrapper. It must keep its own identity (`a/b`) there, as it
# does when a host aspect includes it; before the fix it resolved as an
# anonymous `host/<anon>:N`, so `excludes` naming it never matched and it was
# never deduplicated against the same aspect included another way.
{ denTest, lib, ... }:
let
  resourcesOf =
    modules:
    builtins.attrNames
      (lib.evalModules {
        modules = modules ++ [
          {
            options.resource = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
          }
        ];
      }).config.resource;

  fleet = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.hosts.x86_64-linux.iceberg.users.alice = { };
    den.aspects.kuma.observed =
      { host, ... }:
      {
        nixos.environment.etc."kuma".text = host.name;
        central.resource."monitor-${host.name}" = 1;
      };
    den.schema.host.includes = [ den.aspects.kuma.observed ];
    # one flake-scope instance collecting `central` from every host
    den.policies.central = _: [
      (den.lib.policy.instantiate {
        name = "central";
        class = "central";
        instantiate = { modules, ... }: resourcesOf modules;
        intoAttr = [ "central" ];
      })
    ];
    den.schema.flake.includes = [ den.policies.central ];
  };
in
{
  flake.tests.deadbugs.schema-included-parametric-exclude = {

    test-host-aspect-excludes = denTest (
      {
        den,
        iceberg,
        igloo,
        ...
      }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.iceberg.excludes = [ den.aspects.kuma.observed ];
      }
      // {
        expr = {
          iceberg = iceberg.environment.etc ? kuma;
          igloo = igloo.environment.etc ? kuma;
        };
        expected = {
          iceberg = false;
          igloo = true;
        };
      }
    );

    test-host-instance-excludes = denTest (
      {
        den,
        iceberg,
        igloo,
        ...
      }:
      lib.recursiveUpdate (fleet den) {
        den.hosts.x86_64-linux.iceberg.excludes = [ den.aspects.kuma.observed ];
      }
      // {
        expr = {
          iceberg = iceberg.environment.etc ? kuma;
          igloo = igloo.environment.etc ? kuma;
        };
        expected = {
          iceberg = false;
          igloo = true;
        };
      }
    );

    test-excluded-host-adds-nothing-to-flake-scope-class = denTest (
      { den, config, ... }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.iceberg.excludes = [ den.aspects.kuma.observed ];
      }
      // {
        expr = config.flake.central;
        expected = [ "monitor-igloo" ];
      }
    );

    # a parametric host aspect's own body is walked as a child of the aspect;
    # its excludes are still the aspect's and cover the whole host scope
    test-parametric-host-aspect-excludes = denTest (
      {
        den,
        config,
        iceberg,
        ...
      }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.iceberg =
          { host, ... }:
          {
            excludes = [ den.aspects.kuma.observed ];
          };
      }
      // {
        expr = {
          iceberg = iceberg.environment.etc ? kuma;
          central = config.flake.central;
        };
        expected = {
          iceberg = false;
          central = [ "monitor-igloo" ];
        };
      }
    );

    # without any exclude, every host's per-host content reaches a flake-scope
    # class: the aspect's identity must not collapse two hosts' modules into one
    test-flake-scope-class-keeps-every-host = denTest (
      { den, config, ... }:
      fleet den
      // {
        expr = config.flake.central;
        expected = [
          "monitor-iceberg"
          "monitor-igloo"
        ];
      }
    );

    # schema and host aspect include the same parametric aspect: one identity,
    # so it is included once (a list-typed option would otherwise hold it twice)
    test-schema-and-host-include-dedup = denTest (
      { den, igloo, ... }:
      lib.recursiveUpdate (fleet den) {
        den.aspects.igloo.includes = [ den.aspects.kuma.observed ];
        den.aspects.kuma.observed = lib.mkForce (
          { host, ... }:
          {
            nixos.environment.etc."kuma".text = host.name;
            nixos.networking.timeServers = lib.mkForce [ ];
            nixos.environment.shellAliases = { };
            nixos.users.groups.kuma.members = [ host.name ];
          }
        );
      }
      // {
        expr = igloo.users.groups.kuma.members;
        expected = [ "igloo" ];
      }
    );

  };
}
