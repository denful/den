{ denTest, ... }:
{
  flake.tests.scope-inheritance = {

    # Single entity, no child scopes — scopeParent has only the root scope.
    test-no-child-scopes = denTest (
      { den, lib, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = {
            name = "plain";
            meta = { };
            nixos = {
              x = 1;
            };
            includes = [ ];
          };
          ctx = { };
        };
        scopeParent = result.state.scopeParent null;
      in
      {
        den.classes.nixos.description = "NixOS";
        # No child scopes means no child→parent entries beyond the root.
        expr = builtins.length (builtins.attrNames scopeParent) <= 1;
        expected = true;
      }
    );

    # mkScopeId produces different IDs for different contexts, same for same.
    test-scope-id-injectivity = denTest (
      { den, ... }:
      let
        mkScopeId = den.lib.aspects.fx.pipeline.mkScopeId;
        id1 = mkScopeId {
          host = {
            name = "igloo";
          };
        };
        id2 = mkScopeId {
          host = {
            name = "server";
          };
        };
        id3 = mkScopeId {
          host = {
            name = "igloo";
          };
          user = {
            name = "tux";
          };
        };
      in
      {
        expr = {
          different = id1 != id2;
          childDiffers = id1 != id3;
          deterministic =
            id1 == mkScopeId {
              host = {
                name = "igloo";
              };
            };
        };
        expected = {
          different = true;
          childDiffers = true;
          deterministic = true;
        };
      }
    );

    # Scope tree populates scopeParent during entity resolution.
    test-scope-tree-structure = denTest (
      { den, lib, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = den.lib.resolveEntity "host" {
            host = den.hosts.x86_64-linux.igloo;
            system = den.hosts.x86_64-linux.igloo.system;
          };
          ctx = {
            host = den.hosts.x86_64-linux.igloo;
            system = den.hosts.x86_64-linux.igloo.system;
          };
        };
        scopeParent = result.state.scopeParent null;
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.classes.nixos.description = "NixOS";
        den.classes.homeManager.description = "Home Manager";

        # Entity resolution creates child scopes with parent references.
        expr = {
          hasParentEntries = scopeParent != { };
          # Child scopes exist if any scope has a parent (i.e., the tree has depth > 1).
          hasChildScopes = builtins.any (scopeId: scopeParent.${scopeId} != null) (
            builtins.attrNames scopeParent
          );
        };
        expected = {
          hasParentEntries = true;
          hasChildScopes = true;
        };
      }
    );

    # Dynamic trait schema registration works for battery aspects.
    test-dynamic-trait-schema = denTest (
      { den, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = "nixos";
          self = {
            name = "battery-host";
            meta = { };
            nixos = { };
            traits.greeting = {
              collection = "list";
            };
            greeting = [
              "hello"
              "world"
            ];
            includes = [ ];
          };
          ctx = { };
        };
        traitSchemas = result.state.traitSchemas null;
      in
      {
        den.classes.nixos.description = "NixOS";
        expr = {
          registered = traitSchemas ? greeting;
          collection = (traitSchemas.greeting or { }).collection or "unknown";
        };
        expected = {
          registered = true;
          collection = "list";
        };
      }
    );

    # fxResolve without crossEntityTraits still resolves traits correctly.
    test-traits-without-cross-entity = denTest (
      { den, lib, ... }:
      let
        result = den.lib.aspects.fx.pipeline.fxResolve {
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
        mkModuleArgs = {
          inherit lib;
          config = { };
          pkgs = { };
          options = { };
          modulesPath = "";
        };
        traitModule = lib.last result.imports;
        peers = (traitModule mkModuleArgs).config._den.traits.peer;
      in
      {
        den.classes.nixos.description = "NixOS";
        den.traits.peer = {
          description = "Peer hosts";
          collection = "list";
        };

        expr = {
          count = builtins.length peers;
          hasLocal = builtins.any (p: p.ip == "127.0.0.1") peers;
        };
        expected = {
          count = 1;
          hasLocal = true;
        };
      }
    );

  };
}
