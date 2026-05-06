# Effect handler: classify
# Partitions aspect keys into class keys and nested keys via classifyKeys.
{
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.keyClassification) classifyKeys;
in
{
  classifyHandler = {
    "classify" =
      { param, state }:
      let
        classified = classifyKeys param.targetClass param.aspect;
      in
      {
        resume = {
          classKeys = classified.classKeys ++ classified.unregisteredClassKeys;
          inherit (classified) nestedKeys pipeKeys;
        };
        inherit state;
      };
  };
}
