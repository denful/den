# Defines `hasAspect` on every entity that imports den.schema.conf
# (host, user, home, and user-defined kinds). Flake-level module:
# the outer closure captures config.den so the inner entity submodule
# can reach den.lib.aspects.mkEntityHasAspect at entity-eval time.
{ lib, config, ... }:
let
  inherit (config) den;

  entityModule =
    { config, ... }:
    {
      options.hasAspect = lib.mkOption {
        description = ''
          Query whether an aspect is structurally present in this entity's
          resolved aspect tree.

          Usage:
            host.hasAspect <facter>                         # primary class
            host.hasAspect.forClass "nixos" <facter>        # explicit class
            host.hasAspect.forAnyClass <facter>             # union across classes

          Safe to call from inside class-config module bodies
          (`nixos = ...`, `homeManager = ...`) and from lazy positions
          inside aspect functor bodies. NOT safe to use for deciding an
          aspect's `includes` list — that's cyclic; use meta.adapter +
          excludeAspect / oneOfAspects for structural decisions instead.
        '';
        internal = true;
        visible = false;
        readOnly = true;
        type = lib.types.raw;
        defaultText = lib.literalMD "Computed from `config.resolved` and the entity's class/classes.";
        default =
          let
            # Prefer `classes` (list), fall back to `[class]`, else error.
            classes =
              config.classes or (
                if config ? class then
                  [ config.class ]
                else
                  throw "den.schema.conf.hasAspect: entity has no `class` or `classes`"
              );
            primaryClass =
              if classes == [ ] then
                throw "den.schema.conf.hasAspect: entity has empty `classes` list"
              else
                lib.head classes;
            # Lazy thunk throwing at call time (not attribute access), so
            # entity.hasAspect / .forClass / .forAnyClass can be referenced
            # safely by tooling and only fire when actually invoked.
            err = throw (
              "hasAspect: ${config.name or "<unnamed entity>"} has no config.resolved "
              + "(no matching den.schema.<kind> defined)."
            );
          in
          if config ? resolved then
            den.lib.aspects.mkEntityHasAspect {
              tree = config.resolved;
              inherit primaryClass classes;
            }
          else
            {
              __functor = _: _: err;
              forClass = _: _: err;
              forAnyClass = _: err;
            };
      };
    };
in
{
  config.den.schema.conf.imports = [ entityModule ];
}
