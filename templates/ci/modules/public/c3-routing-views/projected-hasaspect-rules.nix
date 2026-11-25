# Behavior matrix for in-context `hasAspect` on the ANCESTOR-BINDING axis:
# `host.hasAspect X` read from inside a user's home. The consuming-entity axis
# (`user.hasAspect`) is covered by deadbugs/projected-hasaspect.nix; the
# host-own-scope axis by public/c2-policies-outputs/hasaspect-ancestor-scope.nix.
#
# Rule: `<entity>.hasAspect X`, taken as a class module's argument, is true
# when content of X, or of an aspect X includes, lands in that entity's own
# class, and the answer is the same from whichever scope asks. The full matrix
# is in deadbugs/hasaspect-lands-in-class.nix.
{ denTest, lib, ... }:
let
  # An effect homeManager aspect that reports, via home.username, whether the
  # host (the ancestor binding) sees `probe` at the active (this home's) scope.
  effectFor = probe: {
    homeManager =
      { host, ... }:
      {
        home.username = if host.hasAspect probe then lib.mkForce "right" else lib.mkForce "wrong";
      };
  };
in
{
  flake.tests.c3.projected-hasaspect-rules = {

    # R12 +: host sees an aspect it delivers DOWN to its users (provides.to-users),
    # checked from inside the delivered home.
    test-R12-host-sees-provided-POSITIVE = denTest (
      { den, igloo, ... }:
      {
        # #694: these hosts accept their users' host-class output, which is
        # what this cell exercises.
        den.schema.host.includes = [ den.batteries.user-aspects ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.test.nixos = { };
        den.aspects.effect = effectFor den.aspects.test;
        den.aspects.igloo.provides.to-users.includes = [
          den.aspects.test
          den.aspects.effect
        ];
        expr = igloo.home-manager.users.tux.home.username;
        expected = "right";
      }
    );

    # R12 -: host does NOT report an aspect it never provided. `other` exists but
    # is never delivered anywhere, so it is in no bucket.
    test-R12-host-absent-when-unprovided-NEGATIVE = denTest (
      { den, igloo, ... }:
      {
        # #694: these hosts accept their users' host-class output, which is
        # what this cell exercises.
        den.schema.host.includes = [ den.batteries.user-aspects ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.test.nixos = { };
        den.aspects.other.nixos = { };
        den.aspects.effect = effectFor den.aspects.other;
        den.aspects.igloo.provides.to-users.includes = [
          den.aspects.test
          den.aspects.effect
        ];
        expr = igloo.home-manager.users.tux.home.username;
        expected = "wrong";
      }
    );

    # R4: the host's own aspect is in the host's nixos, so host.hasAspect is
    # true from a user's home too.
    test-R4-host-own-aspect-visible-from-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.hostonly.nixos = { };
        den.aspects.effect = effectFor den.aspects.hostonly;
        den.aspects.igloo = {
          includes = [ den.aspects.hostonly ];
          provides.to-users.includes = [ den.aspects.effect ];
        };
        expr = igloo.home-manager.users.tux.home.username;
        expected = "right";
      }
    );

    # R6: `test` is provided only to tux, and its nixos reaches the host
    # through tux, so the host has it, and host.hasAspect answers true from
    # pingu's home as well.
    test-R6-per-user-provide-reaches-host-for-every-user = denTest (
      { den, igloo, ... }:
      {
        # #694: these hosts accept their users' host-class output, which is
        # what this cell exercises.
        den.schema.host.includes = [ den.batteries.user-aspects ];
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.test.nixos = { };
        den.aspects.effect = effectFor den.aspects.test;
        den.aspects.igloo = {
          provides.tux.includes = [
            den.aspects.test
            den.aspects.effect
          ];
          provides.pingu.includes = [ den.aspects.effect ];
        };
        expr = {
          tux = igloo.home-manager.users.tux.home.username;
          pingu = igloo.home-manager.users.pingu.home.username;
        };
        expected = {
          tux = "right";
          pingu = "right";
        };
      }
    );

    # R2 -: per-active-path on the host-binding axis. `test` is provided to-users
    # on igloo only; the same user `tux` under iceberg must NOT see it.
    test-R2-multi-host-host-binding-discriminates = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {
        # #694: these hosts accept their users' host-class output, which is
        # what this cell exercises.
        den.schema.host.includes = [ den.batteries.user-aspects ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.test.nixos = { };
        den.aspects.effect = effectFor den.aspects.test;
        den.aspects.igloo.provides.to-users.includes = [
          den.aspects.test
          den.aspects.effect
        ];
        den.aspects.iceberg.provides.to-users.includes = [ den.aspects.effect ];
        expr = {
          igloo = igloo.home-manager.users.tux.home.username;
          iceberg = iceberg.home-manager.users.tux.home.username;
        };
        expected = {
          igloo = "right";
          iceberg = "wrong";
        };
      }
    );

  };
}
