# Battery: expose lib, inputs, and den to aspect pipeline functions.
# Users opt in via: den.default.includes = [ den.batteries.flake-scope ];
#
# Values use pipelineOnly (collisionPolicy = "class-wins") so that
# class-module-native values (e.g., NixOS _module.args.lib) win silently.
{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.policy) resolve pipelineOnly;
in
{
  den.batteries.flake-scope = {
    name = "flake-scope";
    description = "Expose lib, inputs, and den to aspect pipeline functions.";
    policies.den-flake-scope = _: [
      (resolve {
        lib = pipelineOnly lib;
        inputs = pipelineOnly inputs;
        den = pipelineOnly den;
      })
    ];
    includes = [
      den.batteries.flake-scope.policies.den-flake-scope
    ];
  };
}
