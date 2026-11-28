# Two hosts with the same name on different systems share an id_hash (kind +
# name), but each lands its own content. The fleet landing index keys each
# delivery by id_hash, system and class, so each igloo's in-context
# `host.hasAspect` and the finalized query answer about that igloo's own
# landing. Expectations come from the markers that land, in both orders of
# which system carries which marker. The nested-scope control is tux below
# each igloo, read in its own home and through `within.host`.
{ denTest, lib, ... }:
let
  b = v: if v then "T" else "f";

  # igloo and iceberg resolved under a `fleet` entity without excluding the
  # default per-system walk, so each is delivered from two scopes.
  twiceDelivered =
    { den, ... }:
    {
      den.hosts.x86_64-linux.igloo = { };
      den.hosts.x86_64-linux.iceberg = { };
      den.policies.to-fleet = _: [ (den.lib.policy.resolve.to "fleet" { fleet.name = "fleet"; }) ];
      den.policies.fleet-to-hosts =
        { fleet, ... }:
        lib.concatMap
          (n: [
            (den.lib.policy.resolve.to "host" { host = den.hosts.x86_64-linux.${n}; })
            (den.lib.policy.instantiate den.hosts.x86_64-linux.${n})
          ])
          [
            "igloo"
            "iceberg"
          ];
      den.schema.flake.includes = [ den.policies.to-fleet ];
      den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
      den.aspects.mk.nixos.environment.etc."mark-k".text = "k";
      den.aspects.igloo.includes = [ den.aspects.mk ];
    };
  fixture =
    xHas:
    { den, ... }:
    {
      den.schema.user.classes = [ "homeManager" ];
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [
        den._.define-user
        {
          nixos =
            { host, ... }:
            {
              environment.etc."r".text =
                "${b (host.hasAspect den.aspects.mx)}${b (host.hasAspect den.aspects.ma)}";
            };
          homeManager =
            { user, ... }:
            {
              home.file."r".text = "${b (user.hasAspect den.aspects.mx)}${b (user.hasAspect den.aspects.ma)}";
            };
        }
      ];
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.hosts.aarch64-linux.igloo = {
        intoAttr = [
          "nixosConfigurations"
          "igloo-arm"
        ];
        users.tux = { };
      };
      den.aspects.mx = {
        nixos.environment.etc."mark-x".text = "x";
        homeManager.home.file."mark-x".text = "x";
      };
      den.aspects.ma = {
        nixos.environment.etc."mark-a".text = "a";
        homeManager.home.file."mark-a".text = "a";
      };
      # Each system's igloo, and tux on it, gets its own marker aspect.
      den.schema.host.includes = [
        (
          { host, ... }:
          {
            includes = [ (if (host.system == "x86_64-linux") == xHas then den.aspects.mx else den.aspects.ma) ];
          }
        )
      ];
      den.schema.user.includes = [
        (
          { host, user, ... }:
          {
            includes = [ (if (host.system == "x86_64-linux") == xHas then den.aspects.mx else den.aspects.ma) ];
          }
        )
      ];
    };

  # Per igloo: what lands, and each reader's answer, as "<mx><ma>".
  read =
    den: config:
    let
      row =
        sys: n:
        let
          c = config.flake.nixosConfigurations.${n}.config;
          etc = c.environment.etc;
          hm = c.home-manager.users.tux.home.file;
          h = den.hosts.${sys}.igloo;
          late = r: b (den.lib.__hasLandedAspect { entity = h; } r);
          lateTux =
            r:
            b (
              den.lib.__hasLandedAspect {
                entity = h.users.tux;
                within.host = h;
              } r
            );
        in
        {
          host = {
            lands = "${b (etc ? "mark-x")}${b (etc ? "mark-a")}";
            inContext = lib.concatStringsSep "," (lib.unique (lib.splitString "\n" etc."r".text));
            late = "${late den.aspects.mx}${late den.aspects.ma}";
          };
          tux = {
            lands = "${b (hm ? "mark-x")}${b (hm ? "mark-a")}";
            inContext = hm."r".text;
            late = "${lateTux den.aspects.mx}${lateTux den.aspects.ma}";
          };
        };
    in
    {
      x86 = row "x86_64-linux" "igloo";
      arm = row "aarch64-linux" "igloo-arm";
    };

  # Every reader equals what lands, and the two igloos land different markers.
  agrees =
    r:
    builtins.all
      (
        row:
        builtins.all (e: e.inContext == e.lands && e.late == e.lands) [
          row.host
          row.tux
        ]
      )
      [
        r.x86
        r.arm
      ];
in
{
  flake.tests.landing-index-per-system = {
    test-x86-lands-mx = denTest (
      { den, config, ... }:
      let
        r = read den config;
      in
      {
        imports = [ (fixture true) ];
        expr = {
          lands = [
            r.x86.host.lands
            r.arm.host.lands
          ];
          agrees = agrees r;
        };
        expected = {
          lands = [
            "Tf"
            "fT"
          ];
          agrees = true;
        };
      }
    );
    test-x86-lands-ma = denTest (
      { den, config, ... }:
      let
        r = read den config;
      in
      {
        imports = [ (fixture false) ];
        expr = {
          lands = [
            r.x86.host.lands
            r.arm.host.lands
          ];
          agrees = agrees r;
        };
        expected = {
          lands = [
            "fT"
            "Tf"
          ];
          agrees = true;
        };
      }
    );

    # One host delivered from two scopes is ambiguous: the index refuses it by
    # name rather than keep either delivery.
    test-same-host-from-two-scopes-is-refused = denTest (
      { den, ... }:
      let
        inherit (den.lib.policy) resolve instantiate;
      in
      {
        den.schema.zone.isEntity = true;
        den.schema.host.parent = "zone";
        den.schema.flake-system.excludes = [ den.policies.system-to-os-outputs ];
        den.policies.test-zones =
          { system, ... }:
          map (n: resolve.to "zone" { zone.name = n; }) [
            "a"
            "b"
          ];
        den.policies.test-zone-hosts =
          { zone, ... }:
          [
            (resolve.to "host" { host = den.hosts.x86_64-linux.igloo; })
            (instantiate den.hosts.x86_64-linux.igloo)
          ];
        den.schema.flake-system.includes = [ den.policies.test-zones ];
        den.schema.zone.includes = [ den.policies.test-zone-hosts ];
        den.hosts.x86_64-linux.igloo = { };
        expr = den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.igloo;
        expectedError = {
          type = "ThrownError";
          msg = "den: two scopes deliver igloo";
        };
      }
    );

    # A host record's own `class` option takes one value: two class
    # definitions for it conflict.
    test-one-host-two-classes-conflict = denTest (
      { den, ... }:
      {
        imports = [ { den.hosts.x86_64-linux.igloo.class = "darwin"; } ];
        den.hosts.x86_64-linux.igloo.class = "nixos";
        expr = den.hosts.x86_64-linux.igloo.class;
        expectedError = {
          type = "ThrownError";
          msg = "den: conflicting definitions for `class` on an entity";
        };
      }
    );

    # The nearest shape with two classes under one name and system: a host and
    # a standalone home both named igloo, each landing its own marker, each
    # answering about its own.
    test-host-and-home-same-name = denTest (
      {
        den,
        config,
        igloo,
        ...
      }:
      let
        hm = config.flake.homeConfigurations.igloo.config.home.file;
      in
      {
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den._.define-user ];
        den.hosts.x86_64-linux.igloo = { };
        den.homes.x86_64-linux.igloo = { };
        den.aspects.mh.nixos.environment.etc."mark-h".text = "h";
        den.aspects.mm.homeManager.home.file."mark-m".text = "m";
        den.schema.host.includes = [ den.aspects.mh ];
        den.schema.home.includes = [
          den.aspects.mm
          {
            homeManager =
              { home, ... }:
              {
                home.file."r".text = "${b (home.hasAspect den.aspects.mh)}${b (home.hasAspect den.aspects.mm)}";
              };
          }
        ];
        den.default.nixos =
          { host, ... }:
          {
            environment.etc."r".text =
              "${b (host.hasAspect den.aspects.mh)}${b (host.hasAspect den.aspects.mm)}";
          };
        expr = {
          host = {
            lands = "${b (igloo.environment.etc ? "mark-h")}${b (igloo.environment.etc ? "mark-m")}";
            inContext = igloo.environment.etc."r".text;
            late = "${b (den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.mh)}${
              b (den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.mm)
            }";
          };
          home = {
            lands = "${b (hm ? "mark-h")}${b (hm ? "mark-m")}";
            inContext = hm."r".text;
            late = "${b (den.lib.__hasLandedAspect { entity = den.homes.x86_64-linux.igloo; } den.aspects.mh)}${
              b (den.lib.__hasLandedAspect { entity = den.homes.x86_64-linux.igloo; } den.aspects.mm)
            }";
          };
        };
        expected = {
          host = {
            lands = "Tf";
            inContext = "Tf";
            late = "Tf";
          };
          home = {
            lands = "fT";
            inContext = "fT";
            late = "fT";
          };
        };
      }
    );

    # The fleet shape where each host is delivered twice (a `fleet` entity plus
    # the default per-system walk): a class module that only binds `host`
    # builds, a read on a duplicated host is refused by name, and a host the
    # fleet doesn't cover still answers.
    test-twice-delivered-host-binds = denTest (
      { igloo, ... }:
      {
        imports = [ twiceDelivered ];
        den.default.nixos =
          { host, ... }:
          {
            environment.etc."hn".text = host.name;
          };
        expr = igloo.environment.etc."hn".text;
        expected = "igloo";
      }
    );
    test-twice-delivered-host-read-refused = denTest (
      { den, igloo, ... }:
      {
        imports = [ twiceDelivered ];
        den.default.nixos =
          { host, ... }:
          {
            environment.etc."r".text = b (host.hasAspect den.aspects.mk);
          };
        expr = igloo.environment.etc."r".text;
        expectedError = {
          type = "ThrownError";
          msg = "den: two scopes deliver igloo";
        };
      }
    );
    test-once-delivered-sibling-answers = denTest (
      { den, config, ... }:
      let
        etc = config.flake.nixosConfigurations.solo.config.environment.etc;
      in
      {
        imports = [ twiceDelivered ];
        den.hosts.x86_64-linux.solo = { };
        den.aspects.solo.includes = [ den.aspects.mk ];
        den.aspects.solo.nixos =
          { host, ... }:
          {
            environment.etc."r".text = b (host.hasAspect den.aspects.mk);
          };
        expr = {
          lands = b (etc ? "mark-k");
          inContext = etc."r".text;
          late = b (den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.solo; } den.aspects.mk);
        };
        expected = {
          lands = "T";
          inContext = "T";
          late = "T";
        };
      }
    );

    # One host record delivered in two classes from one scope: its own nixos
    # build plus a custom-class spec built from the record. Each class is its
    # own delivery, so the nixos readers answer about nixos only.
    test-one-record-two-classes = denTest (
      { den, igloo, ... }:
      {
        den.classes.probe.description = "probe";
        den.hosts.x86_64-linux.igloo = { };
        den.policies.test-dual =
          { system, ... }:
          lib.optional (system == "x86_64-linux") (
            den.lib.policy.instantiate (
              den.hosts.x86_64-linux.igloo
              // {
                class = "probe";
                instantiate = { modules, ... }: modules;
                intoAttr = [
                  "probeOut"
                  "igloo"
                ];
              }
            )
          );
        den.schema.flake-system.includes = [ den.policies.test-dual ];
        den.aspects.mk.nixos.environment.etc."mark-k".text = "k";
        den.aspects.mp.probe.x = 1;
        den.aspects.igloo.includes = [
          den.aspects.mk
          den.aspects.mp
        ];
        den.aspects.igloo.nixos =
          { host, ... }:
          {
            environment.etc."r".text =
              "${b (host.hasAspect den.aspects.mk)}${b (host.hasAspect den.aspects.mp)}";
          };
        expr = {
          inContext = igloo.environment.etc."r".text;
          late = "${b (den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.mk)}${
            b (den.lib.__hasLandedAspect { entity = den.hosts.x86_64-linux.igloo; } den.aspects.mp)
          }";
        };
        expected = {
          inContext = "Tf";
          late = "Tf";
        };
      }
    );
  };
}
