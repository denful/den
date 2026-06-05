{ denTest, ... }:
{
  flake.tests.route-ensure-entry-function = {
    # When a route with adaptArgs and path has no source modules, the
    # ensureEntry placeholder must produce an attrset — not a function.
    # Bug: ensureEntry used (_: { imports = []; }) which is a function value.
    test-empty-route-not-function = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib) policy;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.classes.custom = { };

        den.policies.route-custom = _: [
          (policy.route {
            fromClass = "custom";
            intoClass = "nixos";
            collectSubtree = true;
            path = [ "services" ];
            adaptArgs = _: { };
          })
        ];

        den.schema.host.includes = [
          den.policies.route-custom
        ];

        # No aspects emit into the custom class, so ensureEntry fires.
        # The route should produce an empty attrset at the path, not a function.
        expr = builtins.isAttrs igloo.services;
        expected = true;
      }
    );
  };
}
