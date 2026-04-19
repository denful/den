{ den, lib, ... }:
let
  inherit (den.lib) parametric;

  description = ''
    Projects all `user.classes` like `homeManager` from the host's aspect tree
    onto users who opt in. Requires the fx pipeline.

    ## Usage

      den.aspects.tux.includes = [ den._.host-aspects ];

    Any host aspect that defines a `homeManager` key will have that
    config forwarded to the user's homeManager evaluation. Other host-class
    keys (nixos, darwin) are ignored — host.aspect is resolved
    specifically for `user.classes`.
  '';

  from-host =
    { host, user }:
    lib.listToAttrs (
      map (class: {
        name = class;
        value = den.lib.aspects.resolve class (parametric.fixedTo { inherit host user; } host.aspect);
      }) user.classes
    );

in
{
  den.provides.host-aspects = parametric.exactly {
    inherit description;
    includes = [ from-host ];
  };
}
