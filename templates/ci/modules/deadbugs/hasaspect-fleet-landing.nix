# In-context `hasAspect` and the finalized query (den.lib.__hasLandedAspect)
# read the fleet landing index: what lands in each entity's own evaluation, as
# the flake builds it. These cells take an entity kind above the host
# (`environment`, as a fleet topology declares one), sibling hosts, class
# variants and laziness. Every expectation comes from the markers that land.
{ denTest, lib, ... }:
let
  b = v: if v then "T" else "f";
  one = s: lib.concatStringsSep "," (lib.unique (lib.splitString "\n" s));

  envTopology =
    transition:
    { den, ... }:
    let
      inherit (den.lib.policy) resolve instantiate;
    in
    {
      den.internal.transitionDefaults = lib.mkForce transition;
      den.schema.environment.isEntity = true;
      den.schema.host.parent = "environment";
      den.schema.user.classes = [ "homeManager" ];
      den.schema.flake-system.excludes = [ den.policies.system-to-os-outputs ];
      den.policies.test-env-walk =
        { system, ... }:
        [
          (resolve.to "environment" {
            environment = {
              name = "prod";
              aspect = den.aspects.prod-env;
            };
          })
        ];
      den.policies.test-env-to-host =
        { environment, ... }:
        lib.concatMap (
          host:
          lib.optionals (host.intoAttr != [ ]) [
            (resolve.to "host" { inherit host; })
            (instantiate host)
          ]
        ) (builtins.attrValues (den.hosts.x86_64-linux or { }));
      den.schema.flake-system.includes = [ den.policies.test-env-walk ];
      den.schema.environment.includes = [ den.policies.test-env-to-host ];
      den.aspects.prod-env.nixos = { };
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [ den._.define-user ];
      den.hosts.x86_64-linux.igloo.users = {
        tux = { };
        pingu = { };
      };
    };

  probeX = {
    nixos.environment.etc."mark-x".text = "x";
    homeManager.home.file."mark-x".text = "x";
  };

  # Host and user readers of `ref`, from a host nixos module and tux's home.
  readers =
    ref:
    { den, ... }:
    {
      den.default.includes = [
        {
          nixos =
            { host, ... }:
            {
              environment.etc."r-host".text = b (host.hasAspect (ref den));
            };
          homeManager =
            { host, user, ... }:
            {
              home.file."r-host".text = b (host.hasAspect (ref den));
              home.file."r-user".text = b (user.hasAspect (ref den));
            };
        }
      ];
    };

  # Lands in igloo / in tux's home, and each reader's answer, including the
  # finalized query for the host and for tux below it.
  observe =
    den: igloo: ref:
    let
      etc = igloo.environment.etc;
      hm = igloo.home-manager.users.tux.home.file;
      h = den.hosts.x86_64-linux.igloo;
      tux = h.users.tux;
    in
    {
      got = {
        hostFromHost = one (etc."r-host".text or "-");
        hostFromTux = hm."r-host".text or "-";
        userFromTux = hm."r-user".text or "-";
        lateHost = b (den.lib.__hasLandedAspect { entity = h; } (ref den));
        lateTux = b (
          den.lib.__hasLandedAspect {
            entity = tux;
            within.host = h;
          } (ref den)
        );
      };
      want =
        let
          lh = b (etc ? "mark-x");
          lt = b (hm ? "mark-x");
        in
        {
          hostFromHost = lh;
          hostFromTux = lh;
          userFromTux = lt;
          lateHost = lh;
          lateTux = lt;
        };
      lands = [
        (etc ? "mark-x")
        (hm ? "mark-x")
      ];
    };

  envCell =
    transition: delivery: lands:
    denTest (
      { den, igloo, ... }:
      let
        o = observe den igloo (d: d.aspects.probeX);
      in
      {
        imports = [
          (envTopology transition)
          (readers (d: d.aspects.probeX))
          delivery
        ];
        den.aspects.probeX = probeX;
        expr = {
          inherit (o) lands;
          wrong = builtins.attrNames (lib.filterAttrs (k: v: o.got.${k} != v) o.want);
        };
        expected = {
          inherit lands;
          wrong = [ ];
        };
      }
    );

  # igloo includes probeX and reads it; iceberg's aspect is `poison`.
  siblingPoison =
    poison:
    { den, ... }:
    {
      imports = [ (readers (d: d.aspects.probeX)) ];
      den.schema.user.classes = [ "homeManager" ];
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [ den._.define-user ];
      den.hosts.x86_64-linux = {
        igloo.users.tux = { };
        iceberg.users.tux = { };
      };
      den.aspects.probeX = probeX;
      den.aspects.igloo.includes = [ den.aspects.probeX ];
      den.aspects.iceberg = poison;
    };

  both = name: mk: {
    "test-end-state-${name}" = mk false;
    "test-transition-${name}" = mk true;
  };
in
{
  flake.tests.hasaspect-fleet-landing =

    # A host-scope include that needs the ancestor's context fires only in the
    # fleet walk; X lands in igloo's nixos, not in tux's home.
    both "env-context-host-include" (
      transition:
      envCell transition
        (
          { den, ... }:
          {
            den.schema.host.includes = [
              (
                { environment, host, ... }:
                {
                  includes = [ den.aspects.probeX ];
                }
              )
            ];
          }
        )
        [
          true
          false
        ]
    )

    # The environment's `provides.to-users`: X lands in igloo and in tux's home.
    // both "env-provides-to-users" (
      transition:
      envCell transition
        (
          { den, ... }:
          {
            den.aspects.prod-env.provides.to-users.includes = [ den.aspects.probeX ];
          }
        )
        [
          true
          true
        ]
    )

    # The host's own include, under the same topology.
    // both "env-topology-host-includes" (
      transition:
      envCell transition
        (
          { den, ... }:
          {
            den.aspects.igloo.includes = [ den.aspects.probeX ];
          }
        )
        [
          true
          false
        ]
    )

    # The environment's aspect excludes X that igloo includes. The exclusion
    # doesn't reach the host's own include, so X lands in igloo, and every
    # reader agrees with where it lands.
    // both "env-excludes" (
      transition:
      envCell transition
        (
          { den, ... }:
          {
            den.aspects.igloo.includes = [ den.aspects.probeX ];
            den.aspects.prod-env.excludes = [ den.aspects.probeX ];
          }
        )
        [
          true
          false
        ]
    )

    // {
      # The answer reaches a binding the class module takes as its own
      # argument; a `host` the include function binds is the walk's. X comes
      # from the environment's provides.to-users and lands in igloo.
      test-argument-vs-captured-binding = denTest (
        { den, igloo, ... }:
        {
          imports = [ (envTopology false) ];
          den.aspects.probeX = probeX;
          den.aspects.prod-env.provides.to-users.includes = [ den.aspects.probeX ];
          den.aspects.igloo.includes = [
            {
              nixos =
                { host, ... }:
                {
                  environment.etc."r-arg".text = b (host.hasAspect den.aspects.probeX);
                };
            }
            (
              { host, ... }:
              {
                nixos.environment.etc."r-captured".text = b (host.hasAspect den.aspects.probeX);
              }
            )
          ];
          expr = {
            lands = b (igloo.environment.etc ? "mark-x");
            arg = igloo.environment.etc."r-arg".text;
            captured = one igloo.environment.etc."r-captured".text;
          };
          expected = {
            lands = "T";
            arg = "T";
            captured = "f";
          };
        }
      );

      # A sibling host's include doesn't reach igloo's answers, and iceberg's own
      # answer is true.
      test-sibling-host-no-leak = denTest (
        { den, config, ... }:
        let
          cfg = h: config.flake.nixosConfigurations.${h}.config.environment.etc;
        in
        {
          imports = [ (readers (d: d.aspects.probeX)) ];
          den.schema.user.classes = [ "homeManager" ];
          den.default.homeManager.home.stateVersion = "25.11";
          den.default.includes = [ den._.define-user ];
          den.hosts.x86_64-linux = {
            igloo.users.tux = { };
            iceberg.users.tux = { };
          };
          den.aspects.probeX = probeX;
          den.aspects.iceberg.includes = [ den.aspects.probeX ];
          expr = {
            igloo = [
              (cfg "igloo")."r-host".text
              (b ((cfg "igloo") ? "mark-x"))
              (b (den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.probeX))
            ];
            iceberg = [
              (cfg "iceberg")."r-host".text
              (b ((cfg "iceberg") ? "mark-x"))
            ];
          };
          expected = {
            igloo = [
              "f"
              "f"
              "f"
            ];
            iceberg = [
              "T"
              "T"
            ];
          };
        }
      );

      # The class variants answer per class: X has only homeManager content and
      # lands in tux's home, so tux has it for homeManager and igloo has it for
      # no class it declares.
      test-class-variants = denTest (
        { den, igloo, ... }:
        let
          h = den.hosts.x86_64-linux.igloo;
          tux = h.users.tux;
          late = den.lib.__hasLandedAspect {
            entity = tux;
            within.host = h;
          };
          lateHost = den.lib.__hasLandedAspect { entity = h; };
          ref = den.aspects.homeOnly;
        in
        {
          den.schema.user.classes = [ "homeManager" ];
          den.default.homeManager.home.stateVersion = "25.11";
          den.default.includes = [ den._.define-user ];
          den.hosts.x86_64-linux.igloo.users.tux = { };
          den.aspects.homeOnly.homeManager.home.file."mark-h".text = "h";
          den.aspects.tux.includes = [
            den.aspects.homeOnly
            den.aspects.reader
          ];
          den.aspects.reader.homeManager =
            { host, user, ... }:
            {
              home.file."r".text = lib.concatStrings (
                map b [
                  (user.hasAspect.forClass "homeManager" ref)
                  (user.hasAspect.forClass "nixos" ref)
                  (user.hasAspect.forAnyClass ref)
                  (host.hasAspect.forClass "nixos" ref)
                  (host.hasAspect.forAnyClass ref)
                ]
              );
            };
          expr = {
            inContext = igloo.home-manager.users.tux.home.file."r".text;
            late = map b [
              (late.forClass "homeManager" ref)
              (late.forClass "nixos" ref)
              (lateHost.forClass "nixos" ref)
              (lateHost.forAnyClass ref)
            ];
            lands = igloo.home-manager.users.tux.home.file ? "mark-h";
          };
          expected = {
            inContext = "TfTff";
            late = [
              "T"
              "f"
              "f"
              "f"
            ];
            lands = true;
          };
        }
      );

      # A class reader answers without forcing an option that throws when read,
      # or a sibling host whose configuration throws.
      test-reader-stays-lazy = denTest (
        { den, igloo, ... }:
        {
          imports = [ (readers (d: d.aspects.probeX)) ];
          den.schema.user.classes = [ "homeManager" ];
          den.default.homeManager.home.stateVersion = "25.11";
          den.default.includes = [ den._.define-user ];
          den.hosts.x86_64-linux = {
            igloo.users.tux = { };
            iceberg.users.tux = { };
          };
          den.aspects.probeX = probeX;
          den.aspects.igloo.includes = [ den.aspects.probeX ];
          den.aspects.igloo.nixos.options.trap = lib.mkOption {
            default = throw "den-test: trap option forced";
          };
          den.aspects.iceberg.nixos = _: throw "den-test: sibling configuration forced";
          expr = one igloo.environment.etc."r-host".text;
          expected = "T";
        }
      );

      # What a target query forces on a sibling host: igloo's in-context read
      # and the finalized query for igloo, with iceberg poisoned. An option
      # value or module body iceberg defines is never forced; an include
      # iceberg's walk evaluates is. The fleet walk evaluates every host's
      # includes to build any host, so that include fails igloo's build with
      # no query too.
      test-sibling-option-poison-not-forced = denTest (
        { den, igloo, ... }:
        {
          imports = [
            (siblingPoison { nixos.environment.etc."poison".text = throw "den-test: sibling option forced"; })
          ];
          expr = [
            (one igloo.environment.etc."r-host".text)
            (b (den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.probeX))
          ];
          expected = [
            "T"
            "T"
          ];
        }
      );
      test-sibling-module-body-poison-not-forced = denTest (
        { den, igloo, ... }:
        {
          imports = [ (siblingPoison { nixos = _: throw "den-test: sibling module body forced"; }) ];
          expr = [
            (one igloo.environment.etc."r-host".text)
            (b (den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.probeX))
          ];
          expected = [
            "T"
            "T"
          ];
        }
      );
      test-sibling-include-poison-forced-in-context = denTest (
        { igloo, ... }:
        {
          imports = [ (siblingPoison { includes = [ (_: throw "den-test: sibling include forced") ]; }) ];
          expr = one igloo.environment.etc."r-host".text;
          expectedError = {
            type = "ThrownError";
            msg = "den-test: sibling include forced";
          };
        }
      );
      test-sibling-include-poison-fails-the-build-without-a-query = denTest (
        { den, igloo, ... }:
        {
          den.hosts.x86_64-linux = {
            igloo.users.tux = { };
            iceberg.users.tux = { };
          };
          den.aspects.igloo.nixos.environment.etc."plain".text = "p";
          den.aspects.iceberg.includes = [ (_: throw "den-test: sibling include forced") ];
          expr = igloo.environment.etc."plain".text;
          expectedError = {
            type = "ThrownError";
            msg = "den-test: sibling include forced";
          };
        }
      );
      test-sibling-include-poison-forced-finalized = denTest (
        { den, ... }:
        {
          imports = [ (siblingPoison { includes = [ (_: throw "den-test: sibling include forced") ]; }) ];
          expr = den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.probeX;
          expectedError = {
            type = "ThrownError";
            msg = "den-test: sibling include forced";
          };
        }
      );

      # An option decided by a class query takes the landed answer, and
      # deciding it doesn't feed back into what lands.
      test-class-query-decides-option = denTest (
        { den, igloo, ... }:
        {
          den.schema.user.classes = [ "homeManager" ];
          den.default.homeManager.home.stateVersion = "25.11";
          den.default.includes = [ den._.define-user ];
          den.hosts.x86_64-linux.igloo.users.tux = { };
          den.aspects.probeX = probeX;
          den.aspects.igloo.includes = [
            den.aspects.probeX
            {
              nixos =
                { host, lib, ... }:
                {
                  environment.etc."derived" = lib.mkIf (host.hasAspect den.aspects.probeX) { text = "d"; };
                  environment.etc."derived-absent" = lib.mkIf (host.hasAspect den.aspects.absent) { text = "a"; };
                };
            }
          ];
          den.aspects.absent.nixos.environment.etc."mark-absent".text = "a";
          expr = builtins.filter (n: lib.hasPrefix "mark-" n || lib.hasPrefix "derived" n) (
            builtins.attrNames igloo.environment.etc
          );
          expected = [
            "derived"
            "mark-x"
          ];
        }
      );

      # The finalized query names an entity the flake instantiates, or one below
      # it through `within`; anything else is refused by name.
      test-finalized-query-refuses-unknown = denTest (
        { den, ... }:
        {
          den.hosts.x86_64-linux.igloo.users.tux = { };
          expr = den.lib.__hasLandedAspect {
            entity = den.hosts.x86_64-linux.igloo.users.tux;
          } den.aspects.igloo;
          expectedError = {
            type = "ThrownError";
            msg = "den: __hasLandedAspect";
          };
        }
      );
    };
}
