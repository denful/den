{ denTest, ... }:
{
  flake.tests.provide-to = {

    # Aspect without provide-to produces no emissions.
    test-no-provide-to-no-emissions = denTest (
      { den, ... }:
      let
        self = {
          name = "plain-aspect";
          meta = { };
          nixos = {
            x = 1;
          };
          includes = [ ];
        };
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          inherit self;
          ctx = { };
        };
      in
      {
        expr = builtins.length (result.state.provideTo null);
        expected = 0;
      }
    );

    # Sibling policy (from == to) routes through provide-to, not local resolution.
    test-sibling-routes-to-provide-to = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.x86_64-linux.iceberg = { };

        den.policies.test-host-to-peer = {
          to = "host";
          __functor =
            _:
            {
              __entityKind ? null,
              host,
              ...
            }:
            if __entityKind != "host" then
              [ ]
            else
              map (h: den.lib.policy.resolve { host = h; }) (
                lib.filter (h: h.name != host.name) (lib.attrValues (den.hosts.x86_64-linux or { }))
              );
        };

        expr =
          let
            igloo = den.hosts.x86_64-linux.igloo;
            result = den.lib.aspects.fx.pipeline.fxFullResolve {
              class = "nixos";
              self = den.lib.resolveEntity "host" {
                inherit (igloo) system;
                host = igloo;
              };
              ctx = {
                inherit (igloo) system;
                host = igloo;
              };
            };
            emissions = result.state.provideTo null;
            first = builtins.head emissions;
          in
          {
            hasEmissions = emissions != [ ];
            hasTargetEntity = first ? targetEntity;
            hasTraits = first ? traits;
            targetName = first.targetEntity.name or "";
          };
        expected = {
          hasEmissions = true;
          hasTargetEntity = true;
          hasTraits = true;
          targetName = "iceberg";
        };
      }
    );

    # Fleet /etc/hosts: two hosts, each provides IP to peers via provide-to.
    # Distribution groups by target and merges trait data.
    test-fleet-hosts-distribution = denTest (
      { den, lib, ... }:
      let
        # Simulate provide-to emissions (new shape: { targetEntity, traits })
        emissions = [
          {
            targetEntity = {
              name = "iceberg";
            };
            traits = {
              peer = [
                {
                  ip = "10.0.0.1";
                  hostname = "igloo";
                }
              ];
            };
          }
          {
            targetEntity = {
              name = "igloo";
            };
            traits = {
              peer = [
                {
                  ip = "10.0.0.2";
                  hostname = "iceberg";
                }
              ];
            };
          }
        ];
        grouped = den.lib.aspects.fx.distributeCrossEntity.groupByTarget emissions;
        distributed = den.lib.aspects.fx.distributeCrossEntity.distributeCrossEntityTraits { } emissions;
      in
      {
        expr = {
          targets = builtins.sort (a: b: a < b) (builtins.attrNames grouped);
          iglooData = (builtins.head distributed.igloo.peer).hostname;
          icebergData = (builtins.head distributed.iceberg.peer).hostname;
        };
        expected = {
          targets = [
            "iceberg"
            "igloo"
          ];
          iglooData = "iceberg";
          icebergData = "igloo";
        };
      }
    );

    # Haproxy backends: multiple sources provide http-backend data to a target.
    # Distribution accumulates data under the same trait across sources.
    test-haproxy-backend-distribution = denTest (
      { den, lib, ... }:
      let
        emissions = [
          {
            targetEntity = {
              name = "lb";
            };
            traits = {
              http-backends = [
                {
                  address = "10.0.0.1";
                  port = 8080;
                  vhost = "example.com";
                }
              ];
            };
          }
          {
            targetEntity = {
              name = "lb";
            };
            traits = {
              http-backends = [
                {
                  address = "10.0.0.2";
                  port = 8081;
                  vhost = "foobar.com";
                }
              ];
            };
          }
        ];
        distributed = den.lib.aspects.fx.distributeCrossEntity.distributeCrossEntityTraits { } emissions;
        handlers = den.lib.aspects.fx.distributeCrossEntity.distribute { } emissions;
      in
      {
        expr = {
          backendCount = builtins.length distributed.lb.http-backends;
          hasHandler = handlers ? lb;
          vhosts = builtins.sort (a: b: a < b) (map (b: b.vhost) distributed.lb.http-backends);
        };
        expected = {
          backendCount = 2;
          hasHandler = true;
          vhosts = [
            "example.com"
            "foobar.com"
          ];
        };
      }
    );

    # Distribution produces constantHandler bindings usable by bind.fn.
    test-distribute-produces-handlers = denTest (
      { den, lib, ... }:
      let
        emissions = [
          {
            targetEntity = {
              name = "lb";
            };
            traits = {
              http-backends = [
                {
                  address = "10.0.0.1";
                  port = 80;
                }
              ];
            };
          }
        ];
        handlers = den.lib.aspects.fx.distributeCrossEntity.distribute { } emissions;
        # The handler for "lb" should contain an "http-backends" effect handler
        lbHandlers = handlers.lb;
      in
      {
        expr = {
          hasHttpBackends = lbHandlers ? http-backends;
        };
        expected = {
          hasHttpBackends = true;
        };
      }
    );

    # Map collection strategy: merges attrsets, detects duplicate keys.
    test-map-collection-merges = denTest (
      { den, lib, ... }:
      let
        traitSchemas = {
          endpoints = {
            collection = "map";
          };
        };
        emissions = [
          {
            targetEntity = {
              name = "gateway";
            };
            traits = {
              endpoints = {
                api = "10.0.0.1:8080";
              };
            };
          }
          {
            targetEntity = {
              name = "gateway";
            };
            traits = {
              endpoints = {
                web = "10.0.0.2:80";
              };
            };
          }
        ];
        distributed = den.lib.aspects.fx.distributeCrossEntity.distributeCrossEntityTraits {
          inherit traitSchemas;
        } emissions;
      in
      {
        expr = {
          hasApi = distributed.gateway.endpoints ? api;
          hasWeb = distributed.gateway.endpoints ? web;
          apiVal = distributed.gateway.endpoints.api;
        };
        expected = {
          hasApi = true;
          hasWeb = true;
          apiVal = "10.0.0.1:8080";
        };
      }
    );

    # Map collection with duplicate keys throws error.
    test-map-collection-duplicate-throws = denTest (
      { den, lib, ... }:
      let
        traitSchemas = {
          endpoints = {
            collection = "map";
          };
        };
        emissions = [
          {
            targetEntity = {
              name = "gateway";
            };
            traits = {
              endpoints = {
                api = "10.0.0.1:8080";
              };
            };
          }
          {
            targetEntity = {
              name = "gateway";
            };
            traits = {
              endpoints = {
                api = "10.0.0.2:9090";
              };
            };
          }
        ];
        result = builtins.tryEval (
          builtins.deepSeq (den.lib.aspects.fx.distributeCrossEntity.distributeCrossEntityTraits {
            inherit traitSchemas;
          } emissions) true
        );
      in
      {
        expr = result.success;
        expected = false;
      }
    );

    # --- fxResolve: cross-entity traits injection (list strategy) ---

    test-cross-entity-list-injection = denTest (
      { den, lib, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = {
            name = "target-host";
            meta = { };
            peer = [
              {
                ip = "127.0.0.1";
                hostname = "self";
              }
            ];
            includes = [ ];
          };
          ctx = { };
          crossEntityTraits = {
            peer = [
              {
                ip = "10.0.0.1";
                hostname = "igloo";
              }
              {
                ip = "10.0.0.2";
                hostname = "iceberg";
              }
            ];
          };
        };
        # The last import is the traitModule; call it with minimal moduleArgs
        traitModule = lib.last result.imports;
        moduleResult = traitModule {
          inherit lib;
          config = { };
          pkgs = { };
          options = { };
          modulesPath = "";
        };
        peers = moduleResult.config._den.traits.peer;
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.peer = {
          description = "Peer hosts";
          collection = "list";
        };

        expr = {
          # Within-entity (1) + cross-entity (2) = 3
          totalPeers = builtins.length peers;
          crossEntityPresent = builtins.any (p: p.hostname == "igloo") peers;
          withinEntityPresent = builtins.any (p: p.hostname == "self") peers;
        };
        expected = {
          totalPeers = 3;
          crossEntityPresent = true;
          withinEntityPresent = true;
        };
      }
    );

    # --- fxResolve: cross-entity traits injection (map strategy) ---

    test-cross-entity-map-injection = denTest (
      { den, lib, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = {
            name = "gateway";
            meta = { };
            endpoints = {
              local = "127.0.0.1:80";
            };
            includes = [ ];
          };
          ctx = { };
          crossEntityTraits = {
            endpoints = {
              api = "10.0.0.1:8080";
              web = "10.0.0.2:80";
            };
          };
        };
        traitModule = lib.last result.imports;
        moduleResult = traitModule {
          inherit lib;
          config = { };
          pkgs = { };
          options = { };
          modulesPath = "";
        };
        endpoints = moduleResult.config._den.traits.endpoints;
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.endpoints = {
          description = "Service endpoints";
          collection = "map";
        };

        expr = {
          hasLocal = endpoints ? local;
          hasApi = endpoints ? api;
          hasWeb = endpoints ? web;
          localVal = endpoints.local;
          apiVal = endpoints.api;
        };
        expected = {
          hasLocal = true;
          hasApi = true;
          hasWeb = true;
          localVal = "127.0.0.1:80";
          apiVal = "10.0.0.1:8080";
        };
      }
    );

    # --- fxResolve: cross-entity map duplicate detection ---

    test-cross-entity-map-duplicate-throws = denTest (
      { den, lib, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = {
            name = "gateway";
            meta = { };
            endpoints = {
              api = "127.0.0.1:80";
            };
            includes = [ ];
          };
          ctx = { };
          crossEntityTraits = {
            endpoints = {
              api = "10.0.0.1:8080";
            };
          };
        };
        traitModule = lib.last result.imports;
        moduleResult = traitModule {
          inherit lib;
          config = { };
          pkgs = { };
          options = { };
          modulesPath = "";
        };
        evaluated = builtins.tryEval (builtins.deepSeq moduleResult.config._den.traits.endpoints true);
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.endpoints = {
          description = "Service endpoints";
          collection = "map";
        };

        expr = evaluated.success;
        expected = false;
      }
    );

    # --- fxResolve: empty crossEntityTraits is no-op ---

    test-cross-entity-empty-is-noop = denTest (
      { den, lib, ... }:
      let
        resultWithout = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = {
            name = "test";
            meta = { };
            peer = [
              {
                ip = "127.0.0.1";
              }
            ];
            includes = [ ];
          };
          ctx = { };
        };
        resultWith = den.lib.aspects.fx.pipeline.fxResolve {
          class = "nixos";
          self = {
            name = "test";
            meta = { };
            peer = [
              {
                ip = "127.0.0.1";
              }
            ];
            includes = [ ];
          };
          ctx = { };
          crossEntityTraits = { };
        };
        mkModuleArgs = {
          inherit lib;
          config = { };
          pkgs = { };
          options = { };
          modulesPath = "";
        };
        traitsWithout = (lib.last resultWithout.imports) mkModuleArgs;
        traitsWith = (lib.last resultWith.imports) mkModuleArgs;
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.peer = {
          description = "Peer hosts";
          collection = "list";
        };

        expr = traitsWithout.config._den.traits == traitsWith.config._den.traits;
        expected = true;
      }
    );

  };
}
