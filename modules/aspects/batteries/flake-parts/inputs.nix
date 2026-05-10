{ withSystem, ... }:
let
  description = ''
    Provides the `flake-parts` `inputs'` (the flake's `inputs` with system pre-selected)
    as a top-level module argument.

    This allows modules to access per-system flake outputs without needing
    `pkgs.stdenv.hostPlatform.system`.

    ## Usage

    **Global (Recommended):**
    Apply to all hosts, users, and homes.

        den.default.includes = [ den.batteries.inputs' ];

    **Specific:**
    Apply only to a specific host, user, or home aspect.

        den.aspects.my-laptop.includes = [ den.batteries.inputs' ];
        den.aspects.alice.includes = [ den.batteries.inputs' ];

    **Note:** This aspect is contextual. When included in a `host` aspect, it
    configures `inputs'` for the host's OS. When included in a `user` or `home`
    aspect, it configures `inputs'` for the corresponding Home Manager configuration.
  '';

  mkAspect =
    class: system:
    withSystem system (
      { inputs', ... }:
      {
        ${class}._module.args.inputs' = inputs';
      }
    );

  osAspect =
    { host }:
    {
      name = "inputs'/os";
    }
    // mkAspect host.class host.system;

  userAspect =
    {
      user,
      host,
    }:
    {
      name = "inputs'/user";
      includes = map (c: mkAspect c host.system) user.classes;
    };

  hmAspect =
    { home }:
    {
      name = "inputs'/home";
    }
    // mkAspect home.class home.system;

in
{
  den.batteries.inputs' = {
    name = "inputs'";
    inherit description;
    includes = [
      osAspect
      userAspect
      hmAspect
    ];
  };
}
