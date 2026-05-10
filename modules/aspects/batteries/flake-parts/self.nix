{ withSystem, ... }:
let
  description = ''
    Provides the `flake-parts` `self'` (the flake's `self` with system pre-selected)
    as a top-level module argument.

    This allows modules to access per-system flake outputs without needing
    `pkgs.stdenv.hostPlatform.system`.

    ## Usage

    **Global (Recommended):**
    Apply to all hosts, users, and homes.

        den.default.includes = [ den.batteries.self' ];

    **Specific:**
    Apply only to a specific host, user, or home aspect.

        den.aspects.my-laptop.includes = [ den.batteries.self' ];
        den.aspects.alice.includes = [ den.batteries.self' ];

    **Note:** This aspect is contextual. When included in a `host` aspect, it
    configures `self'` for the host's OS. When included in a `user` or `home`
    aspect, it configures `self'` for the corresponding Home Manager configuration.
  '';

  mkAspect =
    class: system:
    withSystem system (
      { self', ... }:
      {
        ${class}._module.args.self' = self';
      }
    );

  osAspect =
    { host }:
    {
      name = "self'/os";
    }
    // mkAspect host.class host.system;

  userAspect =
    {
      user,
      host,
    }:
    {
      name = "self'/user";
      includes = map (c: mkAspect c host.system) user.classes;
    };

  homeAspect =
    { home }:
    {
      name = "self'/home";
    }
    // mkAspect home.class home.system;
in
{
  den.batteries.self' = {
    name = "self'";
    inherit description;
    includes = [
      osAspect
      userAspect
      homeAspect
    ];
  };
}
