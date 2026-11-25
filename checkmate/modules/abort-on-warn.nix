# Reading host users' names and classes and a standalone home's user emits no
# warnings: `checks.abort-on-warn` runs the `abortOnWarn` suite under
# `--option abort-on-warn true`, so a nixpkgs or den deprecation warning
# reached there fails the check. It evaluates only, with no system build.
{
  inputs,
  lib,
  self,
  ...
}:
let
  # A den config of its own, as den's test harness builds one (nix/denTest.nix).
  evalDen =
    module:
    (lib.evalModules {
      specialArgs.inputs = inputs // {
        den = inputs.target;
      };
      modules = [
        inputs.target.flakeModule
        inputs.target.flakeOutputs.flake
        module
      ];
    }).config;

  fleet = evalDen {
    den.hosts.x86_64-linux.igloo.users = {
      plain = { };
      disabled = lib.mkIf false { };
      merged = lib.mkMerge [
        { }
        { userName = "merged-user"; }
      ];
    };
    # checkmate has no home-manager input, and nothing here builds the home.
    den.homes.x86_64-linux.tux.instantiate = _: throw "den: abort-on-warn evaluates, never builds";
  };
in
{
  flake.abortOnWarn = {
    test-host-users = {
      expr = lib.mapAttrs (_: u: {
        inherit (u) userName classes;
      }) fleet.den.hosts.x86_64-linux.igloo.users;
      expected = {
        plain = {
          userName = "plain";
          classes = [ "user" ];
        };
        merged = {
          userName = "merged-user";
          classes = [ "user" ];
        };
      };
    };
    test-standalone-home-user = {
      expr = {
        inherit (fleet.den.homes.x86_64-linux.tux.user) userName classes;
      };
      expected = {
        userName = "tux";
        classes = [ "homeManager" ];
      };
    };
  };

  perSystem =
    { config, pkgs, ... }:
    let
      overrideArg =
        name: value: "--override-input ${lib.escapeShellArg name} ${lib.escapeShellArg "${value}"}";
      # Mirrors nix-unit's `checks.nix-unit` (lib/modules/flake/system.nix), always
      # networked where upstream gates it on `allowNetwork`: den's gen fallback fetches.
      key = "abort-on-warn check derived from ${baseNameOf (builtins.unsafeDiscardStringContext drv.drvPath)} is ok\n";
      drv =
        pkgs.runCommand "den-abort-on-warn"
          {
            nativeBuildInputs = [ config.nix-unit.package ];
            buildInputs = [ pkgs.cacert ];
          }
          ''
            export HOME="$(realpath .)"
            unset NIX_STORE
            export NIX_STORE_DIR=${builtins.storeDir}
            export NIX_REMOTE="$HOME/storedata"
            nix-unit \
              --show-trace \
              --option abort-on-warn true \
              --extra-experimental-features "flakes pipe-operators" \
              --accept-flake-config \
              ${lib.concatStringsSep " " (lib.mapAttrsToList overrideArg config.nix-unit.inputs)} \
              --flake ${self}#abortOnWarn
            echo -n "$key" > $out
          '';
    in
    {
      checks.abort-on-warn = drv.overrideAttrs {
        inherit key;
        outputHashAlgo = "sha256";
        outputHashMode = "flat";
        outputHash = builtins.hashString "sha256" key;
      };
    };
}
