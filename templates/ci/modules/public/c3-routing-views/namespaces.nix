{ denTest, inputs, ... }:
{

  flake.tests.namespaces = {

    test-local-definition = denTest (
      { den, ns, ... }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        ns.foo.nixos.truth = true;
        expr = ns.foo ? nixos;
        expected = true;
      }
    );

    test-merge-definition = denTest (
      { den, ns, ... }:
      {
        imports =
          let
            external.denful.ns.foo.nixos.name = [ "source" ];
          in
          [ (inputs.den.namespace "ns" [ external ]) ];
        expr = ns.foo ? nixos;
        expected = true;
      }
    );

    test-multiple-sources-merged = denTest (
      {
        den,
        lib,
        ns,
        igloo,
        ...
      }:
      let
        srcA.denful.ns.gear.nixos.data = [ "from-A" ];
        srcB.denful.ns.gear.nixos.data = [ "from-B" ];
        dataMod = {
          options.data = lib.mkOption { type = lib.types.listOf lib.types.str; };
        };
      in
      {
        imports = [
          (inputs.den.namespace "ns" [
            srcA
            srcB
            true
          ])
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        ns.gear.nixos.data = [ "local" ];
        ns.gear.nixos.imports = [ dataMod ];
        den.aspects.igloo.includes = [ ns.gear ];

        expr = lib.sort (a: b: a < b) igloo.data;
        expected = [
          "from-A"
          "from-B"
          "local"
        ];
      }
    );

    test-provides-underscore-syntax = denTest (
      { den, ns, ... }:
      {
        imports = [ (inputs.den.namespace "ns" true) ];
        ns.root.provides.branch.provides.leaf.nixos.truth = true;

        expr = ns.root._.branch._.leaf ? nixos;
        expected = true;
      }
    );

    test-namespace-as-flake-output = denTest (
      {
        den,
        ns,
        config,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" true) ];
        ns.foo.nixos.truth = true;

        expr = config.flake.denful ? ns;
        expected = true;
      }
    );

  };

}
