# The assignment stage (#781): which users are on which host, decided over
# facts before any host is resolved, and read by everything that reads
# `host.users`.
{ denTest, lib, ... }:
let
  # Hosts carry an `environment` fact, users a `groups` fact; admins go on
  # every prod host.
  fleet =
    { den, ... }:
    {
      den.schema.host.facts = [
        {
          options.environment = lib.mkOption {
            type = lib.types.str;
            default = "dev";
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
      den.users.alice.facts.groups = [ "admin" ];
      den.users.bob.facts.groups = [ "deploy" ];
      den.policies.admins-on-prod = den.lib.policy.assign (
        { host, users }:
        lib.optionals (host.facts.environment == "prod") (
          builtins.attrNames (lib.filterAttrs (_: u: builtins.elem "admin" u.facts.groups) users)
        )
      );
      den.schema.host.includes = [ den.policies.admins-on-prod ];
    };
in
{
  flake.tests.user-assignment = {

    test-policy-assigns-by-facts = denTest (
      { den, ... }:
      {
        imports = [ fleet ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        den.hosts.x86_64-linux.iceberg = { };
        expr = {
          igloo = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
          iceberg = builtins.attrNames den.hosts.x86_64-linux.iceberg.users;
          by = den.hosts.x86_64-linux.igloo.users.alice.__assignedBy;
        };
        expected = {
          igloo = [ "alice" ];
          iceberg = [ ];
          by = [ "policy:admins-on-prod" ];
        };
      }
    );

    # Assignment is the only content-free source: a policy naming a user that
    # `host.users` also gives content keeps that content, once, with both
    # sources recorded.
    test-policy-and-host-users-collapse-to-one = denTest (
      { den, ... }:
      {
        imports = [ fleet ];
        den.hosts.x86_64-linux.igloo = {
          facts.environment = "prod";
          users.alice.email = "alice@igloo";
        };
        expr = {
          users = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
          inherit (den.hosts.x86_64-linux.igloo.users.alice) email;
          by = lib.sort (a: b: a < b) den.hosts.x86_64-linux.igloo.users.alice.__assignedBy;
        };
        expected = {
          users = [ "alice" ];
          email = "alice@igloo";
          by = [
            "host.users"
            "policy:admins-on-prod"
          ];
        };
      }
    );

    test-policy-assigned-user-gets-account = denTest (
      { den, igloo, ... }:
      {
        imports = [ fleet ];
        den.default.includes = [ den.provides.define-user ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        expr = {
          alice = igloo.users.users.alice.isNormalUser;
          bob = igloo.users.users ? bob;
        };
        expected = {
          alice = true;
          bob = false;
        };
      }
    );

    # home-manager's host-level detection reads `host.users`.
    test-home-manager-sees-policy-assigned-user = denTest (
      { den, igloo, ... }:
      {
        imports = [ fleet ];
        den.default.includes = [ den.provides.define-user ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        den.aspects.alice.homeManager.programs.fish.enable = true;
        expr = igloo.home-manager.users.alice.programs.fish.enable;
        expected = true;
      }
    );

    test-stub-aspect-for-policy-assigned-user = denTest (
      { den, ... }:
      {
        imports = [ fleet ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        expr = den.aspects ? alice;
        expected = true;
      }
    );

    # A class only one host gives the user still gets its stub key.
    test-stub-aspect-has-per-host-only-class = denTest (
      { den, ... }:
      {
        den.users.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux.classes = [
          "homeManager"
          "user"
        ];
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        expr = {
          registry = den.users.tux.classes;
          stubHasUser = den.aspects.tux ? user;
        };
        expected = {
          registry = [ "homeManager" ];
          stubHasUser = true;
        };
      }
    );

    # A function-form entry is evaluated alone for its classes: the stub gets
    # the per-host class, and those classes equal the composed user's.
    test-stub-aspect-function-form-entry = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux =
          { ... }:
          {
            classes = [
              "homeManager"
              "user"
            ];
          };
        expr = {
          stubHasUser = den.aspects.tux ? user;
          same =
            den.hosts.x86_64-linux.igloo.__declaredUserClasses.tux
            == den.hosts.x86_64-linux.igloo.users.tux.classes;
        };
        expected = {
          stubHasUser = true;
          same = true;
        };
      }
    );

    # Real imports go through the function form, which is a module.
    test-stub-aspect-function-form-imports = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux =
          { ... }:
          {
            imports = [ { classes = lib.mkForce [ "user" ]; } ];
          };
        expr = {
          stubHasUser = den.aspects.tux ? user;
          inherit (den.hosts.x86_64-linux.igloo.users.tux) classes;
          same =
            den.hosts.x86_64-linux.igloo.__declaredUserClasses.tux
            == den.hosts.x86_64-linux.igloo.users.tux.classes;
        };
        expected = {
          stubHasUser = true;
          classes = [ "user" ];
          same = true;
        };
      }
    );

    # As in nixpkgs' submodule, an attrset entry only defines config, so its
    # `imports` is data and changes no class.
    test-attrset-entry-imports-stays-data = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.imports = [ { classes = lib.mkForce [ "user" ]; } ];
        expr = {
          inherit (den.hosts.x86_64-linux.igloo.users.tux) classes;
          stubCoversComposed = builtins.all (
            c: den.aspects.tux ? ${c}
          ) den.hosts.x86_64-linux.igloo.users.tux.classes;
          stubHasUser = den.aspects.tux ? user;
        };
        expected = {
          classes = [ "homeManager" ];
          stubCoversComposed = true;
          stubHasUser = false;
        };
      }
    );

    test-host-excludes-assignment-policy = denTest (
      { den, ... }:
      {
        imports = [ fleet ];
        den.hosts.x86_64-linux.igloo = {
          facts.environment = "prod";
          excludes = [ den.policies.admins-on-prod ];
        };
        expr = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
        expected = [ ];
      }
    );

    # Users only an assignment policy puts on the host, nothing in host.users:
    # a `{ user, ... }` key under the host reaches the named user's
    # host-integrated home once, and no other user's (#788).
    test-assigned-users-host-key-reaches-named-user-once = denTest (
      { den, igloo, ... }:
      {
        den.default.includes = [ den.provides.define-user ];
        den.schema.user.classes = lib.mkForce [ "homeManager" ];
        den.users = {
          tux = { };
          pingu = { };
        };
        den.policies.both = den.lib.policy.assign (_: [
          "tux"
          "pingu"
        ]);
        den.hosts.x86_64-linux.igloo.includes = [ den.policies.both ];
        den.aspects.igloo.tux =
          { user, ... }:
          {
            homeManager.home.sessionPath = [ "/marker/${user.name}" ];
          };
        expr =
          let
            markers =
              name: builtins.filter (lib.hasPrefix "/marker/") igloo.home-manager.users.${name}.home.sessionPath;
          in
          {
            users = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
            tux = markers "tux";
            pingu = markers "pingu";
          };
        expected = {
          users = [
            "pingu"
            "tux"
          ];
          tux = [ "/marker/tux" ];
          pingu = [ ];
        };
      }
    );

    test-host-includes-assignment-policy = denTest (
      { den, ... }:
      {
        den.users.alice = { };
        den.policies.alice-here = den.lib.policy.assign (_: [ "alice" ]);
        den.hosts.x86_64-linux.igloo.includes = [ den.policies.alice-here ];
        den.hosts.x86_64-linux.iceberg = { };
        expr = {
          igloo = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
          iceberg = builtins.attrNames den.hosts.x86_64-linux.iceberg.users;
        };
        expected = {
          igloo = [ "alice" ];
          iceberg = [ ];
        };
      }
    );

    test-unknown-user-name-is-an-error = denTest (
      { den, ... }:
      {
        den.policies.typo = den.lib.policy.assign (_: [ "alcie" ]);
        den.schema.host.includes = [ den.policies.typo ];
        den.hosts.x86_64-linux.igloo = { };
        expr = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
        expectedError = {
          type = "ThrownError";
          msg = "assigned 'alcie' to host 'igloo', but den.users has no such user";
        };
      }
    );

    test-excluding-unincluded-policy-is-an-error = denTest (
      { den, ... }:
      {
        den.policies.nobody = den.lib.policy.assign (_: [ ]);
        den.hosts.x86_64-linux.igloo.excludes = [ den.policies.nobody ];
        expr = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
        expectedError = {
          type = "ThrownError";
          msg = "`nobody` excluded, but not included";
        };
      }
    );

    test-unnamed-assignment-policy-is-an-error = denTest (
      { den, ... }:
      {
        den.users.alice = { };
        den.schema.host.includes = [ (den.lib.policy.assign (_: [ "alice" ])) ];
        den.hosts.x86_64-linux.igloo = { };
        expr = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
        expectedError = {
          type = "ThrownError";
          msg = "assignment policy is used without a name";
        };
      }
    );

    test-assignment-policy-in-den-default-is-an-error = denTest (
      { den, igloo, ... }:
      {
        den.users.alice = { };
        den.policies.alice-here = den.lib.policy.assign (_: [ "alice" ]);
        den.default.includes = [ den.policies.alice-here ];
        den.hosts.x86_64-linux.igloo = { };
        expr = igloo.system.build.toplevel.drvPath;
        expectedError = {
          type = "ThrownError";
          msg = "reached resolution for host .igloo. without the assignment stage selecting it";
        };
      }
    );

    test-fact-default-reading-host-is-an-error = denTest (
      { den, ... }:
      {
        den.schema.host.facts = [
          (
            { host, ... }:
            {
              options.environment = lib.mkOption {
                type = lib.types.str;
                default = host.hostName;
              };
            }
          )
        ];
        den.hosts.x86_64-linux.igloo = { };
        expr = den.hosts.x86_64-linux.igloo.facts.environment;
        expectedError = {
          type = "ThrownError";
          msg = "a fact of host 'igloo' reads `host`";
        };
      }
    );

    test-fact-sees-identity-and-other-facts = denTest (
      { den, ... }:
      {
        den.schema.host.facts = [
          (
            { name, config, ... }:
            {
              options.environment = lib.mkOption { type = lib.types.str; };
              options.label = lib.mkOption {
                type = lib.types.str;
                default = "${name}-${config.environment}";
              };
            }
          )
        ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        expr = den.hosts.x86_64-linux.igloo.facts.label;
        expected = "igloo-prod";
      }
    );

    # A host option reading `config.users` sees every assigned user and
    # changes no fact: facts never read the host.
    test-host-option-reading-users-leaves-facts-alone = denTest (
      { den, ... }:
      {
        imports = [ fleet ];
        den.schema.host.imports = [
          (
            { config, ... }:
            {
              options.userCount = lib.mkOption {
                type = lib.types.int;
                default = builtins.length (builtins.attrNames config.users);
              };
            }
          )
        ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        expr = {
          inherit (den.hosts.x86_64-linux.igloo) userCount;
          inherit (den.hosts.x86_64-linux.igloo.facts) environment;
        };
        expected = {
          userCount = 1;
          environment = "prod";
        };
      }
    );

    test-user-facts-on-a-host-are-an-error = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.facts.groups = [ "wheel" ];
        expr = den.hosts.x86_64-linux.igloo.users.tux.facts;
        expectedError = {
          type = "ThrownError";
          msg = "sets `facts` on host 'igloo'";
        };
      }
    );

    test-host-user-sees-registry-facts = denTest (
      { den, ... }:
      {
        imports = [ fleet ];
        den.hosts.x86_64-linux.igloo.facts.environment = "prod";
        expr = den.hosts.x86_64-linux.igloo.users.alice.facts.groups;
        expected = [ "admin" ];
      }
    );

    # An entry that discharges to nothing declares no user: it isn't
    # registered, gets no stub aspect and isn't an account.
    test-disabled-host-user-is-not-declared = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = lib.mkIf false { };
          pingu = { };
        };
        expr = {
          users = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
          registered = den.users ? tux;
          stub = den.aspects ? tux;
        };
        expected = {
          users = [ "pingu" ];
          registered = false;
          stub = false;
        };
      }
    );

    test-nested-disabled-host-user-is-not-declared = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = lib.mkIf true (lib.mkIf false { });
          pingu = { };
        };
        expr = {
          users = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
          registered = den.users ? tux;
          stub = den.aspects ? tux;
        };
        expected = {
          users = [ "pingu" ];
          registered = false;
          stub = false;
        };
      }
    );
    test-empty-merge-host-user-is-not-declared = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = lib.mkMerge [ ];
          pingu = { };
        };
        expr = {
          users = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
          registered = den.users ? tux;
          stub = den.aspects ? tux;
        };
        expected = {
          users = [ "pingu" ];
          registered = false;
          stub = false;
        };
      }
    );
    # Control: a priority wrapper around a false `mkIf` still discharges to
    # a definition, so the user stays declared, as before den.users.
    test-default-around-disabled-stays-declared = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = lib.mkDefault (lib.mkIf false { });
          pingu = { };
        };
        expr = {
          users = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
          registered = den.users ? tux;
        };
        expected = {
          users = [
            "pingu"
            "tux"
          ];
          registered = true;
        };
      }
    );

    # A host may exclude an assignment policy another host includes.
    test-exclude-on-another-host = denTest (
      { den, ... }:
      {
        den.users.ann = { };
        den.policies.p = den.lib.policy.assign (_: [ "ann" ]);
        den.hosts.x86_64-linux.igloo.includes = [ den.policies.p ];
        den.hosts.x86_64-linux.iceberg.excludes = [ den.policies.p ];
        expr = {
          igloo = builtins.attrNames den.hosts.x86_64-linux.igloo.users;
          iceberg = builtins.attrNames den.hosts.x86_64-linux.iceberg.users;
        };
        expected = {
          igloo = [ "ann" ];
          iceberg = [ ];
        };
      }
    );

    # An assignment policy is selected once per host, however it's reached,
    # and its assignment recorded once. (How many times Nix calls its function
    # isn't observable from a cell.)
    test-policy-selected-once-per-host = denTest (
      { den, ... }:
      let
        # How many times each host selected `p` (other builtin policies aside).
        pCount = h: builtins.length (builtins.filter (n: n == "p") h.__assignmentPolicies);
      in
      {
        den.users.ann = { };
        den.policies.p = den.lib.policy.assign ({ host, ... }: lib.optional (host.name == "igloo") "ann");
        # Reached both ways on igloo: through the schema and its own includes.
        den.schema.host.includes = [ den.policies.p ];
        den.hosts.x86_64-linux = {
          igloo.includes = [ den.policies.p ];
          iceberg = { };
        };
        expr = {
          perHost = map pCount (builtins.attrValues den.hosts.x86_64-linux);
          assignedBy = den.hosts.x86_64-linux.igloo.users.ann.__assignedBy;
        };
        expected = {
          perHost = [
            1
            1
          ];
          assignedBy = [ "policy:p" ];
        };
      }
    );
  };
}
