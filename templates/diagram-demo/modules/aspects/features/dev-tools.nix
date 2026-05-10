{ den, ... }:
{
  den.aspects.dev-tools = {
    includes = [
      (den.batteries.unfree [ "vscode" ])
    ];
    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          ripgrep
          fd
          jq
        ];
      };
  };
}
