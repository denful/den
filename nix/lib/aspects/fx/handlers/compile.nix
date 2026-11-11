# Effect handler: compile
# Shape router — dispatches to compile-* based on aspect shape.
{
  den,
  ...
}:
let
  inherit (den.lib) fx;
in
{
  compileHandler = {
    "compile" =
      { param, state }:
      let
        meta = param.aspect.meta or { };
        effect =
          if meta ? __forward then
            "compile-forward"
          else if meta ? guard then
            "compile-conditional"
          else if param.aspect ? __fn || (param.aspect.__args or { }) != { } then
            "compile-parametric"
          else
            "compile-static";
      in
      {
        resume = fx.send effect param;
        inherit state;
      };
  };
}
