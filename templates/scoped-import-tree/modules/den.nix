{ inputs, den, ... }:
{
  # we can import this flakeModule even if we dont have flake-parts as input!
  imports = [ inputs.den.flakeModule ];

  den.hosts.x86_64-linux.igloo.users.tux = {
    classes = [ "user" ]; # no homeManager
  };

  den.aspects.igloo = {
    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.hello ];

        # USER TODO: remove this
        boot.loader.grub.enable = false;
        fileSystems."/".device = "/dev/null";
        fileSystems."/".fsType = "auto";
      };
  };

  den.aspects.tux = {
    includes = [ den.batteries.primary-user ];
    user.extraGroups = [ "audio" ];
  };

  # REMOVE: Exposed to test that we have scope values from scoped.nix
  flake.did-scoped = {
    # test that policy is directly in scope
    hasPolicyWhen = policy ? when;

    # den's __findFile is in scope and can find config.den.aspects.*
    hasBrackets = <igloo> ? nixos;

    # libs from inputs
    inherit pipe bend ned;
  };

}
