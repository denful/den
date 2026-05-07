# deploy: service account user present on all hosts.
{ ... }:
{
  den.aspects.deploy = {
    homeManager.home.stateVersion = "25.05";
  };
}
