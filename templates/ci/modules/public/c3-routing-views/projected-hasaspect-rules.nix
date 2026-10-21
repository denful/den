# Behavior matrix for projected (in-context) `hasAspect` on the ANCESTOR-BINDING
# axis — i.e. `host.hasAspect X` answering membership at the ACTIVE (consuming)
# descendant scope. The consuming-entity axis (`user.hasAspect`) is covered by
# deadbugs/projected-hasaspect.nix; the host-own-scope axis by
# internal-api/hasaspect-ancestor-scope.nix. This suite pins the host-binding
# axis with matched positives and negatives.
#
# Formal rule (specs/2026-06-09-projected-hasaspect-v1.md): every in-context
# entity-kind binding answers "is X delivered INTO this active scope", keyed by
# the active (consuming) scope — NOT the binding's own scope.
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
  flake.tests.projected-hasaspect-rules = {

    # R12 +: host sees an aspect it delivers DOWN to its users (provides.to-users),
    # checked from inside the delivered home.
    test-R12-host-sees-provided-POSITIVE = denTest (
      { den, igloo, ... }:
      {
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

    # R4 -: the host's OWN aspect resolves under the HOST scope, so it is NOT
    # visible via host.hasAspect from a USER's home (active scope = user). Matches
    # the spec's scope-specificity rule (and main).
    test-R4-host-own-aspect-not-visible-from-user-NEGATIVE = denTest (
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
        expected = "wrong";
      }
    );

    # R6 -: per-user delivery. `test` is provided ONLY to tux; the host-binding
    # query is keyed by the ACTIVE scope, so tux sees it and sibling pingu does
    # not. (positive + negative in one path.)
    test-R6-per-user-provide-discriminates = denTest (
      { den, igloo, ... }:
      {
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
          pingu = "wrong";
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
