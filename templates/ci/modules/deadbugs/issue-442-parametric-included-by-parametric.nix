# Parametric aspects included by parametric aspects are not applied.
# When a named parametric aspect (context-destructuring fn) includes another
# named parametric aspect, the coercedProviderType wraps both into
# { includes = [fn]; __functor = defaultFunctor; }. mapIncludes was skipping
# includes that have __functor, so the inner parametric fn never received
# user/host context and its config was silently dropped.
# https://github.com/denful/den/issues/442
{ denTest, ... }:
{
  flake.tests.deadbugs-issue-442 = {

    # Exact reproducer from the issue: parametric dev includes parametric git.
    test-parametric-aspect-included-by-parametric-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.git =
          { user, ... }:
          {
            nixos =
              { ... }:
              {
                programs.git.enable = true;
              };
          };

        den.aspects.dev =
          { user, ... }:
          {
            includes = [
              den.aspects.git
            ];
          };

        den.aspects.tux = {
          includes = [
            den.aspects.dev
          ];
        };

        expr = igloo.programs.git.enable;
        expected = true;
      }
    );

    # Three-deep chain: static -> parametric -> parametric -> parametric.
    test-triple-nested-parametric-includes = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.shell =
          { user, ... }:
          {
            nixos =
              { ... }:
              {
                programs.zsh.enable = true;
              };
          };

        den.aspects.dev =
          { user, ... }:
          {
            includes = [ den.aspects.shell ];
            nixos =
              { ... }:
              {
                programs.git.enable = true;
              };
          };

        den.aspects.role =
          { user, ... }:
          {
            includes = [ den.aspects.dev ];
          };

        den.aspects.tux = {
          includes = [ den.aspects.role ];
        };

        expr = {
          git = igloo.programs.git.enable;
          zsh = igloo.programs.zsh.enable;
        };
        expected = {
          git = true;
          zsh = true;
        };
      }
    );

  };
}
