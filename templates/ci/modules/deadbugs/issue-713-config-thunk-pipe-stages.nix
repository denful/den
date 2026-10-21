# A config-dependent quirk value (`{ config, ... }: …`) emitted on the
# consuming scope is deferred to that scope's evalModules fixpoint. Every value
# stage of the pipe must still apply to it once resolved, exactly as it does to
# plain and collected values. Before the fix, filter/transform skipped it, and
# fold/for/withProvenance read the unresolved marker.
{ denTest, lib, ... }:
let
  show = builtins.toJSON;
  sorted = lib.sort lib.lessThan;

  # Two hosts, each emitting a config-dependent `hb`; igloo collects both and
  # runs `stages`, and the `reader` aspect renders what it receives.
  fleet =
    {
      den,
      stages,
      render,
    }:
    {
      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.hosts.x86_64-linux.iceberg.users.alice = { };
      den.quirks.hb.description = "backends";
      den.quirks.hb2.description = "renamed backends";
      den.policies.backends =
        { host, ... }:
        [
          (den.lib.policy.pipe.from "hb" (
            [ (den.lib.policy.pipe.collectAll ({ host, ... }: true)) ] ++ stages den.lib.policy.pipe
          ))
        ];
      den.schema.host.includes = [ den.policies.backends ];
      den.aspects.iceberg.hb =
        { config, ... }:
        {
          addr = "10.0.0.2";
          port = 80;
        };
      den.aspects.igloo = {
        includes = [ den.aspects.reader ];
        hb =
          { config, ... }:
          {
            addr = "10.0.0.1";
            port = 8080;
          };
      };
      den.aspects.reader.nixos =
        { hb, hb2, ... }:
        {
          environment.etc.backends.text = show (render {
            inherit hb hb2;
          });
        };
    };
in
{
  flake.tests.deadbugs.issue-713-config-thunk-pipe-stages = {

    test-transform-applies-to-local-config-thunk = denTest (
      { den, igloo, ... }:
      fleet {
        inherit den;
        stages = pipe: [ (pipe.transform (b: "http://${b.addr}:${toString b.port}")) ];
        render = q: sorted q.hb;
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = show [
          "http://10.0.0.1:8080"
          "http://10.0.0.2:80"
        ];
      }
    );

    test-filter-applies-to-local-config-thunk = denTest (
      { den, igloo, ... }:
      fleet {
        inherit den;
        stages = pipe: [
          (pipe.filter (b: b.port == 80))
          (pipe.transform (b: b.addr))
        ];
        render = q: sorted q.hb;
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = show [ "10.0.0.2" ];
      }
    );

    test-fold-sees-local-config-thunk = denTest (
      { den, igloo, ... }:
      fleet {
        inherit den;
        stages = pipe: [ (pipe.fold (acc: b: acc + b.port) 0) ];
        render = q: q.hb;
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = show [ 8160 ];
      }
    );

    test-for-sees-local-config-thunk = denTest (
      { den, igloo, ... }:
      fleet {
        inherit den;
        stages = pipe: [ (pipe.for (bs: map (b: b.addr) bs)) ];
        render = q: sorted q.hb;
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = show [
          "10.0.0.1"
          "10.0.0.2"
        ];
      }
    );

    test-append-then-transform-local-config-thunk = denTest (
      { den, igloo, ... }:
      fleet {
        inherit den;
        stages = pipe: [
          (pipe.append {
            addr = "10.0.0.9";
            port = 9;
          })
          (pipe.transform (b: b.addr))
        ];
        render = q: sorted q.hb;
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = show [
          "10.0.0.1"
          "10.0.0.2"
          "10.0.0.9"
        ];
      }
    );

    test-provenance-transform-local-config-thunk = denTest (
      { den, igloo, ... }:
      fleet {
        inherit den;
        stages = pipe: [
          (pipe.transform (b: b.addr))
          pipe.withProvenance
        ];
        render = q: sorted (map (e: "${e.value}@${e.source.host.name}") q.hb);
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = show [
          "10.0.0.1@igloo"
          "10.0.0.2@iceberg"
        ];
      }
    );

    test-as-transform-local-config-thunk = denTest (
      { den, igloo, ... }:
      fleet {
        inherit den;
        stages = pipe: [
          (pipe.transform (b: b.addr))
          (pipe.as "hb2")
        ];
        render = q: sorted q.hb2;
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = show [
          "10.0.0.1"
          "10.0.0.2"
        ];
      }
    );

    test-to-transform-local-config-thunk = denTest (
      { den, igloo, ... }:
      fleet {
        inherit den;
        stages = pipe: [
          (pipe.transform (b: b.addr))
          (pipe.to [ den.aspects.reader ])
        ];
        render = q: sorted q.hb;
      }
      // {
        expr = igloo.environment.etc.backends.text;
        expected = show [
          "10.0.0.1"
          "10.0.0.2"
        ];
      }
    );

    # Child → parent: the user's config-dependent value is transformed before
    # pipe.expose lifts it to the host.
    test-expose-transform-config-thunk = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.quirks.prefs.description = "prefs";
        den.policies.prefs =
          { user, ... }:
          [
            (den.lib.policy.pipe.from "prefs" [
              (den.lib.policy.pipe.transform (p: "${p.name}!"))
              den.lib.policy.pipe.expose
            ])
          ];
        den.schema.user.includes = [ den.policies.prefs ];
        den.aspects.tux.prefs =
          { config, ... }:
          {
            name = "tux";
          };
        den.aspects.igloo.includes = [ den.aspects.reader ];
        den.aspects.reader.nixos =
          { prefs, ... }:
          {
            environment.etc.prefs.text = show prefs;
          };
        expr = igloo.environment.etc.prefs.text;
        expected = show [ "tux!" ];
      }
    );

  };
}
