# Effect handler: resolve
# Entry point for aspect resolution — sends compile with the same payload.
{
  den,
  ...
}:
let
  inherit (den.lib) fx;
in
{
  resolveHandler = {
    "resolve" =
      { param, state }:
      {
        resume = fx.send "compile" param;
        inherit state;
      };
  };
}
