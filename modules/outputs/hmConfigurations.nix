{ lib, den, ... }:
let
  hmFwd =
    { home, ... }:
    den.provides.forward {
      each = lib.optional (home.intoAttr != [ ]) true;
      fromClass = _: home.class;
      intoClass = _: "flake";
      intoPath = _: [ "flake" ];
      fromAspect = _: home.resolved;
      mapModule =
        _: module:
        lib.setAttrByPath home.intoAttr (
          home.instantiate {
            pkgs = home.pkgs;
            modules = [ module ];
          }
        );
    };
in
{
  den.aspects.flake-hm = hmFwd;
}
