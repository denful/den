{ den, lib, ... }:
let
  forwardItem =
    {
      item,
      guard ? null,
      adaptArgs ? null,
      adapterModule ? null,
      evalConfig ? false,
      ...
    }@fwd:
    let
      fromClass = fwd.fromClass item;
      classForwardTo = (den.classes.${fromClass} or { }).forwardTo or null;
      intoClass =
        if fwd ? intoClass then
          fwd.intoClass item
        else if classForwardTo != null then
          classForwardTo.class
        else
          throw "forward: no intoClass for fromClass=${fromClass}";
      intoPath =
        if fwd ? intoPath then
          fwd.intoPath item
        else if classForwardTo != null then
          classForwardTo.path or [ ]
        else
          [ ];
      mapModule = (fwd.mapModule or (_: lib.id)) item;

      intoPathArgs = if lib.isFunction intoPath then lib.functionArgs intoPath else { };
      intoPathFn = if lib.isFunction intoPath then intoPath else _: intoPath;
      staticIntoPath = if lib.isFunction intoPath then [ ] else intoPath;

      rawAspect = if fwd ? fromAspect then fwd.fromAspect item else item.resolved or item;
      sourceAspect =
        if fwd ? fromCtx && builtins.isAttrs rawAspect && !(builtins.isFunction rawAspect) then
          let
            ctx = fwd.fromCtx item;
            inherit (den.lib.aspects.fx.handlers) constantHandler;
          in
          rawAspect
          // {
            __scopeHandlers = (rawAspect.__scopeHandlers or { }) // constantHandler ctx;
          }
        else
          rawAspect;

      freeformMod = {
        config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
      };

      adapterMods = [
        freeformMod
        (
          if lib.isFunction adapterModule then
            adapterModule item
          else if builtins.isAttrs adapterModule then
            adapterModule
          else
            { }
        )
      ];

      adapterKey = lib.concatStringsSep "/" (
        [
          fromClass
          intoClass
        ]
        ++ staticIntoPath
      );

      guardArgs = if guard == null then { } else lib.functionArgs guard;
      guardFn =
        if guard == null then
          _: lib.id
        else
          args:
          let
            res = guard args;
          in
          if lib.isFunction res then
            res item
          else
            assert builtins.isBool res;
            lib.optionalAttrs res;

      adaptArgsFn =
        args:
        if adaptArgs == null then
          args
        else
          let
            res = adaptArgs args;
          in
          if lib.isFunction res then res item else res;
      adaptArgv = if adaptArgs == null then { } else lib.functionArgs adaptArgs;

      extraArgsFor = args: builtins.removeAttrs (adaptArgsFn args) (builtins.attrNames args);
      canDirectImport = adapterModule == null;

      needsAdapter =
        guard != null || adaptArgs != null || adapterModule != null || builtins.isFunction intoPath;
      needsTopLevelAdapter = needsAdapter && intoPath == [ ];
    in
    {
      includes = [ ];
      meta.__forward = {
        inherit
          fromClass
          intoClass
          evalConfig
          freeformMod
          sourceAspect
          mapModule
          staticIntoPath
          needsAdapter
          needsTopLevelAdapter
          adapterKey
          guardFn
          guardArgs
          intoPathArgs
          intoPathFn
          adaptArgsFn
          adaptArgv
          adapterMods
          extraArgsFor
          canDirectImport
          ;
      };
    };

  forwardEach = fwd: {
    includes = map (item: forwardItem (fwd // { inherit item; })) fwd.each;
  };

in
{
  inherit forwardEach forwardItem;
}
