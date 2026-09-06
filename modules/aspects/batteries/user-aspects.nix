{ den, lib, ... }:
let
  description = ''
    Projects all `host.class`es like `nixos` from the user's aspect tree onto
    hosts that opt in. Requires the fx pipeline.

    ## Usage

      den.aspects.igloo.includes = [ den.batteries.user-aspects ];

    Any user aspect that defines a `host.class` key will have that config
    forwarded to the hosts's evaluation.
  '';

  from-user =
    { host, user, ... }: [ (den.lib.policy.spawn { classes = [ host.class ]; }) ];
in
{
  den.batteries.user-aspects = {
    name = "user-aspects";
    inherit description;
    includes = [
      {
        __isPolicy = true;
        name = "user-aspects-project";
        fn = from-user;
      }
    ];
  };
}
