{ den, lib, ... }:
let
  description = ''
    Projects all `user.classes` like `homeManager` from the host's aspect tree
    onto users who opt in. Requires the fx pipeline.

    ## Usage

      den.aspects.tux.includes = [ den.batteries.host-aspects ];

    Any host aspect that defines a `homeManager` key will have that
    config forwarded to the user's homeManager evaluation. Other host-class
    keys (nixos, darwin) are ignored — host.aspect is resolved
    specifically for `user.classes`.
  '';

  from-host =
    { host, user }:
    let
      # Tag host.aspect with user context so parametric includes like
      # { user }: ... can resolve during host-aspects re-resolution.
      ctx = { inherit host user; };
      scopeHandlers = den.lib.aspects.fx.handlers.constantHandler ctx;
      aspectWithCtx = host.aspect // {
        __scopeHandlers = scopeHandlers;
      };
    in
    {
      name = "host-aspects/${user.userName}@${host.name}";
    }
    // lib.genAttrs (user.classes or [ "homeManager" ]) (
      class: den.lib.aspects.resolveImports class aspectWithCtx
    );
in
{
  den.batteries.host-aspects = {
    name = "host-aspects";
    inherit description;
    includes = [ from-host ];
  };
}
