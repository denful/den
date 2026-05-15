# Fleet topology: two environments, four hosts, policy-driven user access.
#
# Scope tree:
#   flake
#   +-- fleet
#       +-- environment:prod
#       |   +-- host:lb-prod
#       |   |   +-- user:alice  (via prod/admin)
#       |   +-- host:web-prod-1
#       |   |   +-- user:alice  (via prod/admin)
#       |   +-- host:web-prod-2
#       |       +-- user:alice  (via prod/admin)
#       +-- environment:staging
#           +-- host:web-staging
#               +-- user:alice  (via staging/admin)
#               +-- user:bob    (via staging/deploy)
{ lib, den, ... }:
{
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];
  den.schema.environment.isEntity = true;

  # Fleet handles host/home instantiation — exclude default walking policies.
  den.schema.flake-system.excludes = [
    den.policies.system-to-os-outputs
    den.policies.system-to-hm-outputs
  ];

  den.hosts.x86_64-linux = {
    lb-prod = {
      environment = "prod";
      addr = "10.0.1.1";
    };
    web-prod-1 = {
      environment = "prod";
      addr = "10.0.1.10";
    };
    web-prod-2 = {
      environment = "prod";
      addr = "10.0.1.11";
    };
    web-staging = {
      environment = "staging";
      addr = "10.0.2.10";
    };
  };

  den.default = {
    nixos.system.stateVersion = "25.11";
    homeManager.home.stateVersion = "25.11";
  };

  den.default.includes = [
    den.batteries.define-user
    den.batteries.hostname
    den.aspects.ssh-keys
  ];

  den.systems = [ "x86_64-linux" ];
}
