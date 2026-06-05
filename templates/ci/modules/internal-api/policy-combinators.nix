{ denTest, ... }:
{
  flake.tests.policy-combinators = {

    # policy.when with true predicate — fn fires, returns effects
    test-when-true-fires = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            p = {
              __isPolicy = true;
              name = "test-pol";
              fn = _: [ "fired" ];
            };
            wrapped = den.lib.policy.when (_: true) p;
          in
          {
            isPolicy = wrapped.__isPolicy;
            name = wrapped.name;
            result = wrapped.fn { };
          };
        expected = {
          isPolicy = true;
          name = "test-pol";
          result = [ "fired" ];
        };
      }
    );

    # policy.when with false predicate — fn returns []
    test-when-false-skips = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            p = {
              __isPolicy = true;
              name = "guarded";
              fn = _: [ "should-not-appear" ];
            };
            wrapped = den.lib.policy.when (_: false) p;
          in
          wrapped.fn { };
        expected = [ ];
      }
    );

    # policy.when with list input — produces list of wrapped values
    test-when-list-input = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            p1 = {
              __isPolicy = true;
              name = "pol-a";
              fn = _: [ "a" ];
            };
            p2 = {
              __isPolicy = true;
              name = "pol-b";
              fn = _: [ "b" ];
            };
            wrapped = den.lib.policy.when (_: true) [
              p1
              p2
            ];
          in
          {
            count = builtins.length wrapped;
            names = map (w: w.name) wrapped;
            results = map (w: w.fn { }) wrapped;
            allPolicy = builtins.all (w: w.__isPolicy) wrapped;
          };
        expected = {
          count = 2;
          names = [
            "pol-a"
            "pol-b"
          ];
          results = [
            [ "a" ]
            [ "b" ]
          ];
          allPolicy = true;
        };
      }
    );

    # policy.for — wraps with id_hash check
    test-for-matching-entity = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            entity = {
              id_hash = "abc123";
              name = "target";
            };
            p = {
              __isPolicy = true;
              name = "scoped";
              fn = _: [ "matched" ];
            };
            wrapped = den.lib.policy.for entity p;
            # Mock context where __entityKind points to a matching entity
            ctx = {
              __entityKind = "host";
              host = {
                id_hash = "abc123";
                name = "target";
              };
            };
          in
          {
            isPolicy = wrapped.__isPolicy;
            name = wrapped.name;
            result = wrapped.fn ctx;
          };
        expected = {
          isPolicy = true;
          name = "scoped";
          result = [ "matched" ];
        };
      }
    );

    # policy.for — non-matching entity returns []
    test-for-non-matching-entity = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            entity = {
              id_hash = "abc123";
            };
            p = {
              __isPolicy = true;
              name = "scoped";
              fn = _: [ "should-not-appear" ];
            };
            wrapped = den.lib.policy.for entity p;
            ctx = {
              __entityKind = "host";
              host = {
                id_hash = "different";
              };
            };
          in
          wrapped.fn ctx;
        expected = [ ];
      }
    );

    # Identity preservation — wrapped policy .name matches inner policy's name
    test-name-preserved = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            p = {
              __isPolicy = true;
              name = "my-important-policy";
              fn = _: [ ];
            };
            wrappedFor = den.lib.policy.for { id_hash = "x"; } p;
            wrappedWhen = den.lib.policy.when (_: true) p;
          in
          {
            forName = wrappedFor.name;
            whenName = wrappedWhen.name;
          };
        expected = {
          forName = "my-important-policy";
          whenName = "my-important-policy";
        };
      }
    );

    # __isPolicy tag present on all wrapped values
    test-is-policy-tag = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            p = {
              __isPolicy = true;
              name = "tagged";
              fn = _: [ ];
            };
            wrappedFor = den.lib.policy.for { id_hash = "x"; } p;
            wrappedWhen = den.lib.policy.when (_: true) p;
          in
          {
            forTag = wrappedFor.__isPolicy;
            whenTag = wrappedWhen.__isPolicy;
          };
        expected = {
          forTag = true;
          whenTag = true;
        };
      }
    );

    # Composition — policy.when pred (policy.for entity P) works
    test-composition = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            entity = {
              id_hash = "e1";
            };
            p = {
              __isPolicy = true;
              name = "composed";
              fn = _: [ "composed-result" ];
            };
            composed = den.lib.policy.when (ctx: ctx.flag or false) (den.lib.policy.for entity p);
            # Both guards pass
            ctxPass = {
              __entityKind = "host";
              host.id_hash = "e1";
              flag = true;
            };
            # Predicate fails
            ctxPredFail = {
              __entityKind = "host";
              host.id_hash = "e1";
              flag = false;
            };
            # Entity fails
            ctxEntityFail = {
              __entityKind = "host";
              host.id_hash = "other";
              flag = true;
            };
          in
          {
            bothPass = composed.fn ctxPass;
            predFails = composed.fn ctxPredFail;
            entityFails = composed.fn ctxEntityFail;
            name = composed.name;
          };
        expected = {
          bothPass = [ "composed-result" ];
          predFails = [ ];
          entityFails = [ ];
          name = "composed";
        };
      }
    );

    # policy.for — list of entities matches any
    test-for-entity-list = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            p = {
              __isPolicy = true;
              name = "multi-target";
              fn = _: [ "matched" ];
            };
            wrapped = den.lib.policy.for [
              { id_hash = "aaa"; }
              { id_hash = "bbb"; }
            ] p;
            ctxFirst = {
              __entityKind = "host";
              host.id_hash = "aaa";
            };
            ctxSecond = {
              __entityKind = "host";
              host.id_hash = "bbb";
            };
            ctxNeither = {
              __entityKind = "host";
              host.id_hash = "ccc";
            };
          in
          {
            matchFirst = wrapped.fn ctxFirst;
            matchSecond = wrapped.fn ctxSecond;
            matchNeither = wrapped.fn ctxNeither;
            name = wrapped.name;
          };
        expected = {
          matchFirst = [ "matched" ];
          matchSecond = [ "matched" ];
          matchNeither = [ ];
          name = "multi-target";
        };
      }
    );

    # policy.for — list with mixed id_hash presence
    test-for-mixed-hash-list = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            p = {
              __isPolicy = true;
              name = "mixed";
              fn = _: [ "hit" ];
            };
            wrapped = den.lib.policy.for [
              { id_hash = "aaa"; }
              { name = "no-hash"; }
            ] p;
            ctxMatch = {
              __entityKind = "host";
              host.id_hash = "aaa";
            };
            ctxNoHash = {
              __entityKind = "host";
              host = {
                name = "no-hash";
              };
            };
          in
          {
            matchesFirst = wrapped.fn ctxMatch;
            noHashNeverMatches = wrapped.fn ctxNoHash;
          };
        expected = {
          matchesFirst = [ "hit" ];
          noHashNeverMatches = [ ];
        };
      }
    );

    # policy.for — entity without id_hash never matches
    test-for-no-id-hash = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            p = {
              __isPolicy = true;
              name = "no-hash";
              fn = _: [ "should-not-fire" ];
            };
            wrapped = den.lib.policy.for { name = "bare"; } p;
            ctx = {
              __entityKind = "host";
              host = {
                name = "bare";
              };
            };
          in
          wrapped.fn ctx;
        expected = [ ];
      }
    );

    # Raw function input — unwrapped fn gets name = "<inline>"
    test-raw-function-input = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.h.users.u = { };
        expr =
          let
            rawFn = _: [ "raw" ];
            wrappedFor = den.lib.policy.for { id_hash = "x"; } rawFn;
            wrappedWhen = den.lib.policy.when (_: true) rawFn;
          in
          {
            forName = wrappedFor.name;
            whenName = wrappedWhen.name;
            forResult = wrappedFor.fn {
              __entityKind = "host";
              host.id_hash = "x";
            };
            whenResult = wrappedWhen.fn { };
          };
        expected = {
          forName = "<inline>";
          whenName = "<inline>";
          forResult = [ "raw" ];
          whenResult = [ "raw" ];
        };
      }
    );

  };
}
