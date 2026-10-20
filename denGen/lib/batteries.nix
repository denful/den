# Inner module pre-declaring battery aspects (design-gen.md §4; content ASSUMED from Den docs).
denGen: {
  batteries.module = { config, ... }: let withSystem = config._module.args.withSystem; in {
    aspects.primary-user.user = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" ];
    };
    # `user` class = users.users.<user> (route.userPart flattens it with {host,user}); nixos-class fns are not arg-bound (see report).
    # shortcut: nixos/user part only (no HM/darwin host in fleet yet); add home.username/homeDirectory when one appears.
    aspects.define-user.user =
      { user, ... }:
      {
        name = user.userName;
        home = "/home/${user.userName}";
        isNormalUser = true;
      };
    aspects.define-user.homeManager =
      { user, ... }:
      let n = user.userName or user.name; in
      {
        home.username = n;
        home.homeDirectory = "/home/${n}";
      };
    aspects.hostname.nixos =
      { host, ... }:
      {
        networking.hostName = host.hostName;
      };
    # inputs'/self' via flake-parts withSystem; system from the bound host/user/home entity.
    aspects."inputs'".homeManager = { user, ... }: { _module.args."inputs'" = withSystem (user.system or user.host.system) (ps: ps."inputs'"); };
    aspects."inputs'".nixos = { host, ... }: { _module.args."inputs'" = withSystem host.system (ps: ps."inputs'"); };
    aspects."self'".homeManager = { user, ... }: { _module.args."self'" = withSystem (user.system or user.host.system) (ps: ps."self'"); };
    aspects."self'".nixos = { host, ... }: { _module.args."self'" = withSystem host.system (ps: ps."self'"); };
  };
}
