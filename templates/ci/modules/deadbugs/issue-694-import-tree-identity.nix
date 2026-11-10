# An import-tree root is identified by its whole path, not its last segment,
# so two roots sharing a basename (or `provides.host` roots sharing a host
# name) both land, while one root included twice is still one aspect.
{ denTest, lib, ... }:
let
  collide = ../../non-dendritic/collide;
  etc = igloo: builtins.filter (lib.hasPrefix "it-") (builtins.attrNames igloo.environment.etc);
  igloo1 = {
    den.hosts.x86_64-linux.igloo.users.tux = { };
  };
in
{
  flake.tests.import-tree-identity = {
    test-same-basename-both-land = denTest (
      { den, igloo, ... }:
      {
        imports = [ igloo1 ];
        den.aspects.igloo.includes = [
          (den.batteries.import-tree "${collide}/a/disko")
          (den.batteries.import-tree "${collide}/b/disko")
        ];
        expr = etc igloo;
        expected = [
          "it-a-disko"
          "it-b-disko"
        ];
      }
    );
    test-same-root-twice-is-one = denTest (
      { den, igloo, ... }:
      let
        key = den.lib.aspects.fx.identity.key;
      in
      {
        imports = [ igloo1 ];
        den.aspects.igloo.includes = [
          (den.batteries.import-tree "${collide}/a/disko")
          (den.batteries.import-tree "${collide}/a/disko")
        ];
        expr = {
          etc = etc igloo;
          one =
            key (den.batteries.import-tree "${collide}/a/disko")
            == key (den.batteries.import-tree "${collide}/a/disko");
        };
        expected = {
          etc = [ "it-a-disko" ];
          one = true;
        };
      }
    );
    test-two-host-roots-both-land = denTest (
      { den, igloo, ... }:
      {
        imports = [ igloo1 ];
        den.aspects.igloo.includes = [
          (den.batteries.import-tree.provides.host "${collide}/hosts-a")
          (den.batteries.import-tree.provides.host "${collide}/hosts-b")
        ];
        expr = etc igloo;
        expected = [
          "it-hosts-a-igloo"
          "it-hosts-b-igloo"
        ];
      }
    );
    test-exclude-one-root = denTest (
      { den, igloo, ... }:
      {
        imports = [ igloo1 ];
        den.aspects.igloo.includes = [
          (den.batteries.import-tree "${collide}/a/disko")
          (den.batteries.import-tree "${collide}/b/disko")
        ];
        den.aspects.igloo.excludes = [ (den.batteries.import-tree "${collide}/a/disko") ];
        expr = etc igloo;
        expected = [ "it-b-disko" ];
      }
    );
    test-exclude-battery = denTest (
      { den, igloo, ... }:
      {
        imports = [ igloo1 ];
        den.aspects.igloo.includes = [
          (den.batteries.import-tree "${collide}/a/disko")
          (den.batteries.import-tree "${collide}/b/disko")
        ];
        den.aspects.igloo.excludes = [ den.batteries.import-tree ];
        expr = etc igloo;
        expected = [ ];
      }
    );
    # Two store objects both named `source`, the same relative path under each.
    test-same-tail-distinct-store-roots = denTest (
      { den, igloo, ... }:
      let
        src =
          sub:
          builtins.path {
            path = collide + "/${sub}";
            name = "source";
          };
      in
      {
        imports = [ igloo1 ];
        den.aspects.igloo.includes = [
          (den.batteries.import-tree "${src "a"}/disko")
          (den.batteries.import-tree "${src "b"}/disko")
        ];
        expr = etc igloo;
        expected = [
          "it-a-disko"
          "it-b-disko"
        ];
      }
    );
    # Text that only contains a hash-like run is shown as written.
    test-display-keeps-non-store-text = denTest (
      { den, ... }:
      let
        h = "0123456789abcdfghijklmnpqrsvwxyz";
        show = den.lib.argsName.withoutStoreHash;
      in
      {
        expr = map show [
          "my-${h}-thing"
          "user-aspects-accept([\"${h}-bob\"])"
          "a${h}-b"
          "unfree([\"vscode\"])"
          "import-tree(${h}-source/hosts/igloo)"
          "${builtins.storeDir}/${h}-source/x"
        ];
        expected = [
          "my-${h}-thing"
          "user-aspects-accept([\"${h}-bob\"])"
          "a${h}-b"
          "unfree([\"vscode\"])"
          "import-tree(source/hosts/igloo)"
          "source/x"
        ];
      }
    );
    test-display-strips-store-hash = denTest (
      { den, ... }:
      let
        root = builtins.path {
          path = collide + "/a";
          name = "source";
        };
      in
      {
        expr = den.lib.argsName.withoutStoreHash (
          den.lib.aspects.fx.identity.key (den.batteries.import-tree "${root}/disko")
        );
        expected = "den/batteries/import-tree/import-tree(source/disko)";
      }
    );
  };
}
