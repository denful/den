# The trace's entityKind fallback: an anonymous node's kind comes from its
# nearest kinded ancestor on the include chain, through the trace's own
# entries when entityKindMap has no entry. Driven step by step through the
# real handlers, so the index behind the lookup is exercised as the pipeline
# feeds it. First entry wins, a kindMap entry beats the trace's.
{ denTest, lib, ... }:
let
  steps = [
    {
      p = {
        name = "host";
        __entityKind = "host";
      };
    }
    # same name kinded again with a different kind: the first stays
    {
      p = {
        name = "host";
        __entityKind = "user";
      };
    }
    {
      chain = [ "host" ];
      p.name = "plain";
    }
    {
      p = {
        name = "plain";
        __entityKind = "system";
      };
    }
    # anonymous children derive their kind from the chain
    {
      chain = [ "host" ];
      p = { };
    }
    {
      chain = [
        "plain"
        "host"
      ];
      p = { };
    }
    {
      chain = [ "nope" ];
      p = { };
    }
    {
      chain = [ "host" ];
      kindMap.host = "fromKindMap";
      p = { };
    }
    # a policy batch indexes names, including one already indexed
    {
      fired = {
        host = 1;
        pol = 1;
      };
      ek = "home";
    }
    {
      chain = [ "pol" ];
      p = { };
    }
    # one name in two unmerged chunks: the older entry still answers. Nearly
    # every step indexes (anonymous nodes carry a derived kind), so the index
    # is a binary counter over steps; "c" places the two "a" entries at 11 and
    # 13, which stay in separate chunks (sizes 8, 4, 1).
    {
      p = {
        name = "c";
        __entityKind = "kc";
      };
    }
    {
      p = {
        name = "a";
        __entityKind = "k1";
      };
    }
    {
      p = {
        name = "b";
        __entityKind = "kb";
      };
    }
    {
      p = {
        name = "a";
        __entityKind = "k2";
      };
    }
    {
      chain = [ "a" ];
      p = { };
    }
  ];
  run =
    h:
    let
      go =
        acc: s:
        let
          st0 = acc.state // {
            currentScope = "sc";
            scopedIncludesChain = _: { sc = s.chain or [ ]; };
            entityKindMap = s.kindMap or { };
            scopeContexts = _: { };
          };
          r =
            if s ? fired then
              h."record-fired" {
                state = st0;
                param = {
                  firedPolicies = s.fired;
                  entityKind = s.ek;
                };
              }
            else
              h."resolve-complete" {
                state = st0;
                param = s.p;
              };
        in
        {
          inherit (r) state;
          kinds = acc.kinds ++ [
            (map (e: e.entityKind) (lib.drop (builtins.length (acc.state.entries or [ ])) r.state.entries))
          ];
        };
    in
    (builtins.foldl' go {
      state.entries = [ ];
      kinds = [ ];
    } steps).kinds;
in
{
  flake.tests.internal.fx-trace-entry-kind = {
    test-chain-fallback-and-first-wins = denTest (
      { den, ... }:
      {
        expr = run (den.lib.aspects.fx.trace.tracingHandler "nixos");
        expected = [
          [ "host" ]
          [ "user" ]
          [ "host" ]
          [ "system" ]
          [ "host" ]
          [ "host" ]
          [ null ]
          [ "fromKindMap" ]
          [
            "home"
            "home"
          ]
          [ "home" ]
          [ "kc" ]
          [ "k1" ]
          [ "kb" ]
          [ "k2" ]
          [ "k1" ]
        ];
      }
    );
  };
}
