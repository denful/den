{ ... }:
{
  # Renamed from `shell` to avoid collision with gwenodai's shell aspect.
  den.aspects.demo-shell = {
    homeManager.programs.fish.enable = true;
    homeManager.programs.starship.enable = true;
  };
}
