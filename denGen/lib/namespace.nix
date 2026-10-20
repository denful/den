# den.namespace name sources -> module (guides/namespaces.mdx): `name` module arg + `name.<x>` definitions are aspects under `den.aspects.<name>.provides`.
# sources: upstream flakes' `denful.<name>` merged in; `true` exports `flake.denful.<name>`.
denGen: {
  namespace =
    name: sources:
    { lib, config, ... }:
    let
      srcs = if builtins.isList sources then sources else [ sources ];
      up = map (s: s.denful.${name} or { }) (builtins.filter builtins.isAttrs srcs);
    in
    {
      options.${name} = lib.mkOption {
        default = { };
        type = lib.mkOptionType {
          name = "denGenNamespace";
          merge = _: defs: builtins.foldl' (a: d: lib.recursiveUpdate a d.value) { } defs;
        };
      };
      config = {
        ${name} = builtins.foldl' lib.recursiveUpdate { } up;
        den.aspects.${name}.provides = config.${name};
        _module.args.${name} = config._module.args.den.aspects.${name}.provides;
        flake.denful.${name} = lib.mkIf (builtins.elem true srcs || sources == true) config.${name};
      };
    };
}
