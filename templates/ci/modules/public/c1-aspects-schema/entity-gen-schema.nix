{ denTest, ... }:
{
  flake.tests.entity-gen-schema = {
    # gen-schema id_hash available on hosts
    test-entity-host-id-hash = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = {
          hasIdHash = den.hosts.x86_64-linux.igloo ? id_hash;
          isString = builtins.isString den.hosts.x86_64-linux.igloo.id_hash;
        };
        expected = {
          hasIdHash = true;
          isString = true;
        };
      }
    );

    # id_hash differs between different hosts
    test-entity-id-hash-differs = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.tundra.users.tux = { };

        expr = den.hosts.x86_64-linux.igloo.id_hash != den.hosts.x86_64-linux.tundra.id_hash;
        expected = true;
      }
    );

    # Freeform: arbitrary attributes on hosts not rejected
    test-entity-freeform = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          customAttr = "hello";
        };

        expr = den.hosts.x86_64-linux.igloo.customAttr;
        expected = "hello";
      }
    );

    # gen-schema _meta.topology derived from parent collections
    test-entity-topology = denTest (
      { den, ... }:
      {
        expr = den.schema._topology.host.children;
        expected = [
          "home"
          "user"
        ];
      }
    );

    # gen-schema _topology is available
    test-entity-topology-available = denTest (
      { den, ... }:
      {
        expr = den.schema ? _topology;
        expected = true;
      }
    );

    # _roots (parentless kinds) is the buildRoots root-detection contract:
    # host is a root scope; user/home are spawned under host, not roots.
    test-entity-roots = denTest (
      { den, ... }:
      {
        expr = {
          hostIsRoot = builtins.elem "host" den.schema._roots;
          userNotRoot = builtins.elem "user" den.schema._roots;
          homeNotRoot = builtins.elem "home" den.schema._roots;
        };
        expected = {
          hostIsRoot = true;
          userNotRoot = false;
          homeNotRoot = false;
        };
      }
    );

    # Schema entry has isEntity computed correctly
    test-entity-is-entity = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = {
          hostIsEntity = den.schema.host.isEntity;
          flakeIsEntity = den.schema.flake.isEntity;
        };
        expected = {
          hostIsEntity = true;
          flakeIsEntity = false;
        };
      }
    );

    # Schema entry has includes sidecar
    test-entity-schema-includes = denTest (
      { den, ... }:
      {
        expr = builtins.isList den.schema.host.includes;
        expected = true;
      }
    );
  };
}
