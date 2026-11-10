# mutual-provider's transition default, excluded by each form, with
# user-aspects' default (whose lift also carries provided content) excluded.
{ denTest, lib, ... }:
let
  base = {
    den.internal.transitionDefaults = lib.mkForce true;
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.aspects.tux.provides.to-hosts.nixos.environment.etc.prov.text = "x";
  };
  noUa = den: { den.aspects.igloo.excludes = [ den.batteries.user-aspects ]; };
  form =
    den: f: x:
    if f == "L" then
      { den.aspects.igloo.excludes = [ x ]; }
    else if f == "E" then
      {
        den.aspects.igloo.includes = [
          (den.lib.policy.mkPolicy "ex" ({ host, ... }: [ (den.lib.policy.exclude x) ]))
        ];
      }
    else
      {
        den.schema.host.includes = [
          (den.lib.policy.mkPolicy "ex" ({ host, ... }: [ (den.lib.policy.exclude x) ]))
        ];
      };
in
{
  flake.tests.exclude-forms-mp-parity = {
    test-ctl-mp-default-delivers = denTest (
      { den, igloo, ... }:
      {
        imports = [
          base
          (noUa den)
        ];
        expr = igloo.environment.etc ? prov;
        expected = true;
      }
    );
  }
  // lib.listToAttrs (
    map
      (f: {
        name = "test-mp-${f}";
        value = denTest (
          { den, igloo, ... }:
          {
            imports = [
              base
              (noUa den)
              (form den f den.batteries.mutual-provider)
            ];
            expr = igloo.environment.etc ? prov;
            expected = false;
          }
        );
      })
      [
        "L"
        "E"
        "S"
      ]
  );
}
