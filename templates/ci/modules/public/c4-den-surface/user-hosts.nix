# `den.users.<n>.hosts` and the builtin `den.policies.user-to-hosts` (#781):
# host names, conditions over facts, named predicates and warned functions.
{ denTest, lib, ... }:
let
  envFact = {
    den.schema.host.facts = [
      {
        options.environment = lib.mkOption {
          type = lib.types.str;
          default = "dev";
        };
        options.region = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      }
    ];
    den.schema.user.facts = [
      {
        options.groups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      }
    ];
  };
  usersOf = den: h: builtins.attrNames den.hosts.x86_64-linux.${h}.users;

  mockHjemModule =
    { lib, ... }:
    {
      options.hjem.users = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submoduleWith {
            modules = [ { config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified; } ];
          }
        );
        default = { };
      };
    };
  mockMaidModule =
    { lib, ... }:
    {
      options.users.users = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.maid = lib.mkOption {
              type = lib.types.submoduleWith {
                modules = [ { config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified; } ];
              };
              default = { };
            };
          }
        );
      };
    };

  # The fleet-demo pattern: a host policy resolving a registry user.
  legacyFleet =
    { den, ... }:
    {
      den.default.includes = [ den.provides.define-user ];
      den.users.bob = { };
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.policies.legacy-grant =
        { host, ... }:
        lib.optional (host.name == "igloo") (den.lib.policy.resolve.to "user" { user = den.users.bob; });
      den.schema.host.includes = [ den.policies.legacy-grant ];
    };
  legacyOutputs = igloo: {
    bob = igloo.users.users.bob.isNormalUser;
    tux = igloo.users.users.tux.isNormalUser;
  };
in
{
  flake.tests.user-hosts = {

    test-host-name-assigns = denTest (
      { den, ... }:
      {
        den.users.alice.hosts = [ "igloo" ];
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.x86_64-linux.iceberg = { };
        expr = {
          igloo = usersOf den "igloo";
          iceberg = usersOf den "iceberg";
          by = den.hosts.x86_64-linux.igloo.users.alice.__assignedBy;
        };
        expected = {
          igloo = [ "alice" ];
          iceberg = [ ];
          by = [ "policy:user-to-hosts" ];
        };
      }
    );

    test-condition-assigns = denTest (
      { den, ... }:
      {
        imports = [ envFact ];
        den.users.alice.hosts = [ (den.lib.cond.eq [ "host" "environment" ] "prod") ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        den.hosts.x86_64-linux.iceberg = { };
        expr = {
          igloo = usersOf den "igloo";
          iceberg = usersOf den "iceberg";
        };
        expected = {
          igloo = [ "alice" ];
          iceberg = [ ];
        };
      }
    );

    test-condition-forms = denTest (
      { den, ... }:
      let
        inherit (den.lib) cond;
      in
      {
        imports = [ envFact ];
        den.users.prod-admin.facts.groups = [ "admin" ];
        den.users.prod-admin.hosts = [
          (cond.all [
            (cond.eq [ "host" "environment" ] "prod")
            (cond.not (cond.eq [ "host" "name" ] "iceberg"))
          ])
        ];
        den.users.everywhere.hosts = [ cond.always ];
        den.users.either.hosts = [
          (cond.any [
            (cond.eq [ "host" "name" ] "iceberg")
            (cond.eq [ "user" "name" ] "nobody")
          ])
        ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        den.hosts.x86_64-linux.iceberg.facts.environment = "prod";
        expr = {
          igloo = usersOf den "igloo";
          iceberg = usersOf den "iceberg";
        };
        expected = {
          igloo = [
            "everywhere"
            "prod-admin"
          ];
          iceberg = [
            "either"
            "everywhere"
          ];
        };
      }
    );

    # A present `null` fact equals null; `not (eq …)` of it is false.
    test-condition-present-null-fact = denTest (
      { den, ... }:
      {
        imports = [ envFact ];
        den.users.a.hosts = [ (den.lib.cond.eq [ "host" "region" ] null) ];
        den.users.b.hosts = [ (den.lib.cond.not (den.lib.cond.eq [ "host" "region" ] null)) ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expected = [ "a" ];
      }
    );

    test-condition-misspelled-fact-is-an-error = denTest (
      { den, ... }:
      {
        imports = [ envFact ];
        den.users.alice.hosts = [ (den.lib.cond.eq [ "host" "enviroment" ] "prod") ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "no `enviroment` fact is declared for hosts";
        };
      }
    );

    test-condition-refusal-is-an-error = denTest (
      { den, ... }:
      {
        den.users.alice.hosts = [ (den.lib.cond.eq [ "host" "name" ] (x: x)) ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "is a condition den can't decide";
        };
      }
    );

    # `any` stops at the first true operand, so a later refusing operand isn't
    # reached.
    test-condition-short-circuits = denTest (
      { den, ... }:
      let
        inherit (den.lib) cond;
      in
      {
        den.users.alice.hosts = [
          (cond.any [
            cond.always
            (cond.all [
              (cond.not cond.always)
              (cond.eq [ "host" "name" ] "x")
            ])
          ])
        ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expected = [ "alice" ];
      }
    );

    test-named-predicate-assigns = denTest (
      { den, ... }:
      {
        imports = [ envFact ];
        den.predicates.admin-on-prod =
          { host, user, ... }: host.facts.environment == "prod" && builtins.elem "admin" user.facts.groups;
        den.users.alice = {
          facts.groups = [ "admin" ];
          hosts = [ (den.lib.cond.predicate "admin-on-prod") ];
        };
        den.users.bob.hosts = [ (den.lib.cond.predicate "admin-on-prod") ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        den.hosts.x86_64-linux.iceberg = { };
        expr = {
          igloo = usersOf den "igloo";
          iceberg = usersOf den "iceberg";
        };
        expected = {
          igloo = [ "alice" ];
          iceberg = [ ];
        };
      }
    );

    test-same-condition-two-users = denTest (
      { den, ... }:
      let
        onProd = den.lib.cond.eq [ "host" "environment" ] "prod";
      in
      {
        imports = [ envFact ];
        den.users.alice.hosts = [ onProd ];
        den.users.bob.hosts = [ onProd ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        expr = usersOf den "igloo";
        expected = [
          "alice"
          "bob"
        ];
      }
    );

    test-missing-predicate-is-an-error = denTest (
      { den, ... }:
      {
        den.users.alice.hosts = [ (den.lib.cond.predicate "nope") ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "uses predicate 'nope', but den.predicates has no such predicate";
        };
      }
    );

    test-duplicate-predicate-is-an-error = denTest (
      { den, ... }:
      {
        imports = [ { den.predicates.p = _: true; } ];
        den.predicates.p = _: false;
        den.users.alice.hosts = [ (den.lib.cond.predicate "p") ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "is defined multiple times";
        };
      }
    );

    test-function-entry-assigns-like-condition = denTest (
      { den, ... }:
      {
        imports = [ envFact ];
        den.users.byFunction.hosts = [ ({ host, ... }: host.facts.environment == "prod") ];
        den.users.byCondition.hosts = [ (den.lib.cond.eq [ "host" "environment" ] "prod") ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        den.hosts.x86_64-linux.iceberg = { };
        expr = {
          igloo = usersOf den "igloo";
          iceberg = usersOf den "iceberg";
        };
        expected = {
          igloo = [
            "byCondition"
            "byFunction"
          ];
          iceberg = [ ];
        };
      }
    );

    test-function-entry-same-with-suppressed-warning = denTest (
      { den, ... }:
      {
        imports = [ envFact ];
        den.migrations.anonymous-predicates.suppressWarnings = true;
        den.users.byFunction.hosts = [ ({ host, ... }: host.facts.environment == "prod") ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        den.hosts.x86_64-linux.iceberg = { };
        expr = {
          igloo = usersOf den "igloo";
          iceberg = usersOf den "iceberg";
        };
        expected = {
          igloo = [ "byFunction" ];
          iceberg = [ ];
        };
      }
    );

    test-unknown-host-name-is-an-error = denTest (
      { den, ... }:
      {
        den.users.alice.hosts = [ "igloo" ];
        den.users.bob.hosts = [ "iglu" ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "names host 'iglu', but no host by that name is declared";
        };
      }
    );

    # A bad entry fails even beside one that matches.
    test-bad-entry-fails-beside-a-match = denTest (
      { den, ... }:
      {
        den.users.alice.hosts = [
          "igloo"
          "iglu"
        ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "names host 'iglu'";
        };
      }
    );

    test-malformed-entry-is-an-error = denTest (
      { den, ... }:
      {
        den.users.alice.hosts = [ 42 ];
        den.hosts.x86_64-linux.igloo = { };
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "has a int; an entry is a host name";
        };
      }
    );

    test-ambiguous-host-name-is-an-error = denTest (
      { den, ... }:
      {
        den.users.alice.hosts = [ "igloo" ];
        den.hosts.x86_64-linux.igloo = { };
        den.hosts.aarch64-linux.igloo = { };
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "declared on aarch64-linux.igloo, x86_64-linux.igloo";
        };
      }
    );

    test-excluding-user-to-hosts-ignores-hosts = denTest (
      { den, ... }:
      {
        den.schema.host.excludes = [ den.policies.user-to-hosts ];
        den.users.alice.hosts = [ "igloo" ];
        den.hosts.x86_64-linux.igloo = { };
        expr = {
          users = usersOf den "igloo";
          hostless = den.internal.hostlessUsers;
        };
        expected = {
          users = [ ];
          hostless = [ ];
        };
      }
    );

    test-sources-combine-as-or = denTest (
      { den, ... }:
      {
        den.users.alice.hosts = [ "igloo" ];
        den.hosts.x86_64-linux.igloo.users.alice.email = "alice@igloo";
        den.hosts.x86_64-linux.iceberg.users.alice = { };
        expr = {
          igloo = lib.sort (a: b: a < b) den.hosts.x86_64-linux.igloo.users.alice.__assignedBy;
          iceberg = den.hosts.x86_64-linux.iceberg.users.alice.__assignedBy;
          inherit (den.hosts.x86_64-linux.igloo.users.alice) email;
        };
        expected = {
          igloo = [
            "host.users"
            "policy:user-to-hosts"
          ];
          iceberg = [ "host.users" ];
          email = "alice@igloo";
        };
      }
    );

    test-hosts-on-a-host-user-is-an-error = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.hosts = [ "igloo" ];
        expr = den.hosts.x86_64-linux.igloo.users.tux.hosts;
        expectedError = {
          type = "ThrownError";
          msg = "sets `hosts` on host 'igloo'";
        };
      }
    );

    test-hostless-diagnostic = denTest (
      { den, ... }:
      {
        den.users.ghost = { };
        den.users.sso.hosts = [ ];
        den.users.homebody = { };
        den.homes.x86_64-linux.homebody = { };
        den.users.alice.hosts = [ "igloo" ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = den.internal.hostlessUsers;
        expected = [ "ghost" ];
      }
    );

    # A host policy assigning a user during resolution keeps working, with or
    # without its migration warning silenced.
    test-resolution-assignment-keeps-working = denTest (
      { den, igloo, ... }:
      {
        imports = [ legacyFleet ];
        expr = legacyOutputs igloo;
        expected = {
          bob = true;
          tux = true;
        };
      }
    );

    test-resolution-assignment-same-when-suppressed = denTest (
      { den, igloo, ... }:
      {
        imports = [ legacyFleet ];
        den.migrations.resolution-assignments.suppressWarnings = true;
        expr = legacyOutputs igloo;
        expected = {
          bob = true;
          tux = true;
        };
      }
    );

    # With warnings as errors: the legacy pattern warns, and den's own
    # host-scope user fan-out for each home environment does not.
    test-resolution-assignment-warns = denTest (
      { den, igloo, ... }:
      {
        imports = [ legacyFleet ];
        den.internal.warningsAsErrors = true;
        expr = legacyOutputs igloo;
        expectedError = {
          type = "ThrownError";
          msg = "policy `legacy-grant` assigns users to hosts during resolution";
        };
      }
    );

    test-home-manager-config-does-not-warn = denTest (
      { den, tuxHm, ... }:
      {
        den.internal.warningsAsErrors = true;
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.tux.homeManager.programs.fish.enable = true;
        expr = tuxHm.programs.fish.enable;
        expected = true;
      }
    );

    test-hjem-config-does-not-warn = denTest (
      { den, igloo, ... }:
      {
        den.internal.warningsAsErrors = true;
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "hjem" ];
          hjem.module = mockHjemModule;
        };
        den.aspects.tux.hjem.theme = "nord";
        expr = igloo.hjem.users.tux.theme;
        expected = "nord";
      }
    );

    test-maid-config-does-not-warn = denTest (
      { den, igloo, ... }:
      {
        den.internal.warningsAsErrors = true;
        den.hosts.x86_64-linux.igloo = {
          users.tux.classes = [ "maid" ];
          nix-maid.module = mockMaidModule;
        };
        den.aspects.tux.maid.description = "maid-tux";
        expr = igloo.users.users.tux.maid.description;
        expected = "maid-tux";
      }
    );

    test-function-entry-warns = denTest (
      { den, ... }:
      {
        imports = [ envFact ];
        den.internal.warningsAsErrors = true;
        den.users.byFunction.hosts = [ ({ host, ... }: host.facts.environment == "prod") ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        expr = usersOf den "igloo";
        expectedError = {
          type = "ThrownError";
          msg = "den.users.byFunction.hosts has an inline function";
        };
      }
    );

    test-condition-entry-does-not-warn = denTest (
      { den, ... }:
      {
        imports = [ envFact ];
        den.internal.warningsAsErrors = true;
        den.users.byCondition.hosts = [ (den.lib.cond.eq [ "host" "environment" ] "prod") ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        expr = usersOf den "igloo";
        expected = [ "byCondition" ];
      }
    );

    # The hostless warning lives only in the flake checks. Building one host
    # never reads them, even with a hostless user and a check that throws.
    test-one-host-never-forces-the-diagnostic = denTest (
      { den, igloo, ... }:
      {
        den.default.includes = [ den.provides.define-user ];
        den.users.alice.hosts = [ "igloo" ];
        den.users.ghost = { };
        den.hosts.x86_64-linux.igloo = { };
        flake.checks.x86_64-linux.sentinel = throw "den-test: the flake checks were forced";
        expr = {
          alice = igloo.users.users.alice.isNormalUser;
          hostless = den.internal.hostlessUsers;
        };
        expected = {
          alice = true;
          hostless = [ "ghost" ];
        };
      }
    );

    # The checks carry the diagnostic: reading them reaches it.
    test-flake-checks-carry-the-diagnostic = denTest (
      { den, config, ... }:
      {
        den.users.alice.hosts = [ "igloo" ];
        den.users.ghost = { };
        den.hosts.x86_64-linux.igloo = { };
        den.homes.x86_64-linux.sentinel.userName = throw "den-test: the diagnostic was read";
        expr = builtins.attrNames config.flake.checks;
        expectedError = {
          type = "ThrownError";
          msg = "the diagnostic was read";
        };
      }
    );

  };
}
