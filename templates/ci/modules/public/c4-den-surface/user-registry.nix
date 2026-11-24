# `den.users`: one registry user per person, and the view each host gets of
# them — the registry user plus the host's `user@host` relation (#781).
{ denTest, lib, ... }:
let
  shellOption = {
    den.schema.user.imports = [
      {
        options.shell = lib.mkOption {
          type = lib.types.str;
          default = "bash";
        };
      }
    ];
  };
  groupsOption = default: {
    den.schema.user.imports = [
      {
        options.groups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          inherit default;
        };
      }
    ];
  };

  # `registry` and `relation` set `shell` on den.users.tux and on igloo's tux.
  bands =
    expected: registry: relation:
    denTest (
      { den, ... }:
      {
        imports = [ shellOption ];
        den.users.tux.shell = registry;
        den.hosts.x86_64-linux.igloo.users.tux.shell = relation;
        expr = den.hosts.x86_64-linux.igloo.users.tux.shell;
        inherit expected;
      }
    );
  # Skipped, not exported: band precedence covers declared options only. A
  # freeform field carries no per-key priority after gen-merge's merge, so it
  # competes in the `set` band. This cell joins the suite once gen-merge
  # publishes per-key freeform priority and den's gen pin includes it.
  skipped.test-freeform-registry-force-beats-relation-plain = denTest (
    { den, ... }:
    {
      den.users.tux.editor = lib.mkForce "vim";
      den.hosts.x86_64-linux.igloo.users.tux.editor = "nano";
      expr = den.hosts.x86_64-linux.igloo.users.tux.editor;
      expected = "vim";
    }
  );
in
{
  flake.tests.user-registry = {

    test-registry-entry-is-readable = denTest (
      { den, ... }:
      {
        den.users.alice.email = "alice@example.com";
        expr = {
          inherit (den.users.alice) email name userName;
        };
        expected = {
          email = "alice@example.com";
          name = "alice";
          userName = "alice";
        };
      }
    );

    test-host-users-registers-registry-user = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = {
          registered = den.users ? tux;
          inherit (den.users.tux) classes;
        };
        expected = {
          registered = true;
          classes = [ "homeManager" ];
        };
      }
    );

    test-host-user-sees-registry-fields = denTest (
      { den, ... }:
      {
        den.users.tux.email = "tux@example.com";
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = den.hosts.x86_64-linux.igloo.users.tux.email;
        expected = "tux@example.com";
      }
    );

    test-registry-only-user-gets-no-account = denTest (
      { den, igloo, ... }:
      {
        den.default.includes = [ den.provides.define-user ];
        den.users.ghost = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = {
          onHost = den.hosts.x86_64-linux.igloo.users ? ghost;
          account = igloo.users.users ? ghost;
          tux = igloo.users.users.tux.isNormalUser;
        };
        expected = {
          onHost = false;
          account = false;
          tux = true;
        };
      }
    );

    # The registry's `userName` reaches the host's real account.
    test-registry-field-reaches-host-output = denTest (
      { den, igloo, ... }:
      {
        den.default.includes = [ den.provides.define-user ];
        den.users.tux.userName = "tuxedo";
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = igloo.users.users ? tuxedo;
        expected = true;
      }
    );

    test-band-plain-both-relation-wins = bands "fish" "zsh" "fish";
    test-band-registry-force-beats-relation-plain = bands "zsh" (lib.mkForce "zsh") "fish";
    test-band-registry-plain-beats-relation-default = bands "zsh" "zsh" (lib.mkDefault "fish");
    test-band-default-both-relation-wins = bands "fish" (lib.mkDefault "zsh") (lib.mkDefault "fish");
    # Same band (force), so specificity decides despite 75 > 50.
    test-band-override-75-vs-force-relation-wins = bands "fish" (lib.mkOverride 75 "zsh") (
      lib.mkForce "fish"
    );
    # Same band (set), so specificity decides despite 200 < 900.
    test-band-custom-priorities-one-band = bands "fish" (lib.mkOverride 200 "zsh") (
      lib.mkOverride 900 "fish"
    );
    test-band-relation-mkif-false-contributes-nothing = bands "zsh" "zsh" (lib.mkIf false "fish");
    # `mkOptionDefault` moves nothing: the registry's default band wins.
    test-band-option-default-moves-nothing = bands "zsh" (lib.mkDefault "zsh") (
      lib.mkOptionDefault "fish"
    );

    # A function-form override counts as the relation's own definition.
    test-band-function-form-relation-wins = denTest (
      { den, ... }:
      {
        imports = [ shellOption ];
        den.users.tux.shell = "zsh";
        den.hosts.x86_64-linux.igloo.users.tux = _: { shell = "fish"; };
        expr = den.hosts.x86_64-linux.igloo.users.tux.shell;
        expected = "fish";
      }
    );

    # A function-form registry entry counts as the registry's own, too.
    test-band-function-form-registry-force-wins = denTest (
      { den, ... }:
      {
        imports = [ shellOption ];
        den.users.tux = _: { shell = lib.mkForce "zsh"; };
        den.hosts.x86_64-linux.igloo.users.tux.shell = "fish";
        expr = den.hosts.x86_64-linux.igloo.users.tux.shell;
        expected = "zsh";
      }
    );

    test-unset-on-both-keeps-schema-default = denTest (
      { den, ... }:
      {
        imports = [ shellOption ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = den.hosts.x86_64-linux.igloo.users.tux.shell;
        expected = "bash";
      }
    );

    test-replace-is-default-for-lists = denTest (
      { den, ... }:
      {
        imports = [ (groupsOption [ ]) ];
        den.users.tux.groups = [ "wheel" ];
        den.hosts.x86_64-linux.igloo.users.tux.groups = [ "video" ];
        expr = den.hosts.x86_64-linux.igloo.users.tux.groups;
        expected = [ "video" ];
      }
    );

    test-append-fold-concatenates-registry-then-relation = denTest (
      { den, ... }:
      {
        imports = [ (groupsOption [ ]) ];
        den.schema.user.folds.groups = den.lib.fold.append;
        den.users.tux.groups = [ "wheel" ];
        den.hosts.x86_64-linux.igloo.users.tux.groups = [ "video" ];
        expr = den.hosts.x86_64-linux.igloo.users.tux.groups;
        expected = [
          "wheel"
          "video"
        ];
      }
    );

    test-append-stronger-band-suppresses-weaker = denTest (
      { den, ... }:
      {
        imports = [ (groupsOption [ ]) ];
        den.schema.user.folds.groups = den.lib.fold.append;
        den.users.tux.groups = lib.mkForce [ "wheel" ];
        den.hosts.x86_64-linux.igloo.users.tux.groups = [ "video" ];
        expr = den.hosts.x86_64-linux.igloo.users.tux.groups;
        expected = [ "wheel" ];
      }
    );

    # A schema-level definition in the same band is part of the type, so it
    # appears once, not once per position.
    test-append-schema-definition-not-counted-twice = denTest (
      { den, ... }:
      {
        imports = [ (groupsOption [ ]) ];
        den.schema.user.imports = [ { groups = [ "base" ]; } ];
        den.schema.user.folds.groups = den.lib.fold.append;
        den.users.tux.groups = [ "wheel" ];
        den.hosts.x86_64-linux.igloo.users.tux.groups = [ "video" ];
        expr = lib.sort (a: b: a < b) den.hosts.x86_64-linux.igloo.users.tux.groups;
        expected = [
          "base"
          "video"
          "wheel"
        ];
      }
    );

    # Pins today's behaviour while freeform priority is undecided: on an
    # undeclared field the relation's own contribution can't be told from the
    # schema's, so a same-band schema definition is appended twice.
    test-freeform-append-counts-schema-definition-twice = denTest (
      { den, ... }:
      {
        den.schema.user.imports = [ { groups = [ "base" ]; } ];
        den.schema.user.folds.groups = den.lib.fold.append;
        den.users.tux.groups = [ "wheel" ];
        den.hosts.x86_64-linux.igloo.users.tux.groups = [ "video" ];
        expr = lib.sort (a: b: a < b) den.hosts.x86_64-linux.igloo.users.tux.groups;
        expected = [
          "base"
          "base"
          "video"
          "wheel"
        ];
      }
    );

    test-conflicting-fold-declarations-error = denTest (
      { den, ... }:
      {
        imports = [
          (groupsOption [ ])
          { den.schema.user.folds.groups = den.lib.fold.replace; }
        ];
        den.schema.user.folds.groups = den.lib.fold.append;
        den.users.tux.groups = [ "wheel" ];
        den.hosts.x86_64-linux.igloo.users.tux.groups = [ "video" ];
        expr = den.hosts.x86_64-linux.igloo.users.tux.groups;
        expectedError = {
          type = "ThrownError";
          msg = "folds.groups is declared both";
        };
      }
    );

    test-per-host-includes-append-to-registry-includes = denTest (
      { den, ... }:
      {
        den.aspects.a = { };
        den.aspects.b = { };
        den.users.tux.includes = [ den.aspects.a ];
        den.hosts.x86_64-linux.igloo.users.tux.includes = [ den.aspects.b ];
        expr = builtins.length den.hosts.x86_64-linux.igloo.users.tux.includes;
        expected = 2;
      }
    );

    test-freeform-plain-both-relation-wins = denTest (
      { den, ... }:
      {
        den.users.tux.editor = "vim";
        den.hosts.x86_64-linux.igloo.users.tux.editor = "nano";
        expr = den.hosts.x86_64-linux.igloo.users.tux.editor;
        expected = "nano";
      }
    );

    # Per-host contributions never write back to the registry or another host.
    test-no-write-back-between-hosts = denTest (
      { den, ... }:
      {
        imports = [ shellOption ];
        den.users.tux.shell = "zsh";
        den.hosts.x86_64-linux.igloo.users.tux.shell = "fish";
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        expr = {
          igloo = den.hosts.x86_64-linux.igloo.users.tux.shell;
          iceberg = den.hosts.x86_64-linux.iceberg.users.tux.shell;
          registry = den.users.tux.shell;
        };
        expected = {
          igloo = "fish";
          iceberg = "zsh";
          registry = "zsh";
        };
      }
    );

    # A registry user is on no host, so schema modules see `host = null`; the
    # same module on a host user sees that host.
    test-registry-entry-host-is-null = denTest (
      { den, ... }:
      {
        den.schema.user.imports = [
          (
            { host, ... }:
            {
              options.onHost = lib.mkOption {
                type = lib.types.str;
                default = if host == null then "none" else host.name;
              };
            }
          )
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = {
          registry = den.users.tux.onHost;
          host = den.hosts.x86_64-linux.igloo.users.tux.onHost;
        };
        expected = {
          registry = "none";
          host = "igloo";
        };
      }
    );

  };
}
