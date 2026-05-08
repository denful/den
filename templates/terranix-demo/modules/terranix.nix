# Terranix integration: terranix as an entity kind.
#
# Each host gets a terranix entity child scope. applyInstantiates
# collects terranix class modules from the host subtree and calls
# terranixConfiguration, placing the result at packages.<system>.<host>-tf.
{
  den,
  inputs,
  lib,
  ...
}:
let
  inherit (den.lib.policy) resolve;
in
{
  den.classes.terranix = { };

  den.policies.host-to-terranix =
    { host, system, ... }:
    [
      (den.lib.policy.instantiate {
        name = "${host.name}-tf";
        class = "terranix";
        instantiate =
          { modules, ... }: inputs.terranix.lib.terranixConfiguration { inherit system modules; };
        intoAttr = [
          "terranixConfigurations"
          "${host.name}"
        ];
        sourceScopeId = null;
      })
    ];

  den.schema.host.includes = [ den.policies.host-to-terranix ];
}
