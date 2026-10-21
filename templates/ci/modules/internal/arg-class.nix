# Pure-fn tests for the arg classifier over the schema entity DAG.
# Exercises isDescendantOf (parent-chain walk, cycle-safe) and the
# convention-based childrenOf enumeration. No entity wiring — these call
# den.lib.aspects.fx.argClass.* directly against literal schemas.
{ denTest, lib, ... }:
let
  schema = {
    tier = { };
    host.parent = "tier";
    user.parent = "host";
    home.parent = "host";
  };
  cyclic = {
    a.parent = "b";
    b.parent = "a";
  };
in
{
  flake.tests.arg-class = {

    test-isDescendantOf-direct = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.argClass.isDescendantOf schema "host" "user";
        expected = true;
      }
    );

    test-isDescendantOf-transitive = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.argClass.isDescendantOf schema "tier" "user";
        expected = true;
      }
    );

    test-isDescendantOf-self = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.argClass.isDescendantOf schema "host" "host";
        expected = false;
      }
    );

    test-isDescendantOf-ancestor-inverted = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.argClass.isDescendantOf schema "user" "host";
        expected = false;
      }
    );

    test-isDescendantOf-null-scope = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.argClass.isDescendantOf schema null "user";
        expected = false;
      }
    );

    test-isDescendantOf-cycle-safe = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.argClass.isDescendantOf cyclic "x" "a";
        expected = false;
      }
    );

    test-childrenOf-convention = denTest (
      { den, ... }:
      {
        expr = lib.sort builtins.lessThan (
          map (c: c.n) (
            den.lib.aspects.fx.argClass.childrenOf {
              users = {
                tux = {
                  n = 1;
                };
                pingu = {
                  n = 2;
                };
              };
            } "user"
          )
        );
        expected = [
          1
          2
        ];
      }
    );

    test-isDescendantOf-unknown-kind = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.argClass.isDescendantOf {
          user.parent = "host";
          host = { };
        } "host" "ghost";
        expected = false;
      }
    );

    test-childrenOf-absent = denTest (
      { den, ... }:
      {
        expr = den.lib.aspects.fx.argClass.childrenOf { } "user";
        expected = [ ];
      }
    );

  };
}
