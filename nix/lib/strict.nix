{ lib, ... }:
{
  _module.freeformType = lib.mkOptionType {
    name = "strict type";
    typeMerge = _outer: {
      merge =
        path: decls:
        (
          let
            decl = lib.pipe decls [
              lib.head
              (lib.getAttr "value")
              lib.attrsToList
              lib.head
            ];

            kind = if (lib.head path) == "flake" then "flake" else lib.elemAt path 1;
          in
          throw ''
            STRICT MODE

            Attempted to set the option "${decl.name}" in "${lib.join "." path}" but no explicit definition exists. If this wasn't a mistake, disable STRICT mode or configure an option. e.g.

            den.schema.${kind}.options.${decl.name} = lib.mkOption { ... };

            See https://documentation.example
          ''
        );
    };
  };
}
