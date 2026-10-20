# Tier-1 R2/R3 assertions (no nix-unit available): ci/run.sh prints the result attrset; every value must be true.
{ denGen, nixpkgsLib }:
let
  den = denGen.evalDen [ (
    { ... }:
    {
      hosts.x86_64-linux.igloo.users.tux.classes = [ "user" ];
      aspects.igloo.nixos = { };
      aspects.tux = {
        includes = [ den.batteries.primary-user ];
        user.extraGroups = [ "audio" ];
      };
    }
  ) ];
  names = map (a: a.name);
  cl = den.lib.closure den.aspects.tux;
  ms = den.lib.userModules "igloo" "tux";
  # stub of nixpkgs' users.users so list merge order is the real module-system order
  eval =
    mods:
    (nixpkgsLib.evalModules {
      modules = [
        {
          options.users.users = nixpkgsLib.mkOption {
            type = nixpkgsLib.types.attrsOf (
              nixpkgsLib.types.submodule {
                options.extraGroups = nixpkgsLib.mkOption { type = nixpkgsLib.types.listOf nixpkgsLib.types.str; default = []; };
                options.isNormalUser = nixpkgsLib.mkOption { type = nixpkgsLib.types.bool; default = false; };
              }
            );
          };
        }
      ] ++ mods;
    }).config.users.users.tux;
  # O2: hostname + define-user batteries, evaluated against a stub of the nixos options they set
  d2 = denGen.evalDen [ (
    { ... }:
    {
      hosts.x86_64-linux.igloo.users.tux.classes = [ "user" ];
      hosts.x86_64-linux.x.users = { };
      aspects.igloo.includes = [ d2.batteries.hostname ];
      aspects.x.includes = [ d2.batteries.hostname ];
      aspects.tux.includes = [ d2.batteries.define-user ];
    }
  ) ];
  stub =
    host:
    (nixpkgsLib.evalModules {
      modules = [
        {
          options.networking.hostName = nixpkgsLib.mkOption { type = nixpkgsLib.types.str; default = "unset"; };
          options.users.users = nixpkgsLib.mkOption {
            type = nixpkgsLib.types.attrsOf (
              nixpkgsLib.types.submodule {
                options.home = nixpkgsLib.mkOption { type = nixpkgsLib.types.str; default = ""; };
                options.name = nixpkgsLib.mkOption { type = nixpkgsLib.types.str; default = ""; };
                options.isNormalUser = nixpkgsLib.mkOption { type = nixpkgsLib.types.bool; default = false; };
              }
            );
          };
        }
      ] ++ (denGen.route d2.aspects host [ "tux" ]).modules;
    }).config;
  O2set = {
    O2host = (stub "igloo").networking.hostName == "igloo";
    O2home = (stub "igloo").users.users.tux.home == "/home/tux";
    O2neg = (stub "x").networking.hostName == "igloo"; # control: MUST be false
  };
in
{
  T5 = names cl == [ "tux" "primary-user" ];
  T6 = map (m: (eval [ m ]).extraGroups) ms == [ [ "audio" ] [ "wheel" "networkmanager" ] ];
  T2 = (eval ms).extraGroups == [ "audio" "wheel" "networkmanager" ];
  T2neg = (eval ms).extraGroups == [ "wheel" "networkmanager" "audio" ]; # control: MUST be false
  T3 = (eval ms).isNormalUser;
  # DFS membership == model membership: closure is model-filtered DFS, so compare to reachability by name
  T9 = builtins.sort builtins.lessThan (names cl) == [ "primary-user" "tux" ];
  N5 = names (den.lib.closure den.aspects.primary-user) == [ "primary-user" ];
  O2home = O2set.O2home;

}
