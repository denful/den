# Bob: secondary user on devbox with a different desktop environment.
# Deliberately simpler than alice — no cross-provides, no home-level
# roles. Shows how the multi-user policy-seq view distinguishes which
# aspects belong to which user.
{ den, ... }:
{
  den.aspects.bob = {
    includes = [
      den.batteries.primary-user
      den.aspects.gnome
      den.aspects.dev-tools
    ];
    nixos =
      { ... }:
      {
        users.users.bob.isNormalUser = true;
      };
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.firefox ];
      };
  };
}
