# Issue #694: mutual-provider delivers exactly what a user's `provides.to-hosts`
# / `provides.<host>` emits at the user scope (its provenance), folded with the
# user's own context and pipe values, to the host. Nothing else of the user's
# crosses.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-694-provenance = {

    test-static = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.p.text = "static";
        expr = igloo.environment.etc.p.text;
        expected = "static";
      }
    );

    test-parametric = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts =
          { host, user, ... }:
          {
            nixos.environment.etc.p.text = "${user.name}@${host.name}";
          };
        expr = igloo.environment.etc.p.text;
        expected = "tux@igloo";
      }
    );

    test-named-host = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.tux.provides.igloo.nixos.environment.etc.p.text = "igloo-only";
        expr = {
          igloo = igloo.environment.etc.p.text;
          iceberg = iceberg.environment.etc ? p;
        };
        expected = {
          igloo = "igloo-only";
          iceberg = false;
        };
      }
    );

    test-two-owners = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.x.provides.to-hosts.nixos.environment.etc.x.text = "x";
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.t.text = "t";
        den.aspects.tux.includes = [ den.aspects.x ];
        expr = [
          igloo.environment.etc.x.text
          igloo.environment.etc.t.text
        ];
        expected = [
          "x"
          "t"
        ];
      }
    );

    # A named aspect included inside the provided aspect keeps its own
    # identity; provenance still selects it.
    test-named-sub-include-delivered = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.feat.text = "feat";
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.feat ];
        expr = igloo.environment.etc.feat.text;
        expected = "feat";
      }
    );

    # The same aspect included directly by the user does not cross.
    test-direct-include-does-not-cross = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.environment.etc.feat.text = "feat";
        den.aspects.tux.includes = [ den.aspects.feat ];
        expr = igloo.environment.etc ? feat;
        expectedError = {
          type = "ThrownError";
          msg = "no longer receives host-class content";
        };
      }
    );

    # With user-aspects on the same host, to-hosts content lands once.
    test-with-user-aspects-no-doubling = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.provides.to-hosts.nixos.boot.kernelModules = [ "tux-mod" ];
        expr = builtins.length (builtins.filter (m: m == "tux-mod") igloo.boot.kernelModules);
        expected = 1;
      }
    );

    # Provided and also included directly by the user, in either order: the
    # provide's edge still crosses, and the unkeyed content lands once.
    test-provided-and-direct = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.boot.kernelModules = [ "feat-mod" ];
        den.aspects.tux.includes = [ den.aspects.feat ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.feat ];
        expr = builtins.filter (m: m == "feat-mod") igloo.boot.kernelModules;
        expected = [ "feat-mod" ];
      }
    );

    test-direct-after-provided = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.feat.nixos.boot.kernelModules = [ "feat-mod" ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.feat ];
        den.aspects.tux.includes = [ den.aspects.feat ];
        expr = builtins.filter (m: m == "feat-mod") igloo.boot.kernelModules;
        expected = [ "feat-mod" ];
      }
    );
  };
}
