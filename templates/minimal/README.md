# Getting Started Guide

Steps you can follow after cloning this template:

- Be sure to read the [den documentation](https://den.oeiuwq.com)

- Update den input.

```console
nix flake update den
```

- Edit [modules/den.nix](modules/den.nix)

- Build

```console
# default action is build
nix run .#igloo

# pass any other nh action
nix run .#igloo -- switch
```
