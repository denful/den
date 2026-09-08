{ denTest, ... }:
let
  # Two axes crossed: WHICH ARG defers (policy-enrichment vs pipe) x WHERE the
  # function sits (named aspect vs inline lambda at the includes position) x
  # WHAT the body holds (direct class content vs nested includes).
  fixture = den: {
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.quirks.firewall.description = "Firewall port declarations";

    den.policies.host-guards =
      { host, ... }: [ (den.lib.policy.resolve { isNixos = host.class == "nixos"; }) ];
    den.default.includes = [ den.policies.host-guards ];

    den.aspects.igloo = {
      firewall.ports = [ 22 ];
      includes = [
        den.aspects.named-enrich-direct
        den.aspects.named-pipe-direct
        (
          { isNixos, ... }:
          {
            name = "inline-enrich-direct";
            nixos.networking.firewall.allowedTCPPorts = [ 10130 ];
          }
        )
        (
          { firewall, ... }:
          {
            name = "inline-pipe-direct";
            nixos.networking.firewall.allowedTCPPorts = [ 10140 ];
          }
        )
        den.aspects.named-enrich-nested
        den.aspects.named-pipe-nested
        den.aspects.static-pipe-class-fn
      ];
    };

    den.aspects.named-enrich-direct =
      { isNixos, ... }:
      {
        nixos.networking.firewall.allowedTCPPorts = [ 10110 ];
      };
    den.aspects.named-pipe-direct =
      { firewall, ... }:
      {
        nixos.networking.firewall.allowedTCPPorts = [ 10120 ];
      };
    den.aspects.named-enrich-nested =
      { isNixos, ... }:
      {
        includes = [ den.aspects.enrich-nested-leaf ];
      };
    den.aspects.named-pipe-nested =
      { firewall, ... }:
      {
        includes = [ den.aspects.pipe-nested-leaf ];
      };
    den.aspects.enrich-nested-leaf.nixos.networking.firewall.allowedTCPPorts = [ 10150 ];
    den.aspects.pipe-nested-leaf.nixos.networking.firewall.allowedTCPPorts = [ 10160 ];

    # The shape the corpus already uses for pipe args: a STATIC aspect whose
    # class-key VALUE is the pipe-arg function.
    den.aspects.static-pipe-class-fn.nixos =
      { firewall, ... }:
      {
        networking.firewall.allowedTCPPorts = [ 10170 ];
      };
  };

  arm =
    port:
    denTest (
      { den, igloo, ... }:
      (fixture den)
      // {
        expr = builtins.elem port igloo.networking.firewall.allowedTCPPorts;
        expected = true;
      }
    );
in
{
  flake.tests.d1matrix = {
    test-named-enrich-direct = arm 10110;
    test-named-pipe-direct = arm 10120;
    test-inline-enrich-direct = arm 10130;
    test-inline-pipe-direct = arm 10140;
    test-named-enrich-nested = arm 10150;
    test-named-pipe-nested = arm 10160;
    test-static-pipe-class-fn = arm 10170;

    test-negcontrol-undeclared-port = denTest (
      { den, igloo, ... }:
      (fixture den)
      // {
        expr = builtins.elem 19999 igloo.networking.firewall.allowedTCPPorts;
        expected = false;
      }
    );
  };
}
