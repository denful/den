# Tier-1 R2/R3 assertions (no nix-unit available): ci/run.sh prints the result attrset; every value must be true.
{ denGen, nixpkgsLib }:
let
  den = denGen.evalDen (
    { ... }:
    {
      hosts.x86_64-linux.igloo.users.tux.classes = [ "user" ];
      aspects.igloo.nixos = { };
      aspects.tux = {
        includes = [ den.batteries.primary-user ];
        user.extraGroups = [ "audio" ];
      };
    }
  );
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
}
