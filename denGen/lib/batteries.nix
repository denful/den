# Inner module pre-declaring battery aspects (design-gen.md §4; content ASSUMED from Den docs).
denGen: {
  batteries.module = {
    aspects.primary-user.user = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" ];
    };
  };
}
