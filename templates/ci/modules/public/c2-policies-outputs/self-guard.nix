# `{ self, ... }:` — a policy guard meaning "fire once at my own registration
# scope; never fan to descendant scopes". Distinct from `{ <kind>, ... }:`,
# which fans across every entity of that kind.
#
# `self` is always bound in the dispatch ctx (to the scope's context), so a
# policy can use it even when the scope's own kind isn't a ctx binding — this
# is what lets a flake-scope resolution policy fire, where `{ flake, ... }:`
# could not (flake is not bound in its own ctx).
{ denTest, ... }:
{
  flake.tests.self-guard = {
    # A self-guarded policy is dispatchable and fires at its registration scope.
    test-self-fires-at-registration-scope = denTest (
      {
        den,
        igloo,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.policies.self-fire =
          { self, ... }: [ (include { nixos.environment.variables.DEN_SELF = "fired"; }) ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.self-fire ];
        expr = igloo.environment.variables.DEN_SELF or "no";
        expected = "fired";
      }
    );

    # Registered at the host, `{ self, ... }:` fires once at the host and does
    # NOT fan to the user children — whereas `{ user, ... }:` fans to each user.
    test-self-does-not-fan-to-children = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        # fans: fires once per user, configuring each.
        den.aspects.igloo.policies.fan =
          { user, ... }: [ (include { homeManager.programs.vim.enable = true; }) ];
        # self: fires once at the host scope; its user-targeted bit never lands.
        den.aspects.igloo.policies.self-only =
          { self, ... }: [ (include { homeManager.programs.emacs.enable = true; }) ];
        den.aspects.igloo.includes = [
          den.aspects.igloo.policies.fan
          den.aspects.igloo.policies.self-only
        ];
        expr = {
          tuxVim = tuxHm.programs.vim.enable;
          pinguVim = pinguHm.programs.vim.enable;
          tuxEmacs = tuxHm.programs.emacs.enable or false;
          pinguEmacs = pinguHm.programs.emacs.enable or false;
        };
        expected = {
          tuxVim = true;
          pinguVim = true;
          tuxEmacs = false;
          pinguEmacs = false;
        };
      }
    );
  };
}
