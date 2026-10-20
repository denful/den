# Inner surface: hosts + aspects at ROOT. includes elems must be refs to declared aspects.
denGen: {
  view =
    let
      inherit (denGen) gen;
      t = denGen.genLib.types;
      cat = category: builtins.mapAttrs (_: _: { inherit category; });
      cnf = {
        keySemantics = cat "class" {
          nixos = null;
          user = null;
          homeManager = null;
        };
      };
      mkAspects =
        decl:
        let
          isRef = b: (decl.aspects.${b.name}.key or null) == b.key;
          authored =
            name: e: k: _:
            let
              c = gen.aspects.keyCategory cnf k;
            in
            if c == null then
              throw "den: aspect `${name}`: key `${k}` is not a declared class"
            else
              c == "class" && gen.aspects.hasClassContent e.${k};
          norm =
            name: e:
            e
            // {
              inherit name;
              includes = gen.prelude.imap0 (
                i: b:
                if isRef b then
                  b
                else
                  throw "den: aspect `${name}`: includes[${toString i}] is not a ref to a declared aspect"
              ) e.includes;
              # forces key validation (N2)
              content = gen.prelude.filterAttrs (authored name e) e;
            };
        in
        builtins.mapAttrs norm decl.aspects;
    in
    {
      inherit mkAspects;
      module =
        { lib, config, ... }:
        {
          options.hosts = lib.mkOption {
            type = t.lazyAttrsOf (
              t.lazyAttrsOf (
                t.submodule (
                  { name, ... }:
                  {
                    # schema.host.imports (e.g. fleet addr/environment options) extend the entity.
                    imports = config.schema.host.imports;
                    options.name = lib.mkOption { type = t.str; default = name; };
                    options.hostName = lib.mkOption { type = t.str; default = name; };
                    options.class = lib.mkOption { type = t.str; default = "nixos"; };
                    options.users = lib.mkOption {
                      type = t.lazyAttrsOf (
                        t.submodule (
                          { name, ... }:
                          {
                            imports = config.schema.user.imports;
                            options.name = lib.mkOption { type = t.str; default = name; };
                            options.userName = lib.mkOption { type = t.str; default = name; };
                            options.classes = lib.mkOption {
                              type = t.listOf t.str;
                              default = [ ];
                            };
                          }
                        )
                      );
                      default = { };
                    };
                  }
                )
              )
            );
            default = { };
          };
          options.aspects = lib.mkOption {
            type = gen.aspects.aspectsType cnf;
            default = { };
          };
          # den.default is an aspect: same type as aspects.<n>, then walked as aspects.default.
          options.default = lib.mkOption {
            type = gen.aspects.aspectType cnf;
            default = { };
          };
          config.aspects.default = config.default;
          # shortcut: raw, no semantics yet; later rungs type these.
          options.schema = lib.mkOption {
            type = t.lazyAttrsOf (
              t.submodule {
                freeformType = t.lazyAttrsOf t.raw;
                options =
                  let
                    rawList = lib.mkOption { type = t.listOf t.raw; default = [ ]; };
                  in
                  {
                    imports = rawList;
                    includes = rawList;
                    excludes = rawList;
                    classes = lib.mkOption { type = t.listOf t.str; default = [ ]; };
                    isEntity = lib.mkOption { type = t.bool; default = false; };
                  };
              }
            );
            default = { };
          };
          # consumers read schema.host/user unconditionally
          config.schema.host = { };
          config.schema.user = { };
          options.policies = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          options.quirks = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          options.systems = lib.mkOption { type = t.listOf t.str; default = [ ]; };
        };
    };
}
