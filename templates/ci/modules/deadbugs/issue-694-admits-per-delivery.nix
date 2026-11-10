# admits decides each delivery a policy include carries, wherever it sits in the
# include (a list at any depth, a list value, a wrapper): a withheld forward is
# dropped and its admitted and local siblings stay, in either order. Reported in
# an external review.
{ denTest, lib, ... }:
let
  tryV =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "THREW";
  fwd =
    den: host: user: rcv: from: into:
    den.batteries.forward {
      each = [ true ];
      fromClass = _: from;
      intoClass = _: into;
      intoPath = _: [ ];
      fromAspect = _: den.lib.resolveEntity "user" { inherit host user; };
      receiver = rcv;
    };
  # shape: host -> user -> fHost -> fUser -> include value
  base = den: shape: {
    den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
    den.aspects.tux.homeManager.home.stateVersion = "25.11";
    den.aspects.tux.policies.fw =
      { host, user, ... }:
      [
        (den.lib.policy.include (
          shape (fwd den host user host "smug" host.class) (fwd den host user user "smug2" "homeManager")
        ))
      ];
    den.aspects.tux.includes = [ den.aspects.tux.policies.fw ];
    den.aspects.tux.smug.environment.etc.fw.text = "x";
    den.aspects.tux.smug2.home.sessionVariables.FW2 = "x";
  };
  hostGot = igloo: igloo.environment.etc ? fw;
  userGot = igloo: igloo.home-manager.users.tux.home.sessionVariables ? FW2;
  locGot = igloo: igloo.home-manager.users.tux.home.sessionVariables ? LOC;
  dd = {
    den.aspects.igloo.admits.default = "deny";
  };
  denyFw = den: { den.aspects.igloo.admits.deny = [ den.aspects.tux.policies.fw ]; };
in
{
  flake.tests.admits-per-delivery = {
    # Controls.
    test-c0-direct-no-admits-lands = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den (fh: fu: fh)) ];
        expr = tryV (hostGot igloo);
        expected = true;
      }
    );
    test-c0b-list-no-admits-lands = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den (fh: fu: { includes = [ [ fh ] ]; })) ];
        expr = tryV (hostGot igloo);
        expected = true;
      }
    );
    test-c0c-user-forward-no-admits-lands = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den (fh: fu: fu)) ];
        expr = tryV (userGot igloo);
        expected = true;
      }
    );
    # 1. Denied receiver under nested lists (default deny: must throw).
    test-a1-direct-default-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: fh))
          dd
        ];
        expr = tryV (hostGot igloo);
        expected = "THREW";
      }
    );
    test-a2-one-list-level-default-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: { includes = [ [ fh ] ]; }))
          dd
        ];
        expr = tryV (hostGot igloo);
        expected = "THREW";
      }
    );
    test-a3-two-list-levels-default-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: { includes = [ [ [ fh ] ] ]; }))
          dd
        ];
        expr = tryV (hostGot igloo);
        expected = "THREW";
      }
    );
    # 4. Equivalent payloads: direct (a1), as a list value, and through a wrapper.
    test-a4-list-value-default-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: [ fh ]))
          dd
        ];
        expr = tryV (hostGot igloo);
        expected = "THREW";
      }
    );
    test-a5-wrapper-default-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: { includes = [ fh ]; }))
          dd
        ];
        expr = tryV (hostGot igloo);
        expected = "THREW";
      }
    );
    # The same four under admits.deny (silent withhold).
    test-d1-direct-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: fh))
          (denyFw den)
        ];
        expr = tryV (hostGot igloo);
        expected = false;
      }
    );
    test-d2-one-list-level-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: { includes = [ [ fh ] ]; }))
          (denyFw den)
        ];
        expr = tryV (hostGot igloo);
        expected = false;
      }
    );
    test-d4-list-value-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: [ fh ]))
          (denyFw den)
        ];
        expr = tryV (hostGot igloo);
        expected = false;
      }
    );
    test-d5-wrapper-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (fh: fu: { includes = [ fh ]; }))
          (denyFw den)
        ];
        expr = tryV (hostGot igloo);
        expected = false;
      }
    );
    # 2. Two receivers, different decisions (igloo denies the policy; tux admits), both orders.
    test-b1-host-then-user = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (
            fh: fu: {
              includes = [
                fh
                fu
              ];
            }
          ))
          (denyFw den)
        ];
        expr = tryV {
          host = hostGot igloo;
          user = userGot igloo;
        };
        expected = {
          host = false;
          user = true;
        };
      }
    );
    test-b2-user-then-host = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (
            fh: fu: {
              includes = [
                fu
                fh
              ];
            }
          ))
          (denyFw den)
        ];
        expr = tryV {
          host = hostGot igloo;
          user = userGot igloo;
        };
        expected = {
          host = false;
          user = true;
        };
      }
    );
    test-b3-user-then-host-default-deny = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (
            fh: fu: {
              includes = [
                fu
                fh
              ];
            }
          ))
          dd
        ];
        expr = tryV {
          host = hostGot igloo;
          user = userGot igloo;
        };
        expected = "THREW";
      }
    );
    # 3. Denied forward beside an ordinary local include.
    test-l1-denied-forward-and-local = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (
            fh: fu: {
              includes = [
                fh
                { homeManager.home.sessionVariables.LOC = "x"; }
              ];
            }
          ))
          (denyFw den)
        ];
        expr = tryV {
          host = hostGot igloo;
          loc = locGot igloo;
        };
        expected = {
          host = false;
          loc = true;
        };
      }
    );
    test-l2-local-then-denied-forward = denTest (
      { den, igloo, ... }:
      {
        imports = [
          (base den (
            fh: fu: {
              includes = [
                { homeManager.home.sessionVariables.LOC = "x"; }
                fh
              ];
            }
          ))
          (denyFw den)
        ];
        expr = tryV {
          host = hostGot igloo;
          loc = locGot igloo;
        };
        expected = {
          host = false;
          loc = true;
        };
      }
    );
  };
}
