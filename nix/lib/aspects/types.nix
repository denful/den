{ lib, den, ... }:
let
  inherit (den.lib) canTake;
  inherit (import ./policy-type.nix { inherit lib; }) policyRegistryType;

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

  # A __contentValues entry holding a parametric function — a function with named
  # args that is not a NixOS module function. Both sites that pull functions out
  # of a content wrapper (providerType.merge here, wrapChild in normalize.nix for
  # includes elements, which listOf hands over unprocessed) must agree on this.
  # lib.functionArgs, not builtins: lib.isFunction admits functor-carrying
  # attrsets, and every merged aspect carries __functor, so the builtin would
  # throw on any aspect reaching here by alias.
  isParametricContent =
    cv:
    lib.isFunction cv.value
    && (
      let
        args = lib.functionArgs cv.value;
      in
      args != { } && !(args ? config) && !(args ? options)
    );

  # A loc can hold non-string segments (module-system placeholders); render those
  # as "<anon>", the same spelling isMeaningfulName rejects.
  locName = loc: lib.concatStringsSep "." (map (x: if builtins.isString x then x else "<anon>") loc);

  isMeaningfulName =
    name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);

  # Two __functor definitions at one path cannot be mechanically composed.
  # Returns the sole functor, or null when there is none.
  soleFunctor =
    loc: defs:
    let
      withFunctor = builtins.filter (
        d: builtins.isAttrs (d.value or null) && (d.value or { }) ? __functor
      ) defs;
    in
    if builtins.length withFunctor > 1 then
      throw "den: multiple __functor definitions at ${locName loc} — merge is ambiguous. Use lib.mkForce to override."
    else if withFunctor != [ ] then
      (lib.head withFunctor).value.__functor
    else
      null;

  # Constructor-stamped names like "<when>" repeat across instances; the
  # child walk indexes them and the gate never keys dedup on them. Both
  # sites must share this predicate or naming and dedup silently desync.
  isSyntheticName = name: lib.hasPrefix "<" name && lib.hasSuffix ">" name;

  # Fold a `_` write into `provides` so both spellings of one provides key
  # are indistinguishable to the two sites that build their own provides
  # view outside the module system.
  #
  # Root must NOT call this: it is a `//` overwrite, whereas root's alias
  # (mkAliasOptionModule, in aspectSubmodule's imports) is priority-preserving
  # and conflict-detecting. Wiring this helper in at root would replace root's
  # genuine conflict error with the same spelling-priority overwrite this fold
  # exists to fix at nested — a regression, not a no-op.
  #
  # A `_` read back off another wrapper carries __functor (the read
  # shorthand, not a write, e.g. `bar._ = otherAspect._;`) and must stay
  # out of provides, matching aspectSubmodule's module-system alias, which
  # only ever sees genuine definitions.
  foldUnderscoreIntoProvides =
    attrs:
    let
      u = if builtins.isAttrs attrs then attrs._ or null else null;
      isWrite = builtins.isAttrs u && !(u ? __functor);
    in
    if isWrite then
      (builtins.removeAttrs attrs [ "_" ]) // { provides = (attrs.provides or { }) // u; }
    else
      attrs;

  # Registries are ambient — populated by battery modules and aspect-schema.nix,
  # and identical at every site that builds a synthetic `_`. Not parameters.
  classReg = den.classes or { };
  pipeReg = den.quirks or { };
  inherit (den.lib.aspects.fx.keyClassification) isStructuralKey;

  # A key names a candidate child aspect when it is neither structural (which
  # covers `__`-prefixed internals by rule), class, nor pipe. Provides children
  # are reached through `provides`/`_`, which are structural, so this alone
  # decides child-key membership — a key held both as a provides child and as a
  # direct key is still a child key, included via its direct value (see
  # mkUnderscore).
  isChildKey = k: !(isStructuralKey k) && !(classReg ? ${k}) && !(pipeReg ? ${k});

  # The synthetic `_`/`provides` aspect, built once for all three shapes an
  # aspect construction can take (declared submodule, functor-carrying
  # battery, nested freeform key). `own` is the aspect's own attrset — it
  # supplies both the child-key domain (`attrNames own`) and the provides
  # source (`own.provides or { }`). `path` is the aspect's dotted position
  # (`chain ++ [ localName ]`), naming the synthetic aspect "<path>._".
  #
  # `_` is a total alias for `provides`: a key held both as a provides child
  # and a direct key is included via its direct value, never excluded for
  # being shadowed — excluding it would make `_` a filtered view of
  # `provides` rather than another spelling of it.
  mkUnderscore =
    own: path:
    let
      # A provides child's NAME lives in a different namespace than the
      # aspect's own top-level keys, so `.provides`/`._` reach every child
      # untouched whatever it is called. Two keys ARE genuine machinery even
      # there: `__`-prefixed (pipeline internals) and `_` — a multi-def
      # nested key merges into a content wrapper carrying
      # `__contentValues`/`__aspectChain`/`_` beside its real children
      # (aspectContentType below), and `_` is the one of those three not
      # already caught by the `__`-prefix rule. `_module` is real NixOS
      # module-system machinery but never reaches `own.provides`'s attrNames
      # (the module system consumes it before freeform merge), so it needs no
      # reservation here.
      providesChildren = lib.filterAttrs (k: _: !(lib.hasPrefix "__" k) && k != "_") (
        own.provides or { }
      );
      # Forwarding a child onto the aspect's own top level is a different
      # question from reaching it through `._`, and it is the one that
      # depends on the construction site. Where the aspect is a declared
      # submodule (mergeWithAspectMeta) every aspect option already has a
      # default, so `merged` wins the `providesChildren // merged` shadow for
      # those names on its own. The two RAW sites — providerType.merge's
      # functor-carrying battery attrset and aspectContentType's nested
      # freeform key — have no submodule and therefore no defaults to win it,
      # so an unreserved child named `name`/`includes`/`meta`/… would land in
      # the aspect's own option position and be read structurally from there.
      # `forwardable` is what those two sites fold, making one user-written
      # shape behave the same at all three: the aspect's own value keeps the
      # top level, the child stays reachable at `._.<name>`.
      #
      # Reserved by the structural registry rather than by the declared-option
      # list, because that registry is what decides own-key dispatch in the
      # first place. It is a superset by two inert names: `into` (declared
      # only on the deprecated den.ctx shim) and anything in user
      # `den.reservedKeys` — both reachable through `._` exactly as the
      # declared options are.
      forwardable = lib.filterAttrs (k: _: !(isStructuralKey k)) providesChildren;
      childKeys = builtins.filter isChildKey (builtins.attrNames own);
      functor = {
        __functor = _self: _args: {
          name = "${lib.concatStringsSep "." path}._";
          includes = map (k: own.${k}) childKeys;
        };
      };
    in
    {
      inherit providesChildren forwardable functor;
      syntheticProvides = providesChildren // functor;
    };

  aspectType =
    typeCfg:
    let
      sub = aspectSubmodule typeCfg;
    in
    sub // { merge = mergeWithAspectMeta typeCfg sub; };

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
        if isParametricWrapper inc then
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
    typeCfg: sub: loc: defs:
    let
      # Rescue explicit __functor from defs before the submodule merge
      # destroys it (freeform keys become deferred modules).
      # Providers like den.batteries.forward define their own __functor.
      originalFunctor = soleFunctor loc defs;
      merged = sub.merge loc (
        defs
        ++ [
          {
            file = (lib.last defs).file;
            value = aspectMeta typeCfg loc defs;
          }
        ]
      );
      # Forward provides children onto the merged aspect so
      # aspect.docker resolves to aspect.provides.docker.
      # provides-first so direct freeform keys on merged take priority.
      # __providesForwarded tells the pipeline to skip these during
      # classification — but only for names the aspect does not define
      # itself. A name held by both loses the forwarded value to the direct
      # key above, so masking it would classify neither: an aspect declaring
      # provides.user alongside user-class content would silently emit no
      # user class at all.
      aspectName = merged.name or (locName loc);
      # __functor hides the synthetic aspect from attrValues while keeping _
      # usable in an includes list: wrapChild sees a zero-arg functor and calls
      # it, so the aspect below is built only when _ is actually included.
      underscore = mkUnderscore merged ((typeCfg.chain or typeCfg.origin) ++ [ aspectName ]);
      inherit (underscore) providesChildren;
      unshadowedProvides = builtins.filter (k: !(merged ? ${k})) (builtins.attrNames providesChildren);
    in
    # __functor makes merged aspects callable (aspect { host = ...; }).
    # Explicit functors (e.g. den.batteries.forward) take priority.
    providesChildren
    // merged
    // {
      __functor = if originalFunctor != null then originalFunctor else resolveAspectWith;
      __providesForwarded = unshadowedProvides;
      provides = underscore.syntheticProvides;
      _ = underscore.syntheticProvides;
    };

  aspectMeta =
    typeCfg: loc: defs:
    { config, ... }:
    {
      meta.name = lib.mkForce (locName config.meta.loc);
      meta.file = lib.mkForce (lib.last defs).file;
      meta.loc = lib.mkForce loc;
      # mkDefault, not mkForce: a declared aspect (root, or one re-typed by
      # providerType.merge's wrapperToAspect) sets its own chain at NORMAL
      # priority, and that must win here so the chain travels with the
      # aspect through re-inclusion the way meta.loc does not — nixpkgs
      # drops a mkDefault def entirely once any normal-priority def exists,
      # so this only ever supplies the value when nothing else does.
      # typeCfg.origin is the container's fixed seed; typeCfg.chain is the
      # threaded definition chain, explicitly nulled for includes elements
      # (aspectSubmodule). `or` only falls back on a MISSING key, so a
      # present-but-null chain bypasses it and this yields null there —
      # absence, not root.
      meta.aspect-chain = lib.mkDefault (typeCfg.chain or typeCfg.origin);
    };

  # A parametric function reaching aspectSubmodule.merge is evaluated as a NixOS
  # module and fails on its own context argument, so def lists handed to the base
  # type pass through here first.
  #
  # The predicate is a parameter because the two callers have different domains.
  # mergeMixed's caller has already split on lib.isFunction, so a functor-carrying
  # attrset is on the function side by construction and must stay coerced. The
  # parametric branch has made no such split: every merged aspect carries
  # __functor, so lib.isFunction there would demote ordinary aspect-valued defs
  # to includes. Only a bare lambda can reach the module system as a module.
  coerceFnDefsWith =
    isFn:
    map (
      d:
      if isFn d.value && !isSubmoduleFn d.value then
        d
        // {
          value = {
            includes = [ d.value ];
          };
        }
      else
        d
    );
  coerceFnDefs = coerceFnDefsWith lib.isFunction;
  coerceBareFnDefs = coerceFnDefsWith builtins.isFunction;

  # Merge branch: mixed function + attrset defs — coerce parametric fns to includes.
  mergeMixed =
    baseType: loc: defs:
    baseType.merge loc (coerceFnDefs defs);

  # Merge branch: all-function defs — submodule fns merge through aspectType,
  # bare parametric fns: single-def returns raw wrapper, multi-def coerces to includes.
  mergeFunctions =
    baseType: typeCfg: loc: defs:
    let
      subFns = builtins.filter (d: isSubmoduleFn d.value) defs;
      paramFns = builtins.filter (d: !isSubmoduleFn d.value) defs;
    in
    if subFns != [ ] then
      baseType.merge loc subFns
    else if builtins.length paramFns == 1 then
      # Single bare parametric fn: return raw wrapper.
      # Avoid baseType.merge here — it triggers a full aspectSubmodule evaluation
      # (module system fixed-point + den.schema.aspect import) which is expensive
      # and causes OOM when applied to every single-def provides child in the tree.
      # The pipeline handles raw wrappers identically via wrapChild normalization.
      let
        fn = (builtins.head paramFns).value;
      in
      if builtins.isAttrs fn then
        # Attrset with __functor (e.g. batteries like import-tree, forward).
        # Forward provides children and add _ alias so aspect._.child and
        # aspect.child both work, matching mergeWithAspectMeta behavior.
        let
          normalizedFn = foldUnderscoreIntoProvides fn;
          aspectName = fn.name or (lib.last loc);
          underscore = mkUnderscore normalizedFn ((typeCfg.chain or typeCfg.origin) ++ [ aspectName ]);
          inherit (underscore) forwardable;
          unshadowedProvides = builtins.filter (k: !(normalizedFn ? ${k})) (builtins.attrNames forwardable);
        in
        forwardable
        // normalizedFn
        // {
          __providesForwarded = unshadowedProvides;
          provides = underscore.syntheticProvides;
          _ = underscore.syntheticProvides;
        }
      else
        let
          args = lib.functionArgs fn;
          nameFromLoc = lib.last loc;
        in
        {
          name = nameFromLoc;
          meta = {
            aspect-chain = typeCfg.chain or typeCfg.origin;
          };
          __fn = fn;
          __args = args;
          __functor = self: self.__fn;
        }
    else
      # Multiple bare parametric fns: coerce each to { includes = [fn]; }, merge
      # through aspectType. paramFns is all-function by construction, so the
      # mixed branch's coercion is the same operation here.
      mergeMixed baseType loc paramFns;

  providerType =
    typeCfg:
    let
      baseType = aspectType typeCfg;
    in
    lib.types.mkOptionType {
      name = "provider";
      description = "aspect or function returning aspect";
      check =
        v:
        builtins.isAttrs v
        || lib.isFunction v
        || (builtins.isList v && builtins.all (i: builtins.isAttrs i && i.__isPolicy or false) v);
      # Content wrappers are expanded into their constituent defs first, so the
      # dispatch below sees one def per definition rather than one per key.
      # Merge dispatch:
      #   policy list → pass through as-is
      #   parametric wrappers (__fn/__args) → sole wrapper with no other defs:
      #     preserve wrapper; otherwise coerce every fn to { includes = [fn]; }
      #   mixed fns + attrsets → coerce parametric fns to { includes = [fn]; }
      #   all fns, has submodule fns → merge through aspectType
      #   all fns, bare parametric only → single: raw wrapper; multi: coerce to includes
      #   multiple __functor defs → error (ambiguous)
      #   all attrsets → merge through aspectType
      merge =
        loc: defs:
        let
          # Normalize __contentValues wrappers (from aspectContentType) that
          # contain parametric functions.  Without this, the wrapper merges
          # through aspectSubmodule and the function is buried as a freeform
          # key.  Extract the function so existing dispatch handles it.
          # Definition position of the value as the author wrote it, read from
          # the ORIGINAL defs: wrapperToAspect below rewrites `name`, and a
          # position read after that points at types.nix rather than the
          # author's file. Two inclusion sites of one let-bound value report
          # ONE position; two separately-written inline literals report two.
          defPosOf =
            v:
            let
              p = if v ? name then builtins.unsafeGetAttrPos "name" v else null;
            in
            if p == null then null else "${toString p.file}:${toString p.line}:${toString p.column}";
          stampDefPos =
            d:
            let
              pos = defPosOf d.value;
            in
            if
              builtins.isAttrs d.value && !(d.value.__isPolicy or false) && !(d.value ? __fn) && pos != null
            then
              d
              // {
                value = d.value // {
                  meta = (d.value.meta or { }) // {
                    __defPos = pos;
                    # The value exactly as the author wrote it, captured before
                    # wrapperToAspect rewrites anything. A position is a token,
                    # not a value: one position carries as many distinct values
                    # as a factory is called times. This is what lets the
                    # registry tell those apart from one value seen twice.
                    __defValue = d.value;
                  };
                };
              }
            else
              d;
          isContentWrapper =
            d:
            builtins.isAttrs d.value
            && (d.value ? __contentValues || d.value ? __aspectChain)
            && !(d.value ? __fn);
          nameFromProvider =
            v:
            let
              prov = v.__aspectChain or [ ];
            in
            if prov != [ ] then lib.last prov else null;
          # A content wrapper holds every definition of its key. Taking one value
          # out of it drops the rest with no diagnostic, so keep the wrapper as a
          # single def and move its parametric definitions into includes, where
          # the pipeline resolves them — the same shape wrapChild produces for an
          # includes element, which listOf hands over without reaching this merge.
          #
          # One def rather than one per definition: the wrapper is the only
          # carrier of __aspectChain, so splitting it leaves the parametric defs
          # nameless. They then resolve to an anonymous per-inclusion identity,
          # which defeats gate dedup and duplicates their content once per path.
          wrapperToAspect =
            d:
            let
              parts = builtins.partition isParametricContent (d.value.__contentValues or [ ]);
              provName = nameFromProvider d.value;
            in
            d
            // {
              value =
                d.value
                # Only narrow what exists: a navigated child carries __aspectChain
                # with no __contentValues, and inventing an empty one here makes
                # the wrapper re-flatten to nothing instead of failing loudly.
                // lib.optionalAttrs (d.value ? __contentValues) { __contentValues = parts.wrong; }
                // lib.optionalAttrs (parts.right != [ ]) {
                  includes = (d.value.includes or [ ]) ++ map (cv: cv.value) parts.right;
                }
                # Preserve identity: inject name and provider chain from
                # __aspectChain so aspectSubmodule.merge produces a meaningful
                # identity instead of an anonymous include index. Fill only
                # what the value does not already carry — an aliased aspect
                # (den.aspects.group.key = den.aspects.other;) owns a
                # meaningful name and chain of its own, and an author's name
                # outranks its position here.
                // lib.optionalAttrs (provName != null) (
                  lib.optionalAttrs (!(d.value ? name) || !(isMeaningfulName d.value.name)) {
                    name = provName;
                  }
                  // lib.optionalAttrs ((d.value.meta.aspect-chain or null) == null) {
                    meta = (d.value.meta or { }) // {
                      aspect-chain = lib.init d.value.__aspectChain;
                    };
                  }
                );
            };
          defs' = map (d: if isContentWrapper d then wrapperToAspect d else d) (map stampDefPos defs);
          listDefs = builtins.filter (d: builtins.isList d.value) defs';
          policyDefs = builtins.filter (d: builtins.isAttrs d.value && d.value.__isPolicy or false) defs';
        in
        # Policy list (from policy.when/policy.for with list input) — pass through as-is.
        if listDefs != [ ] then
          (builtins.head listDefs).value
        else if policyDefs != [ ] then
          let
            p = (builtins.head policyDefs).value;
          in
          p // { name = p.name or (lib.last loc); }
        else
          let
            parametrics = builtins.filter (d: isParametricWrapper d.value) defs';
          in
          if parametrics != [ ] then
            let
              nonParametrics = builtins.filter (d: !isParametricWrapper d.value) defs';
            in
            # Single wrapper with no other defs: return wrapper directly.
            # Avoid baseType.merge here — it triggers a full aspectSubmodule evaluation
            # (module system fixed-point + den.schema.aspect import) which is expensive
            # and causes OOM when applied to every single-def provides child in the tree.
            # The pipeline handles raw wrappers identically via wrapChild normalization.
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
                ++ coerceBareFnDefs nonParametrics
              )
          else
            let
              nonParametrics = builtins.filter (d: !isParametricWrapper d.value) defs';
              # Must fire here as well as in mergeWithAspectMeta: the mixed branch
              # coerces a functor-bearing attrset to { includes = [fn]; }, erasing
              # __functor before the submodule merge could ever see the conflict.
              _functorCheck = soleFunctor loc nonParametrics;
              hasFns = builtins.seq _functorCheck (builtins.any (d: lib.isFunction d.value) nonParametrics);
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
  # Wraps any value (class module, quirk data, function) with provenance metadata.
  # Multi-site definitions are preserved as a list with file attribution.
  # Already-wrapped values (from cross-submodule propagation) are flattened
  # to prevent double-wrapping.
  #
  # Attrset definition values are shallow-merged onto the wrapper so that
  # nested attribute access works (e.g. `gloom.apps.polybar.razermon`).
  # Pipeline consumers use __contentValues for processing; the forwarded
  # attributes are a convenience for direct config access and includes.
  aspectContentType =
    typeCfg:
    lib.types.mkOptionType {
      name = "aspectContent";
      description = "class module, quirk emission, or nested aspect";
      check = _: true;
      merge =
        loc: defs:
        let
          keyName = lib.last loc;
          # Flatten: if a def value is already wrapped, expand its __contentValues
          # instead of nesting another layer.
          #
          # Except once wrapperToAspect has converted it: that keeps the wrapper
          # whole and moves the parametric definitions into includes, so
          # __contentValues no longer lists every definition. Expanding such a
          # value would discard the aspect and the includes with it, leaving only
          # the static half. A raw wrapper has no name and a converted one always
          # does, which is what tells them apart.
          # _ folded into provides here, once, before any per-key merge below
          # sees them: both spellings become defs of the same key, so the
          # existing multi-def merge (deepMerge — recurse attrsets, concat
          # lists, last-wins on scalars) treats them exactly like two defs of
          # `provides` itself, regardless of which spelling each file used.
          flatDefs = map (d: d // { value = foldUnderscoreIntoProvides d.value; }) (
            lib.concatMap (
              d:
              if builtins.isAttrs d.value && d.value ? __contentValues && !(d.value ? name) then
                d.value.__contentValues
              else
                [ { inherit (d) value file; } ]
            ) defs
          );
          # Merge attrset definition values per-key.  Single-def keys are
          # forwarded directly; multi-def attrset keys get a __contentValues
          # wrapper so downstream consumers (emit-classes) collect all
          # definitions.  List-valued keys are concatenated.
          attrVals = builtins.filter builtins.isAttrs (map (d: d.value) flatDefs);
          # Fast path: single attrset def — forward directly, skip per-key merge.
          merged =
            if builtins.length attrVals <= 1 then
              if attrVals == [ ] then { } else builtins.head attrVals
            else
              let
                allKeys = lib.unique (lib.concatMap builtins.attrNames attrVals);
              in
              lib.genAttrs allKeys (
                k:
                let
                  defsForKey = lib.concatMap (
                    cv:
                    if builtins.isAttrs cv.value && cv.value ? ${k} then
                      [
                        {
                          inherit (cv) file;
                          value = cv.value.${k};
                        }
                      ]
                    else
                      [ ]
                  ) flatDefs;
                  allList = builtins.all (d: builtins.isList d.value) defsForKey;
                in
                if builtins.length defsForKey == 1 then
                  (builtins.head defsForKey).value
                else if allList then
                  lib.concatLists (map (d: d.value) defsForKey)
                else
                  let
                    # Forward sub-keys from attrset defs so deeper nested access
                    # works (e.g., den.aspects.root.sub1.sub2.a where sub2 has
                    # multi-def). Deep-merge so sub-keys contributed by several
                    # files all survive for navigation — a shallow `//` drops all
                    # but the last when multiple files each add a different child
                    # under the same nested namespace (e.g. cilium.nix,
                    # hubble-ui.nix and cilium-bgp-resources.nix all defining
                    # children of services.network.cilium). __contentValues
                    # remains the canonical source for emit/forward collection,
                    # so this only affects read-navigation (no double-collection).
                    subAttrVals = builtins.filter builtins.isAttrs (map (d: d.value) defsForKey);
                    # Merge contributions consistently with den's own semantics
                    # (and the module system): colliding attrsets recurse and
                    # colliding lists concatenate, so children contributed by
                    # multiple files all survive. Scalars keep last-def-wins —
                    # genuinely-conflicting scalars are resolved by the real
                    # module merge via __contentValues (which errors without
                    # mkForce), so this navigation view stays total.
                    deepMerge =
                      a: b:
                      a
                      // builtins.mapAttrs (
                        bk: bv:
                        if !(a ? ${bk}) then
                          bv
                        else if builtins.isAttrs a.${bk} && builtins.isAttrs bv then
                          deepMerge a.${bk} bv
                        else if builtins.isList a.${bk} && builtins.isList bv then
                          a.${bk} ++ bv
                        else
                          bv
                      ) b;
                    subForwarded = builtins.foldl' deepMerge { } subAttrVals;
                    provBase = (typeCfg.chain or typeCfg.origin) ++ [
                      keyName
                      k
                    ];
                    annotatedSub = annotateChildren provBase subForwarded;
                  in
                  annotatedSub
                  // {
                    __contentValues = defsForKey;
                    __aspectChain = provBase;
                    _ = underscoreAt provBase annotatedSub;
                  }
              );
          # Single-function content wrappers need __functor so the wrapper is
          # callable (e.g. `den.aspects.wm.gnome-autologin "benjamin"`).
          # Without provides, aspectContentType handles the merge, but the
          # wrapper must still be invocable like the providerType path.
          singleFn = builtins.length flatDefs == 1 && lib.isFunction (builtins.head flatDefs).value;
          # Synthetic ._ for nested aspects — same semantics as root aspects.
          # Forward provides children onto the wrapper so
          # aspect.child.monitoring resolves to aspect.child.provides.monitoring,
          # matching mergeWithAspectMeta behavior for root aspects — including
          # the rule that a name the wrapper defines itself keeps its own value
          # and stays classified.
          # `_` is the write alias for `provides`. aspectSubmodule wires it with
          # mkAliasOptionModule, but a nested key never reaches that submodule —
          # `_` is structural, so an alias write would otherwise arrive here as
          # a plain key of its own. foldUnderscoreIntoProvides already folded
          # every `_` write into `provides` on flatDefs above, so `merged` never
          # carries a `_` key for genuine writes and `merged.provides` alone is
          # the complete source, at every depth.
          provider = (typeCfg.chain or typeCfg.origin) ++ [ keyName ];
          # The synthetic aspect behind ._ at a given tree position — reused
          # unqualified (no providesChildren fold) for every nested position by
          # annotateChildren below; the top-level `provides`/`_` fold
          # providesChildren in explicitly, matching mergeWithAspectMeta.
          underscoreAt = provPath: attrs: (mkUnderscore attrs provPath).functor;
          # Annotate nested attrset children with __aspectChain so deeply nested
          # aspects carry provenance for hasAspect resolution, and give each
          # one its own ._ so the shorthand holds at every depth rather than
          # only at this wrapper. Without the recursion, navigation through a
          # nested key also yields raw children that get anon-renamed per
          # inclusion path and double-emit class content.
          # Name-based guards come first — forcing a registered class value
          # mid-merge can re-enter the flake fixpoint (#580; see isNestedKey);
          # only unregistered namespace keys (forced by navigation anyway) get
          # WHNF'd.
          annotateChildren =
            provPath: attrs:
            lib.mapAttrs (
              k: v:
              let
                childPath = provPath ++ [ k ];
                sub = annotateChildren childPath v;
              in
              if isChildKey k && builtins.isAttrs v && !(v ? __aspectChain) && !(v ? __contentValues) then
                sub
                // {
                  __aspectChain = childPath;
                  _ = underscoreAt childPath sub;
                }
              else
                v
            ) attrs;
          annotatedMerged = annotateChildren provider merged;
          # Both spellings arrive as a content wrapper when the key is defined
          # in more than one file, carrying `__contentValues` / `__aspectChain`
          # / `_` alongside the real children. Those are wrapper machinery, not
          # provides children: unfiltered they surface as `provides` keys and
          # enter `__providesForwarded`. Filtering here covers both, and the
          # single-def path is unaffected because a raw attrset carries none of
          # these keys.
          topUnderscore = mkUnderscore annotatedMerged provider;
          inherit (topUnderscore) forwardable;
          unshadowedProvides = builtins.filter (k: !(annotatedMerged ? ${k})) (
            builtins.attrNames forwardable
          );
        in
        forwardable
        // annotatedMerged
        // {
          __contentValues = flatDefs;
          __aspectChain = provider;
          __providesForwarded = unshadowedProvides;
          # Root aspects publish `provides` and `_` as one value — provides-
          # children plus the all-children functor (mergeWithAspectMeta's
          # syntheticProvides). Match that here so the two spellings are
          # interchangeable for reading as well as writing, at any depth.
          provides = topUnderscore.syntheticProvides;
          _ = topUnderscore.syntheticProvides;
        }
        // lib.optionalAttrs singleFn {
          __functor = _self: (builtins.head flatDefs).value;
        };
    };

  # Unified freeform type for aspect submodules.
  # Dispatches per-key: registered class keys get aspectContentType
  # (provenance wrapper), everything else also gets aspectContentType for now.
  # After provides removal, the else branch switches to providerType so that
  # nested aspects at the freeform level get proper aspect shapes.
  # Registry lookup uses `den.classes or {}` which is populated by battery
  # modules and aspect-schema.nix — no circular dependency because declared
  # option access doesn't trigger freeform merge.
  aspectKeyType =
    typeCfg:
    let
      contentType = aspectContentType typeCfg;
      inherit (den.lib.aspects.fx.keyClassification) isStructuralKey;
    in
    lib.types.mkOptionType {
      name = "aspectKey";
      description = "class module or nested aspect (dispatch by registry)";
      check = _: true;
      # Reserved/structural keys are metadata, not aspect content: pass their
      # value through untouched (last def wins) so consumers read it back as
      # declared. Without this, the content wrapper mangles the value into a
      # __contentValues/__aspectChain shape even though the pipeline ignores the
      # key for dispatch. Everything else gets the provenance/content wrapper.
      merge =
        loc: defs:
        if isStructuralKey (lib.last loc) then (lib.last defs).value else contentType.merge loc defs;
    };

  # Aspect meta submodule type: handleWith, provider, collisionPolicy.
  metaType =
    typeCfg: config:
    lib.types.submodule {
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
      options.aspect-chain = lib.mkOption {
        internal = true;
        visible = false;
        description = "Provider path tracking aspect provenance";
        # NOT listOf: that type accumulates, and a node has exactly one
        # position. Two files defining one aspect path each inject the same
        # chain (providerType.merge, wrapperToAspect), and concatenating them
        # yields ["a" "a"] — a chain every descendant then inherits. Agreeing
        # definitions collapse; genuinely different ones are an ambiguity den
        # cannot resolve, so it says so rather than picking one.
        #
        # null means "no chain set" — distinct from [ ] ("root, chain is
        # empty"). Without this distinction a root aspect and an inline
        # literal both defaulted to [ ] and were indistinguishable. There is
        # no default here: a declared aspect must set its own chain
        # (aspectMeta's mkDefault) rather than inherit one, so the value
        # travels with the aspect through re-inclusion instead of being
        # re-derived at whatever site last merged it.
        type = lib.types.mkOptionType {
          name = "aspectChain";
          description = "aspect provenance chain";
          check = v: v == null || (builtins.isList v && builtins.all builtins.isString v);
          merge =
            loc: defs:
            let
              distinct = lib.unique (map (d: d.value) defs);
              render = c: if c == null then "null" else "[${lib.concatStringsSep " " c}]";
            in
            if distinct == [ ] then
              null
            else if builtins.length distinct == 1 then
              builtins.head distinct
            else
              throw "den: conflicting provenance for ${locName loc}: ${
                lib.concatMapStringsSep " vs " render distinct
              }";
        };
        default = null;
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

  aspectSubmodule =
    typeCfg:
    lib.types.submodule (
      { name, config, ... }:
      let
        # The chain this aspect's children hang off. `meta.aspect-chain` defaults to
        # `typeCfg.chain or typeCfg.origin`, but providerType.merge overrides it when it
        # re-types an included nested aspect (wrapperToAspect injects the chain
        # from __aspectChain). Reading the static typeCfg there truncates the chain
        # to the aspect's own name, so `alpha/tools` and `beta/tools` both hand
        # their children the prefix ["tools"] and the children collide.
        #
        # meta.aspect-chain can be null here (an inline includes literal that
        # never had its own chain filled in). Naming this aspect's own
        # descendants is a separate, computational concern from the chain
        # value itself, so null falls back to [ ] purely for that purpose —
        # this is not a place that reads absence as root.
        ownChain = if config.meta.aspect-chain == null then [ ] else config.meta.aspect-chain;
        childProviderPrefix = ownChain ++ [ config.name ];
      in
      {
        freeformType = lib.types.lazyAttrsOf (
          aspectKeyType (
            typeCfg
            // {
              chain = childProviderPrefix;
            }
          )
        );
        imports = [
          (lib.mkAliasOptionModule [ "_" ] [ "provides" ])
          (den.schema.aspect or { })
        ];
        options = {
          name = lib.mkOption {
            description = "Aspect name";
            default = name;
            type = lib.types.str;
          };
          description = lib.mkOption {
            description = "Aspect description";
            default = "Aspect ${name}";
            type = lib.types.str;
          };
          meta = lib.mkOption {
            description = "Aspect attached meta data";
            type = metaType typeCfg config;
            default = { };
          };
          policies = lib.mkOption {
            description = "Named policy functions — activated by placing in includes.";
            type = policyRegistryType;
            default = { };
          };
          includes = lib.mkOption {
            description = "Providers to ask aspects from";
            # chain explicitly null (not omitted): `or origin` only falls
            # back on a genuinely MISSING key, so a present-but-null chain
            # still yields null through aspectMeta's default. That is what
            # makes an inline includes literal's chain read as "unknown"
            # rather than silently defaulting to the container's origin.
            type = lib.types.listOf (providerType (typeCfg // { chain = null; }));
            default = [ ];
          };
          excludes = lib.mkOption {
            description = "Aspects or policies to exclude from this subtree";
            type = lib.types.listOf (providerType (typeCfg // { chain = null; }));
            default = [ ];
          };
          provides = lib.mkOption {
            description = "Providers of aspect for other aspects";
            default = { };
            type = lib.types.submodule {
              freeformType = lib.types.lazyAttrsOf (
                providerType (
                  typeCfg
                  // {
                    chain = childProviderPrefix;
                  }
                )
              );
            };
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
    aspectKeyType
    providerType
    isParametricWrapper
    isParametricContent
    isSubmoduleFn
    isMeaningfulName
    isSyntheticName
    ;
}
