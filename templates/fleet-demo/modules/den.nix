# Fleet topology: two environments, four hosts, haproxy + web backends.
#
# Scope tree:
#   flake
#   +-- flake-system (x86_64-linux)
#   |   +-- [packages, checks, devShells — kept]
#   +-- fleet
#       +-- environment:prod
#       |   +-- host:lb-prod
#       |   +-- host:web-prod-1
#       |   +-- host:web-prod-2
#       +-- environment:staging
#           +-- host:web-staging
{ lib, den, ... }:
{
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];
  den.schema.environment.isEntity = true;

  # Fleet handles host/home instantiation — exclude default walking policies.
  den.schema.flake-system.excludes = [
    den.policies.to-os-outputs
    den.policies.to-hm-outputs
  ];

  den.hosts.x86_64-linux = {
    lb-prod = {
      environment = "prod";
      addr = "10.0.1.1";
      users.deploy = { };
    };
    web-prod-1 = {
      environment = "prod";
      addr = "10.0.1.10";
      users.deploy = { };
    };
    web-prod-2 = {
      environment = "prod";
      addr = "10.0.1.11";
      users.deploy = { };
    };
    web-staging = {
      environment = "staging";
      addr = "10.0.2.10";
      users.deploy = { };
    };
  };

  den.default = {
    nixos.system.stateVersion = "25.11";
    homeManager.home.stateVersion = "25.11";
  };

  den.default.includes = [
    den.batteries.define-user
    den.batteries.hostname
  ];

  den.systems = [ "x86_64-linux" ];
}
