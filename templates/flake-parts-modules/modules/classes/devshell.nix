{ den, inputs, ... }:
let
  inherit (den.lib.policy) resolve;
in
{
  imports = [ inputs.devshell.flakeModule ];
  den.policies.flake-parts-to-flake-parts-system-devshell =
    {
      __entityKind ? null,
      ...
    }:
    if __entityKind != "flake-parts" then
      [ ]
    else
      [
        (resolve.to "flake-parts-system" {
          fromClass = _: "devshell";
          intoPath = _: [
            "devshells"
            "default"
          ];
        })
      ];
}
