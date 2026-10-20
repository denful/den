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
        name = user;
        home = "/home/${user}";
        isNormalUser = true;
      };
    # shortcut: hosts option has no hostName, so the host name is used; add hostName option when a fleet overrides it.
    aspects.hostname.nixos =
      { host, ... }:
      {
        networking.hostName = host;
      };
  };
}
