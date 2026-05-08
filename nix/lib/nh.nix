{ lib, den, ... }:
let

  mkApp =
    getCommand:
    {
      outPrefix ? [ ],
      fromFlake ? true,
      fromPath ? ".",
      defaultAction ? "build",
      defaultArgs ? [ ],
    }:
    pkgs: item:
    pkgs.writeShellApplication {
      name = item.name;
      runtimeInputs = [ pkgs.nh ];
      text =
        let
          command = getCommand item;
          attr = if command == "home" then "" else lib.concatStringsSep "." (outPrefix ++ item.intoAttr);
          from =
            (
              if fromFlake then
                [ "${fromPath}#${attr}" ]
              else
                [
                  "--file"
                  fromPath
                  attr
                ]
            )
            ++ (lib.optionals (command == "home") [
              "-c"
              item.name
            ]);

          args = lib.concatStringsSep " " (from ++ defaultArgs);
        in
        ''
          action="''${1:-${defaultAction}}"
          shift || true
          exec nh ${command} "$action" ${args} "$@"
        '';
    };

  os = mkApp (
    host:
    {
      darwin = "darwin";
      nixos = "os";
    }
    .${host.class}
  );
  hm = mkApp (_: "home");

  hosts = lib.concatMap lib.attrValues (lib.attrValues den.hosts);
  homes = lib.concatMap lib.attrValues (lib.attrValues den.homes);

  hostApps = args: pkgs: map (os args pkgs) hosts;
  homeApps = args: pkgs: map (hm args pkgs) homes;
  denApps = args: pkgs: (hostApps args pkgs) ++ (homeApps args pkgs);

  denShell =
    args: pkgs:
    pkgs.mkShell {
      buildInputs = [ pkgs.nh ] ++ (denApps args pkgs);
    };

  denPackages =
    args: pkgs:
    lib.listToAttrs (
      map (a: {
        name = a.name;
        value = a;
      }) (denApps args pkgs)
    );

in
{
  inherit
    denPackages
    denShell
    homeApps
    hostApps
    denApps
    ;
}
