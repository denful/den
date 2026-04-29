# traitCollectorHandler: Handles emit-trait — collects trait data into state.traits/deferredTraits.
#   Tier 1: plain value → collect immediately
#   Tier 2: function with only den context args → resolve with ctx, collect
#   Tier 3: function with module-system args → defer
# traitArgHandler: Handles <trait-name> effects — resumes with collected trait data for parametric consumers.
#   State reads: traits, consumedTraits
#   State writes: consumedTraits
{
  lib,
  den,
  ...
}:
let
  # Module-system args that indicate Tier 3 (deferred).
  moduleSysArgs = lib.genAttrs [
    "config"
    "lib"
    "pkgs"
    "options"
    "modulesPath"
  ] (_: true);

  isModuleSysArg = name: moduleSysArgs ? ${name} || lib.hasPrefix "_module" name;

  # Detect tier for a trait value.
  # Returns: { tier = 1|2|3; value = <resolved or raw>; }
  detectTier =
    ctx: value:
    if !builtins.isFunction value then
      {
        tier = 1;
        inherit value;
      }
    else
      let
        args = builtins.functionArgs value;
        argNames = builtins.attrNames args;
      in
      # { ... }: with no named args → conservative Tier 3
      if argNames == [ ] then
        {
          tier = 3;
          inherit value;
        }
      else
        let
          hasModuleSys = builtins.any isModuleSysArg argNames;
        in
        if hasModuleSys then
          {
            tier = 3;
            inherit value;
          }
        else
          let
            allInCtx = builtins.all (k: ctx ? ${k}) argNames;
          in
          if allInCtx then
            # All args are den context args → Tier 2, resolve now
            {
              tier = 2;
              value = value (lib.getAttrs argNames ctx);
            }
          else
            # Args not in ctx and not module-system → conservative Tier 3
            {
              tier = 3;
              inherit value;
            };

  # Apply collection strategy when collecting trait data.
  # "list" → concat lists
  # "map" → merge attrsets with duplicate key error
  collectTrait =
    {
      strategy,
      traitName,
      existing,
      newValue,
    }:
    if strategy == "map" then
      let
        # Both existing and newValue should be attrsets for map collection
        existingAttrs = if builtins.isAttrs existing then existing else { };
        newAttrs = if builtins.isAttrs newValue then newValue else { ${traitName} = newValue; };
        duplicates = builtins.filter (k: existingAttrs ? ${k}) (builtins.attrNames newAttrs);
      in
      if duplicates != [ ] then
        throw "den: trait '${traitName}' map collection: duplicate keys: ${builtins.concatStringsSep ", " duplicates}"
      else
        existingAttrs // newAttrs
    else
      # "list" (default) — concat
      let
        existingList = if builtins.isList existing then existing else [ ];
        newList = if builtins.isList newValue then newValue else [ newValue ];
      in
      existingList ++ newList;

  traitCollectorHandler =
    {
      ctx,
      traitSchemas ? { },
    }:
    {
      "emit-trait" =
        { param, state }:
        let
          traitName = param.trait;
          rawValue = param.value;
          schema = traitSchemas.${traitName} or { };
          strategy = schema.collection or "list";
          tierInfo = detectTier ctx rawValue;
        in
        if tierInfo.tier == 3 then
          # Defer — store raw function for module-system resolution
          let
            deferred = (state.deferredTraits or (_: { })) null;
            existing = deferred.${traitName} or [ ];
          in
          {
            resume = null;
            state = state // {
              deferredTraits =
                _:
                deferred
                // {
                  ${traitName} = existing ++ [
                    {
                      value = rawValue;
                      chain = param.chain or "<unknown>";
                    }
                  ];
                };
              scopedDeferredTraits =
                _:
                let
                  all = state.scopedDeferredTraits null;
                  scope = state.currentScope;
                  scopeData = all.${scope} or { };
                  existingScoped = scopeData.${traitName} or [ ];
                in
                all
                // {
                  ${scope} = scopeData // {
                    ${traitName} = existingScoped ++ [
                      {
                        value = rawValue;
                        chain = param.chain or "<unknown>";
                      }
                    ];
                  };
                };
            };
          }
        else
          # Tier 1 or 2 — collect immediately
          let
            traits = (state.traits or (_: { })) null;
            existing = traits.${traitName} or (if strategy == "map" then { } else [ ]);
            collected = collectTrait {
              inherit strategy traitName existing;
              newValue = tierInfo.value;
            };
          in
          {
            resume = null;
            state = state // {
              traits =
                _:
                traits
                // {
                  ${traitName} = collected;
                };
              scopedTraits =
                _:
                let
                  all = state.scopedTraits null;
                  scope = state.currentScope;
                  scopeData = all.${scope} or { };
                  existingScoped = scopeData.${traitName} or (if strategy == "map" then { } else [ ]);
                  collectedScoped = collectTrait {
                    inherit strategy traitName;
                    existing = existingScoped;
                    newValue = tierInfo.value;
                  };
                in
                all
                // {
                  ${scope} = scopeData // {
                    ${traitName} = collectedScoped;
                  };
                };
            };
          };
    };

  # One handler per trait name. When bind.fn resolves `{ traitName, ... }:`,
  # it sends the trait name as an effect. This handler responds with
  # collected data and tracks consumption.
  # Accepts full trait schemas so collection strategy determines empty default.
  traitArgHandler =
    traitSchemas:
    builtins.mapAttrs (
      traitName: schema:
      { param, state }:
      let
        traits = (state.traits or (_: { })) null;
        strategy = if builtins.isAttrs schema then schema.collection or "list" else "list";
        emptyDefault = if strategy == "map" then { } else [ ];
        traitData = traits.${traitName} or emptyDefault;
        consumed = (state.consumedTraits or (_: { })) null;
      in
      {
        resume = traitData;
        state = state // {
          consumedTraits =
            _:
            consumed
            // {
              ${traitName} = true;
            };
          scopedConsumedTraits =
            _:
            let
              all = state.scopedConsumedTraits null;
              scope = state.currentScope;
            in
            all
            // {
              ${scope} = (all.${scope} or { }) // {
                ${traitName} = true;
              };
            };
        };
      }
    ) traitSchemas;

in
{
  inherit
    traitCollectorHandler
    traitArgHandler
    detectTier
    collectTrait
    ;
}
