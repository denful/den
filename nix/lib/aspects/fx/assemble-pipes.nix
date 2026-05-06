# Post-pipeline phase: assemble pipe data from scopedClassImports
# and inject into scope contexts for delivery via wrapClassModule.
{
  lib,
  den,
  ...
}:
let
  pipeRegistry = den.pipes or { };
  pipeNames = builtins.attrNames pipeRegistry;

  # Extract raw quirk value from a pipe entry.
  # Pipe entries are raw emit-class params with __isPipeEntry = true.
  # The actual quirk value is in the `module` field.
  extractValue = entry: entry.module or entry;

  # Auto-flatten list-valued quirk entries.
  # If a quirk value is a list, each element becomes a separate entry.
  flattenAndExtract =
    entries:
    builtins.concatMap (
      entry:
      let
        val = extractValue entry;
      in
      if builtins.isList val then val else [ val ]
    ) entries;

  assemblePipes =
    {
      scopeContexts,
      scopedClassImports,
    }:
    if pipeNames == [ ] then
      scopeContexts
    else
      lib.mapAttrs (
        scopeId: scopeCtx:
        let
          scopeImports = scopedClassImports.${scopeId} or { };
          pipeData = lib.genAttrs pipeNames (
            pipeName:
            let
              rawEntries = scopeImports.${pipeName} or [ ];
            in
            flattenAndExtract rawEntries
          );
        in
        scopeCtx // pipeData
      ) scopeContexts;
in
{
  inherit assemblePipes;
}
