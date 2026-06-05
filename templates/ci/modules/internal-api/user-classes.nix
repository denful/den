{ denTest, ... }:
{
  flake.tests.user-classes = {

    test-default-classes = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = den.hosts.x86_64-linux.igloo.users.tux.classes;
        expected = [ "homeManager" ];
      }
    );

    test-multiple-classes = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [
          "homeManager"
          "maid"
        ];

        expr = lib.sort (a: b: a < b) den.hosts.x86_64-linux.igloo.users.tux.classes;
        expected = [
          "homeManager"
          "maid"
        ];
      }
    );

    test-aspect-has-all-user-classes = denTest (
      {
        den,
        lib,
        ...
      }:
      let
        resolve =
          class:
          let
            mod = den.lib.aspects.resolve class den.aspects.tux;
            m = {
              options.tag = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
            };
          in
          (lib.evalModules {
            modules = [
              mod
              m
            ];
          }).config.tag;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [
          "homeManager"
          "maid"
        ];

        den.aspects.tux.maid.tag = "maid-tag";
        den.aspects.tux.homeManager.tag = "hm-tag";

        expr = lib.sort (a: b: a < b) [
          (resolve "maid")
          (resolve "homeManager")
        ];
        expected = [
          "hm-tag"
          "maid-tag"
        ];
      }
    );

  };
}
