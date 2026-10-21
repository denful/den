{ denTest, ... }:
{
  flake.tests.doc-examples = {

    # entities.mdx: den.schema.conf shared options apply to host config.
    test-doc-schema-conf-option = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.conf = {
          options.copyright = lib.mkOption { default = "Copy-Left"; };
        };

        # Schema options are available on the entity's evalModules scope.
        # Test that the option is declared without error.
        expr = den.hosts.x86_64-linux.igloo ? name;
        expected = true;
      }
    );

    # entities.mdx: freeform attributes accessible via host context in aspects.
    test-doc-freeform-host-attrs = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = {
          gpu = "nvidia";
          users.tux = { };
        };

        den.aspects.igloo.includes = [
          (
            { host, ... }:
            lib.optionalAttrs (host ? gpu) {
              nixos.networking.hostName = "gpu-${host.gpu}";
            }
          )
        ];

        expr = igloo.networking.hostName;
        expected = "gpu-nvidia";
      }
    );

    # entities.mdx: den.schema.conf applies across all entity kinds.
    test-doc-schema-conf = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.conf = {
          options.copyright = lib.mkOption { default = "Copy-Left"; };
        };

        expr = igloo ? copyright;
        expected = false;
      }
    );

    # stages.mdx: stages.host.includes attaches behavior to host pipeline stage.
    test-doc-stage-host-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.schema.host.includes = [
          (
            { host, ... }:
            {
              nixos.networking.hostName = "hello-${host.name}";
            }
          )
        ];

        expr = igloo.networking.hostName;
        expected = "hello-igloo";
      }
    );

    # policies.mdx: custom policy with `as` for sibling routing (host-to-peers).
    test-doc-custom-policy-sibling = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };

        den.policies.host-to-peers =
          {
            host,
            ...
          }:
          map (h: den.lib.policy.resolve { host = h; }) (
            lib.filter (h: h.hostName != host.hostName) (lib.attrValues den.hosts.x86_64-linux)
          );

        den.schema.host.includes = [ den.policies.host-to-peers ];

        expr =
          let
            result = den.lib.policyInspect.inspect {
              kind = "host";
              context = {
                host = den.hosts.x86_64-linux.igloo;
              };
            };
          in
          {
            hasPeers = result ? host-to-peers;
            routing = result.host-to-peers.routing;
            targetKey = result.host-to-peers.targetKey;
            targetCount = builtins.length result.host-to-peers.targets;
          };
        expected = {
          hasPeers = true;
          routing = "sibling";
          targetKey = "host";
          targetCount = 1;
        };
      }
    );

    # policies.mdx: policyInspect.inspect returns expected shape.
    test-doc-policy-inspect-shape = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr =
          let
            result = den.lib.policyInspect.inspect {
              kind = "host";
              context = {
                host = den.hosts.x86_64-linux.igloo;
              };
            };
            htu = result.host-to-users;
          in
          {
            hasFrom = htu ? from;
            hasTo = htu ? to;
            hasTargets = htu ? targets;
            hasRouting = htu ? routing;
            hasTargetKey = htu ? targetKey;
            from = htu.from;
            to = htu.to;
            routing = htu.routing;
          };
        expected = {
          hasFrom = true;
          hasTo = true;
          hasTargets = true;
          hasRouting = true;
          hasTargetKey = true;
          from = "host";
          to = "user";
          routing = "child";
        };
      }
    );

  };
}
