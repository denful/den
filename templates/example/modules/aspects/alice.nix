{
  den,
  lib,
  eg,
  ...
}:
{
  den.aspects.alice = {

    # Alice can include other aspects.
    # For small, private one-shot aspects, use let-bindings like here.
    # for more complex or re-usable ones, define on their own modules,
    # as part of any aspect-subtree.
    includes =
      let
        # hack for nixf linter to keep findFile :/
        unused = den.lib.take.unused __findFile;
        __findFile = unused den.lib.__findFile;

        customEmacs.homeManager =
          { pkgs, ... }:
          {
            programs.emacs.enable = true;
            programs.emacs.package = pkgs.emacs30-nox;
          };
      in
      [
        # from local bindings.
        customEmacs
        # from the aspect tree, cooper example is defined bellow
        den.aspects.cooper
        den.aspects.setHost
        # from the `eg` namespace.
        eg.autologin
        # den included batteries that provide common configs.
        <den/primary-user> # alice is admin always.
        (<den/user-shell> "fish") # default user shell
        # explicit policy activation
        den.aspects.alice.policies.to-igloo
      ];

    # Alice configures NixOS hosts it lives on.
    nixos =
      { pkgs, ... }:
      {
        users.users.alice.packages = [ pkgs.vim ];
      };

    # Alice home-manager.
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.htop ];
      };

    # <user>.policies.<name>, aspect-included policy
    # Delivers NixOS config to the host (cross-scope via policy.provide).
    policies.to-igloo =
      { host, user, ... }:
      lib.optional (host.name == "igloo") (
        den.lib.policy.provide {
          class = "nixos";
          module.programs.nh.enable = true;
        }
      );

  };

  # This is a context-aware aspect, that emits configurations
  # **anytime** at least the `user` data is in context.
  # read more at https://den.oeiuwq.com/explanation/parametric/
  den.aspects.cooper =
    { user, ... }:
    {
      nixos.users.users.${user.userName}.description = "Alice Cooper";
    };

  den.aspects.setHost =
    { host, ... }:
    {
      networking.hostName = host.hostName;
    };
}
