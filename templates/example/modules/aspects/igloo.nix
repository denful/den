{ den, lib, ... }:
{
  den.aspects.igloo = {
    # igloo host provides some home-manager defaults to its users.
    homeManager.programs.direnv.enable = true;

    # NixOS configuration for igloo.
    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.hello ];
      };

    # <host>.policies.<name>, aspect-included policy
    policies.to-alice =
      { host, user, ... }:
      lib.optional (user.name == "alice") (
        den.lib.policy.include {
          homeManager.programs.tmux.enable = user.name == "alice";
        }
      );

    includes = [ den.aspects.igloo.policies.to-alice ];
  };
}
