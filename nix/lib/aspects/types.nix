{ lib, den, ... }:
let
  inherit (den.lib) canTake;

  isSubmoduleFn = canTake.upTo {
    lib = true;
    config = true;
    options = true;
  };

  # Aspects are submodules with freeform class keys (nixos, homeManager, etc.)
  # plus structural options (name, meta, includes, provides).
  #
  # Functions with named args (like { host, ... }: { nixos = ...; }) are
  # coerced to { includes = [fn]; } so the fx pipeline resolves them via
  # bind.fn effects. NixOS module functions (taking lib/config/options) are
  # NOT coerced — they're handled by wrapChild's normalizeModuleFn.

  # Duck-typing: any attrset with __fn + __args is treated as a parametric
  # wrapper. The __ prefix convention makes false positives unlikely but
  # not impossible. If explicit tagging is ever needed, add _type = "den:parametric".
  isParametricWrapper = v: builtins.isAttrs v && v ? __fn && v ? __args;

  isMeaningfulName =
    name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);

  aspectType =
    typeCfg:
    let
      sub = aspectSubmodule typeCfg;
    in
    sub // { merge = mergeWithAspectMeta sub; };

  # Resolve parametric includes in an aspect with the given args.
  # Used by __functor so aspects are callable: (aspect { host = ...; }).
  # Directly resolvable includes (__fn/__args wrappers) are called;
  # the result is tagged with __scopeHandlers so the pipeline
  # can resolve remaining parametric children.
  resolveAspectWith =
    self: args:
    let
      inherit (den.lib.aspects.fx.handlers) constantHandler;
      resolveInc =
        inc:
        if builtins.isAttrs inc && inc ? __fn && inc ? __args then
          let
            fn = inc.__fn;
            fnArgs = inc.__args;
            required = builtins.attrNames (lib.filterAttrs (_: v: !v) fnArgs);
            canResolve = builtins.all (k: args ? ${k}) required;
          in
          if canResolve then fn args else inc
        else
          inc;
      resolvedIncludes = map resolveInc (self.includes or [ ]);
    in
    builtins.removeAttrs self [ "_module" ]
    // {
      includes = resolvedIncludes;
      __scopeHandlers = constantHandler args;
    };

  mergeWithAspectMeta =
    sub: loc: defs:
    let
      # Rescue explicit __functor from defs before the submodule merge
      # destroys it (freeform keys become deferred modules).
      # Providers like den.provides.forward define their own __functor.
      explicitFunctors = builtins.filter (
        d: builtins.isAttrs (d.value or null) && (d.value or { }) ? __functor
      ) defs;
      originalFunctor =
        if builtins.length explicitFunctors > 1 then
          throw "den: multiple __functor definitions at ${
            lib.concatStringsSep "." (map (x: if builtins.isString x then x else "<anon>") loc)
          } — merge is ambiguous. Use lib.mkForce to override."
        else if explicitFunctors != [ ] then
          (lib.head explicitFunctors).value.__functor
        else
          null;
      merged = sub.merge loc (
        defs
        ++ [
          {
            file = (lib.last defs).file;
            value = aspectMeta loc defs;
          }
        ]
      );
    in
    # __functor makes merged aspects callable (aspect { host = ...; }).
    # Explicit functors (e.g. den.provides.forward) take priority.
    merged
    // {
      __functor = if originalFunctor != null then originalFunctor else resolveAspectWith;
    };

  aspectMeta =
    loc: defs:
    { config, ... }:
    let
      locSegments = map (x: if builtins.isString x then x else "<anon>") config.meta.loc;
      nameFromLoc = lib.concatStringsSep "." locSegments;
    in
    {
      meta.name = lib.mkForce nameFromLoc;
      meta.file = lib.mkForce (lib.last defs).file;
      meta.loc = lib.mkForce loc;
    };

  # Merge branch: mixed function + attrset defs — coerce parametric fns to includes.
  mergeMixed =
    baseType: loc: defs:
    baseType.merge loc (
      map (
        d:
        if lib.isFunction d.value && !isSubmoduleFn d.value then
          d
          // {
            value = {
              includes = [ d.value ];
            };
          }
        else
          d
      ) defs
    );

  # Merge branch: all-function defs — submodule fns merge through aspectType,
  # bare parametric fns use last-wins.
  mergeFunctions =
    baseType: typeCfg: loc: defs:
    let
      subFns = builtins.filter (d: isSubmoduleFn d.value) defs;
      paramFns = builtins.filter (d: !isSubmoduleFn d.value) defs;
    in
    if subFns != [ ] then
      baseType.merge loc subFns
    else if builtins.length paramFns == 1 then
      # Single bare parametric fn: return raw wrapper (cheap, no submodule eval).
      let
        fn = (builtins.head paramFns).value;
      in
      if builtins.isAttrs fn then
        fn
      else
        let
          args = lib.functionArgs fn;
          nameFromLoc = lib.last loc;
        in
        {
          name = nameFromLoc;
          meta = {
            provider = typeCfg.providerPrefix or [ ];
          };
          __fn = fn;
          __args = args;
          __functor = self: self.__fn;
        }
    else
      # Multiple bare parametric fns: coerce each to { includes = [fn]; }, merge through aspectType.
      baseType.merge loc (
        map (
          d:
          d
          // {
            value = {
              includes = [ d.value ];
            };
          }
        ) paramFns
      );

  providerType =
    typeCfg:
    let
      baseType = aspectType typeCfg;
    in
    lib.types.mkOptionType {
      name = "provider";
      description = "aspect or function returning aspect";
      check = v: builtins.isAttrs v || lib.isFunction v;
      # Merge dispatch:
      #   parametric wrappers (__fn/__args) → last-wins, preserve wrapper
      #   mixed fns + attrsets → coerce parametric fns to { includes = [fn]; }
      #   all fns, has submodule fns → merge through aspectType
      #   all fns, bare parametric only → last-wins, wrap as { __fn, __args }
      #   all attrsets → merge through aspectType
      merge =
        loc: defs:
        let
          parametrics = builtins.filter (d: isParametricWrapper d.value) defs;
        in
        if parametrics != [ ] then
          let
            nonParametrics = builtins.filter (d: !isParametricWrapper d.value) defs;
          in
          # Single wrapper with no other defs: return wrapper directly (cheap, no submodule eval).
          # Multiple wrappers or mixed: coerce __fn to includes, merge through aspectType.
          if builtins.length parametrics == 1 && nonParametrics == [ ] then
            let
              wrapper = (builtins.head parametrics).value;
              nameFromLoc = lib.last loc;
            in
            wrapper // lib.optionalAttrs (!(wrapper ? name) || wrapper.name == "<anon>") { name = nameFromLoc; }
          else
            baseType.merge loc (
              map (
                d:
                d
                // {
                  value = {
                    includes = [ d.value.__fn ];
                  };
                }
              ) parametrics
              ++ nonParametrics
            )
        else
          let
            nonParametrics = builtins.filter (d: !isParametricWrapper d.value) defs;
            hasFns = builtins.any (d: lib.isFunction d.value) nonParametrics;
            hasNonFns = builtins.any (d: !lib.isFunction d.value) nonParametrics;
          in
          if hasFns && hasNonFns then
            mergeMixed baseType loc nonParametrics
          else if hasFns then
            mergeFunctions baseType typeCfg loc nonParametrics
          else
            baseType.merge loc nonParametrics;
    };

  # Generic content wrapper for aspect freeform keys.
  # Wraps any value (class module, trait data, function) with provenance metadata.
  # Multi-site definitions are preserved as a list with file attribution.
  # Already-wrapped values (from cross-submodule propagation) are flattened
  # to prevent double-wrapping.
  aspectContentType =
    typeCfg:
    lib.types.mkOptionType {
      name = "aspectContent";
      description = "class module, trait emission, or nested aspect";
      check = _: true;
      merge =
        loc: defs:
        let
          keyName = lib.last loc;
          # Flatten: if a def value is already wrapped, expand its __contentValues
          # instead of nesting another layer.
          flatDefs = lib.concatMap (
            d:
            if builtins.isAttrs d.value && d.value ? __contentValues then
              d.value.__contentValues
            else
              [ { inherit (d) value file; } ]
          ) defs;
        in
        {
          __contentValues = flatDefs;
          __provider = (typeCfg.providerPrefix or [ ]) ++ [ keyName ];
        };
    };

  aspectSubmodule =
    typeCfg:
    lib.types.submodule (
      { name, config, ... }:
      {
        freeformType = lib.types.lazyAttrsOf (aspectContentType typeCfg);
        imports = [
          (lib.mkAliasOptionModule [ "_" ] [ "provides" ])
          (den.schema.aspect or { })
        ];

        options = {
          name = lib.mkOption {
            description = "Aspect name";
            defaultText = lib.literalExpression "name";
            default = name;
            type = lib.types.str;
          };

          description = lib.mkOption {
            description = "Aspect description";
            defaultText = lib.literalExpression "name";
            default = "Aspect ${name}";
            type = lib.types.str;
          };

          meta = lib.mkOption {
            description = "Aspect attached meta data";
            type = lib.types.submodule {
              freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
              config.self = config;
              options.handleWith = lib.mkOption {
                description = "Resolution handlers for this aspect's subtree";
                type = lib.types.nullOr (
                  lib.types.mkOptionType {
                    name = "handlerValue";
                    description = "handler record or list of handler records";
                    check = v: builtins.isAttrs v || builtins.isList v;
                    merge = _: defs: (lib.last defs).value;
                  }
                );
                default = null;
              };
              options.excludes = lib.mkOption {
                description = "Aspects to exclude from this subtree (sugar for handleWith)";
                type = lib.types.listOf lib.types.unspecified;
                default = [ ];
              };
              options.provider = lib.mkOption {
                internal = true;
                visible = false;
                description = "Provider path tracking aspect provenance";
                type = lib.types.listOf lib.types.str;
                default = typeCfg.providerPrefix or [ ];
              };
              options.collisionPolicy = lib.mkOption {
                description = "Collision policy for flat-form class module arg/module-system arg overlap.";
                type = lib.types.nullOr (
                  lib.types.enum [
                    "error"
                    "class-wins"
                    "den-wins"
                  ]
                );
                default = null;
              };
            };
            defaultText = lib.literalExpression "{ }";
            default = { };
          };

          policies = lib.mkOption {
            description = "Policy names activated when this aspect is the resolution root.";
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };

          includes = lib.mkOption {
            description = "Providers to ask aspects from";
            type = lib.types.listOf (providerType typeCfg);
            defaultText = lib.literalExpression "[ ]";
            default = [ ];
          };

          provides = lib.mkOption {
            description = "Providers of aspect for other aspects";
            defaultText = lib.literalExpression "{ }";
            default = { };
            type = lib.types.submodule {
              freeformType = lib.types.lazyAttrsOf (
                providerType (
                  typeCfg
                  // {
                    providerPrefix = (typeCfg.providerPrefix or [ ]) ++ [ config.name ];
                  }
                )
              );
            };
          };

          traits = lib.mkOption {
            description = "Trait schemas declared by this aspect, merged into den.traits.";
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = { };
          };

          classes = lib.mkOption {
            description = "Class schemas declared by this aspect, merged into den.classes.";
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = { };
          };

        };
      }
    );

  # Coerce non-module functions to { includes = [fn]; } at the aspects level.
  # This is how { host, ... }: { nixos = ...; } becomes a proper aspect
  # with the function as a parametric include for the fx pipeline.
  coercedProviderType =
    typeCfg:
    let
      pt = providerType typeCfg;
    in
    lib.types.coercedTo (lib.types.addCheck lib.types.raw (
      v: builtins.isFunction v && !isSubmoduleFn v && lib.functionArgs v != { }
    )) (fn: { includes = [ fn ]; }) pt;

  aspectsType =
    typeCfg:
    lib.types.submodule { freeformType = lib.types.lazyAttrsOf (coercedProviderType typeCfg); };

in
{
  inherit
    aspectsType
    aspectType
    aspectContentType
    providerType
    isParametricWrapper
    isSubmoduleFn
    isMeaningfulName
    ;
}
