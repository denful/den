# Regression: including a nested aspect should still resolve its includes
# list.  Multiple modules each add their own child to polybar.includes.
# The shallow merge in aspectContentType only keeps the last module's
# includes.  Before #521, auto-walking masked this; after #521, children
# are silently dropped.
{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.deadbugs.nested-aspect-includes-children = {

    # Multiple modules each add to polybar.includes
    # Only the last module's includes survives the shallow merge
    test-multiple-includes-contributors = denTest (
      {
        den,
        igloo,
        gloom,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          (inputs.den.namespace "gloom" false)
          # Module 1: polybar base
          (
            { ... }:
            {
              gloom.apps.polybar = {
                nixos.environment.variables.POLYBAR = "yes";
              };
            }
          )
          # Module 2: coreuse child
          (
            { gloom, ... }:
            {
              gloom.apps.polybar.includes = [ gloom.apps.polybar.coreuse ];
              gloom.apps.polybar.coreuse = {
                nixos.environment.variables.COREUSE = "yes";
              };
            }
          )
          # Module 3: wifi child
          (
            { gloom, ... }:
            {
              gloom.apps.polybar.includes = [ gloom.apps.polybar.wifi ];
              gloom.apps.polybar.wifi = {
                nixos.environment.variables.WIFI = "yes";
              };
            }
          )
        ];

        den.aspects.igloo.includes = [ gloom.apps.polybar ];

        expr = {
          hasPolybar = igloo.environment.variables ? POLYBAR;
          hasCoreuse = igloo.environment.variables ? COREUSE;
          hasWifi = igloo.environment.variables ? WIFI;
        };
        expected = {
          hasPolybar = true;
          hasCoreuse = true;
          hasWifi = true;
        };
      }
    );

    # Explicit include path: polybar must be explicitly included
    test-explicit-include-resolves-all = denTest (
      {
        den,
        igloo,
        gloom,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        imports = [
          (inputs.den.namespace "gloom" false)
          (
            { ... }:
            {
              gloom.apps.polybar = {
                nixos.environment.variables.POLYBAR = "yes";
              };
            }
          )
          (
            { gloom, ... }:
            {
              gloom.apps.polybar.includes = [ gloom.apps.polybar.coreuse ];
              gloom.apps.polybar.coreuse = {
                nixos.environment.variables.COREUSE = "yes";
              };
            }
          )
          (
            { gloom, ... }:
            {
              gloom.apps.polybar.includes = [ gloom.apps.polybar.wifi ];
              gloom.apps.polybar.wifi = {
                nixos.environment.variables.WIFI = "yes";
              };
            }
          )
        ];

        # polybar must be explicitly included — no auto-walk
        den.aspects.igloo.includes = [ gloom.apps.polybar ];

        expr = {
          hasPolybar = igloo.environment.variables ? POLYBAR;
          hasCoreuse = igloo.environment.variables ? COREUSE;
          hasWifi = igloo.environment.variables ? WIFI;
        };
        expected = {
          hasPolybar = true;
          hasCoreuse = true;
          hasWifi = true;
        };
      }
    );

  };
}
