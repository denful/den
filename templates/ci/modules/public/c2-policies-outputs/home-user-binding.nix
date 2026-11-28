# How a standalone home binds its `user` and `host`. A home's user is the
# registry user `den.users.<userName>` (#781): the user's identity fields
# below, with `classes` the home's own; on a declared host, that host's view.
{ denTest, ... }:
let
  homeOf =
    den: system: name:
    den.homes.${system}.${name};

  # The home's own view of osConfig: the hostName when wired, "none" otherwise.
  osProbe = den: {
    includes = [ den.provides.define-user ];
    homeManager =
      args:
      let
        os = args.osConfig or null;
      in
      {
        home.file."OS".text = if os == null then "none" else os.networking.hostName;
      };
  };
  osOf = config: out: config.flake.homeConfigurations.${out}.config.home.file."OS".text;

  syntheticUser = {
    name = "tux";
    userName = "tux";
    classes = [ "homeManager" ];
  };
  # The binding's identity: a home's user carries the registry user's whole
  # record, aspect included, which no cell compares whole.
  userOf = u: {
    inherit (u) name userName classes;
  };
in
{
  flake.tests.home-user-binding = {

    test-plain-home = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux.tux = { };
        den.aspects.tux.includes = [ (osProbe den) ];

        expr =
          let
            home = homeOf den "x86_64-linux" "tux";
          in
          {
            inherit (home) host;
            user = userOf home.user;
            os = osOf config "tux";
          };
        expected = {
          host = null;
          user = syntheticUser;
          os = "none";
        };
      }
    );

    test-named-home-undeclared-host = denTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux."tux@astra" = { };
        den.aspects.tux.includes = [ (osProbe den) ];

        expr =
          let
            home = homeOf den "x86_64-linux" "tux@astra";
          in
          {
            inherit (home) host;
            user = userOf home.user;
            os = osOf config "tux@astra";
            hostBuilt = config.flake ? nixosConfigurations && config.flake.nixosConfigurations ? astra;
          };
        expected = {
          host = {
            name = "astra";
            system = "x86_64-linux";
          };
          user = syntheticUser;
          os = "none";
          hostBuilt = false;
        };
      }
    );

    test-named-home-declared-host-with-user = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = {
          classes = [ "user" ];
          email = "tux@igloo";
        };
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";
        den.aspects.tux.includes = [ (osProbe den) ];

        expr =
          let
            home = homeOf den "x86_64-linux" "tux@igloo";
          in
          {
            hostName = home.host.name;
            hostClass = home.host.class;
            # The host's view of the user, with the home's class: the host
            # user's own classes stay as declared.
            inherit (home.user) classes email;
            hostUserClasses = den.hosts.x86_64-linux.igloo.users.tux.classes;
            userHost = home.user.host.name;
            os = osOf config "tux@igloo";
          };
        expected = {
          hostName = "igloo";
          hostClass = "nixos";
          classes = [ "homeManager" ];
          hostUserClasses = [ "user" ];
          email = "tux@igloo";
          userHost = "igloo";
          os = "igloo";
        };
      }
    );

    test-named-home-declared-host-without-user = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.pingu = { };
        den.homes.x86_64-linux."tux@igloo" = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";
        den.aspects.tux.includes = [ (osProbe den) ];

        expr =
          let
            home = homeOf den "x86_64-linux" "tux@igloo";
          in
          {
            hostName = home.host.name;
            hostClass = home.host.class;
            user = userOf home.user;
            os = osOf config "tux@igloo";
          };
        expected = {
          hostName = "igloo";
          hostClass = "nixos";
          user = syntheticUser;
          os = "igloo";
        };
      }
    );

    # Same home names on two systems, igloo declared on only one of them: the
    # binding follows the home's own system.
    test-same-home-name-two-systems = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.email = "tux@igloo";
        den.homes.x86_64-linux.tux = { };
        den.homes.aarch64-linux.tux = { };
        den.homes.x86_64-linux."tux@igloo" = { };
        den.homes.aarch64-linux."tux@igloo" = { };

        expr = {
          outputs = builtins.sort (a: b: a < b) (builtins.attrNames config.flake.homeConfigurations);
          plain =
            map
              (s: {
                inherit (homeOf den s "tux") host system;
                user = userOf (homeOf den s "tux").user;
              })
              [
                "x86_64-linux"
                "aarch64-linux"
              ];
          x86 = {
            hostClass = (homeOf den "x86_64-linux" "tux@igloo").host.class;
            email = (homeOf den "x86_64-linux" "tux@igloo").user.email;
          };
          arm = {
            inherit (homeOf den "aarch64-linux" "tux@igloo") host;
            user = userOf (homeOf den "aarch64-linux" "tux@igloo").user;
          };
        };
        expected = {
          outputs = [
            "tux@aarch64-linux"
            "tux@igloo@aarch64-linux"
            "tux@igloo@x86_64-linux"
            "tux@x86_64-linux"
          ];
          plain = [
            {
              host = null;
              user = syntheticUser;
              system = "x86_64-linux";
            }
            {
              host = null;
              user = syntheticUser;
              system = "aarch64-linux";
            }
          ];
          x86 = {
            hostClass = "nixos";
            email = "tux@igloo";
          };
          arm = {
            host = {
              name = "igloo";
              system = "aarch64-linux";
            };
            user = syntheticUser;
          };
        };
      }
    );

  };
}
