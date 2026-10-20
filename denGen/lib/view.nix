# Inner surface: hosts + aspects at ROOT. includes elems must be refs to declared aspects.
denGen: {
  view =
    let
      inherit (denGen) gen;
      t = denGen.genLib.types;
      cat = category: builtins.mapAttrs (_: _: { inherit category; });
      cnfOf = c: {
        # quirk names are channel keys (quirks never depend on aspects: no cycle)
        keySemantics =
          cat "class" { nixos = null; darwin = null; user = null; homeManager = null; }
          // cat "class" c.classes
          // cat "channel" c.quirks;
      };
      mkAspects =
        decl:
        let
          cnf = cnfOf decl;
          # nested aspects (Den aspects.mdx:19; gen-aspects "A key with no entry is a nested aspect") are
          # addressed by name `<parent>/<key>`; resolved by path so the world's key set never forces aspect bodies.
          kids = e: builtins.filter (k: gen.aspects.keyCategory cnf k == null && builtins.isAttrs e.${k}) (builtins.attrNames e);
          at = n: builtins.foldl' (e: s: e.${s} or { }) decl.aspects (if decl.aspects ? ${n} then [ n ] else builtins.filter builtins.isString (builtins.split "/" n));
          isRef = b: (at b.name).key or null == b.key;
          authored =
            name: e: k: _:
            let
              c = gen.aspects.keyCategory cnf k;
            in
            if k == "excludes" then
              false
            else if c == null then
              # nested aspect: own entry, its content lands only if included
              if builtins.isAttrs e.${k} then false else throw "den: aspect `${name}`: key `${k}` is not a declared class and not a nested aspect"
            else
              c == "class" && gen.aspects.hasClassContent e.${k};
          norm =
            name: e:
            e
            // builtins.listToAttrs (map (k: { name = k; value = norm "${name}/${k}" e.${k}; }) (kids e))
            // {
              inherit name;
              policyIncs = builtins.filter (p: !builtins.any (x: builtins.isAttrs x && (x.__isPolicy or false) && x.name == p.name) (e.excludes or [ ])) (decl.aspectPolicies.${name} or [ ]);
              includes = gen.prelude.imap0 (
                i: b:
                if isRef b then
                  b
                else
                  throw "den: aspect `${name}`: includes[${toString i}] is not a ref to a declared aspect"
              ) e.includes;
              # policy elements (attrs/functions without an aspect name) are not aspect refs: not closure-excluded here
              excludes = builtins.filter (b: builtins.isAttrs b && b ? name && b ? key && isRef b) (
                gen.prelude.imap0 (
                  i: b:
                  if builtins.isString b then
                    throw "den: aspect `${name}`: excludes[${toString i}] is not of type aspect or function returning aspect (is not of type `aspect or function returning aspect')"
                  else
                    b
                ) (e.excludes or [ ])
              );
              # forces key validation (N2)
              content = gen.prelude.filterAttrs (authored name e) e;
              # unset channel keys surface as null; only authored emissions count
              quirks = gen.prelude.filterAttrs (k: v: v != null && gen.aspects.keyCategory cnf k == "channel") e;
            };
          normed = builtins.mapAttrs norm decl.aspects;
        in
        normed;
    in
    {
      inherit mkAspects cnfOf;
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
                    # open by default (entities.mdx:183-192); schema.host.isStrict closes it
                    freeformType = if config.schema.host.isStrict then null else t.lazyAttrsOf t.raw;
                    imports = config.schema.host.imports ++ [ (denGen.schema.entity config.schema.host) ];
                    options.name = lib.mkOption { type = t.str; default = name; };
                    options.hostName = lib.mkOption { type = t.str; default = name; };
                    options.intoAttr = lib.mkOption { type = t.listOf t.str; default = [ "nixosConfigurations" name ]; };
                    options.class = lib.mkOption { type = t.str; default = "nixos"; };
                    options.users = lib.mkOption {
                      type = t.lazyAttrsOf (
                        t.submodule (
                          { name, ... }:
                          {
                            freeformType = t.lazyAttrsOf t.raw;
                            imports = config.schema.user.imports ++ [ (denGen.schema.entity config.schema.user) ];
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
            type = gen.aspects.aspectsType (cnfOf config);
            default = { };
          };
          # den.default is an aspect: same type as aspects.<n>, then walked as aspects.default.
          options.default = lib.mkOption {
            type = gen.aspects.aspectType (cnfOf config);
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
                    isStrict = lib.mkOption { type = t.bool; default = false; };
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
          # builtins are named atoms so schema.<kind>.excludes can reference them (reference/policies.mdx:293-297)
          config.policies = lib.genAttrs [ "flake-to-systems" "system-to-os-outputs" "system-to-hm-outputs" "host-to-users" ] (n: { __builtin = n; });
          options.aspectPolicies = lib.mkOption { type = t.lazyAttrsOf (t.listOf t.raw); default = { }; };
          options.policyRecs = lib.mkOption { type = t.lazyAttrsOf (t.lazyAttrsOf t.raw); default = { }; };
          options.rawFns = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          options.quirks = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          options.classes = lib.mkOption { type = t.lazyAttrsOf t.raw; default = { }; };
          options.homes = lib.mkOption { type = t.lazyAttrsOf (t.lazyAttrsOf t.raw); default = { }; };
          options.systems = lib.mkOption { type = t.listOf t.str; default = [ ]; };
        };
    };
}
