# Inner module pre-declaring battery aspects (design-gen.md §4; content ASSUMED from Den docs).
denGen: {
  batteries.module = {
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
    aspects.hostname.nixos =
      { host, ... }:
      {
        networking.hostName = host.hostName;
      };
  };
}
