denGen: {
  nh =
    hostNames:
    # shortcut: fromFlake=false (non-flake invocation) ignored, implement when Den's output for it is measured.
    { fromFlake ? true, ... }:
    pkgs:
    builtins.listToAttrs (
      map (h: {
        name = h;
        value = pkgs.writeShellApplication {
          name = h;
          runtimeInputs = [ pkgs.nh ];
          text = ''
            action="''${1:-build}"
            shift || true
            exec nh os "$action" .#nixosConfigurations.${h} "$@"
          '';
        };
      }) hostNames
    );
}
