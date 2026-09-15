{
  inputs,
  lib,
  den,
  ...
}:
{
  den.batteries.import-tree.description = ''
    Recursively imports non-dendritic .nix files depending on their Nix configuration `class`.

    This can be used to help migrating from huge existing setups.


    ```
      # this is at <repo>/modules/non-dendritic.nix
      den.aspects.my-laptop.includes = [
        (den.batteries.import-tree.provides.host ../non-dendritic)
      ]
    ```

    With following structure, it will automatically load modules depending on their class.

    ```
       <repo>/
         modules/
           non-dendritic.nix # configures this aspect
         non-dendritic/ # name is just an example here
           hosts/
             my-laptop/
               _nixos/          # a directory for `nixos` class
                 auto-generated-hardware.nix # any nixos module
               _darwin/ 
                 foo.nix
               _homeManager/
                 me.nix
    ```

    ## Requirements

      - inputs.import-tree

    ## Usage

      this aspect can be included explicitly on any aspect:

          # example: will import ./disko/_nixos files automatically.
          den.aspects.my-disko.includes = [ (den.batteries.import-tree ./disko/) ];

      or it can be default imported per host/user/home:

          # load from ./hosts/<host>/_nixos
          den.schema.host.includes = [ (den.batteries.import-tree.provides.host ./hosts) ];

          # load from ./users/<user>/{_homeManager, _nixos}
          den.schema.user.includes = [ (den.batteries.import-tree.provides.user ./users) ];

          # load from ./homes/<home>/_homeManager
          den.schema.home.includes = [ (den.batteries.import-tree.provides.home ./homes) ];

      you are also free to create your own auto-imports layout following the implementation of these.
  '';

  den.batteries.import-tree.__functor =
    _: root:
    let
      # Scan for _<class> directories under root and emit per-class imports.
      # This avoids depending on the scope's `class` argument, which the
      # fx-pipeline only provides once per scope (not once per class).
      rootStr = toString root;
      entries = lib.optionalAttrs (builtins.pathExists rootStr) (builtins.readDir rootStr);
      classEntries = lib.filterAttrs (name: type: type == "directory" && lib.hasPrefix "_" name) entries;
      aspect = lib.mapAttrs' (dirName: _: {
        name = lib.removePrefix "_" dirName;
        value.imports = [ (inputs.import-tree "${rootStr}/${dirName}") ];
      }) classEntries;
    in
    {
      name = "import-tree(${baseNameOf rootStr})";
      meta.aspect-chain = [
        "den"
        "batteries"
      ];
    }
    // aspect;

  den.batteries.import-tree.provides = {
    host = root: { host, ... }: den.batteries.import-tree "${toString root}/${host.name}";
    home = root: { home, ... }: den.batteries.import-tree "${toString root}/${home.name}";
    user = root: { user, ... }: den.batteries.import-tree "${toString root}/${user.name}";
  };
}
