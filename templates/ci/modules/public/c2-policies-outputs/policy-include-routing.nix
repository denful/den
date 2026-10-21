{ denTest, ... }:
{
  flake.tests.policy-include-routing = {

    # A policy value in includes registers and fires at entity boundary.
    test-policy-in-includes-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          includes = [
            {
              __isPolicy = true;
              name = "enrich-test";
              fn =
                { host, ... }:
                [
                  (den.lib.policy.resolve { testEnriched = true; })
                ];
            }
          ];
        };

        den.aspects.uses-enrichment =
          { testEnriched }:
          {
            nixos.networking.hostName = if testEnriched then "enriched" else "not";
          };

        den.default.includes = [ den.aspects.uses-enrichment ];

        expr = igloo.networking.hostName;
        expected = "enriched";
      }
    );

    # Regular aspect alongside policy in includes both work.
    test-mixed-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.regular-aspect = {
          nixos.environment.variables.FROM_ASPECT = "yes";
        };

        den.aspects.igloo = {
          includes = [
            {
              __isPolicy = true;
              name = "mixed-enrich";
              fn =
                { host, ... }:
                [
                  (den.lib.policy.resolve { mixedFlag = true; })
                ];
            }
            den.aspects.regular-aspect
          ];
        };

        expr = igloo.environment.variables.FROM_ASPECT;
        expected = "yes";
      }
    );

    # A list of policy values (from policy.when with list input) gets each registered.
    test-policy-list-in-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          includes = [
            [
              {
                __isPolicy = true;
                name = "list-pol-a";
                fn =
                  { host, ... }:
                  [
                    (den.lib.policy.resolve { fromA = true; })
                  ];
              }
              {
                __isPolicy = true;
                name = "list-pol-b";
                fn =
                  { host, ... }:
                  [
                    (den.lib.policy.resolve { fromB = true; })
                  ];
              }
            ]
          ];
        };

        den.aspects.check-both =
          { fromA, fromB }:
          {
            nixos.environment.variables.BOTH = if fromA && fromB then "yes" else "no";
          };

        den.default.includes = [ den.aspects.check-both ];

        expr = igloo.environment.variables.BOTH;
        expected = "yes";
      }
    );

    # Policy from den.policies.* placed directly in includes.
    test-den-policies-in-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.policies.direct-include-pol =
          { host, ... }:
          [
            (den.lib.policy.resolve { directIncluded = true; })
          ];

        den.aspects.igloo = {
          includes = [ den.policies.direct-include-pol ];
        };

        den.aspects.check-direct =
          { directIncluded }:
          {
            nixos.environment.variables.DIRECT = if directIncluded then "yes" else "no";
          };

        den.default.includes = [ den.aspects.check-direct ];

        expr = igloo.environment.variables.DIRECT;
        expected = "yes";
      }
    );

  };
}
