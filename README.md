<p align="right">
  <a href="https://dendritic.oeiuwq.com/sponsor"><img src="https://img.shields.io/badge/sponsor-vic-white?logo=githubsponsors&logoColor=white&labelColor=%23FF0000" alt="Sponsor Vic"/></a>
  <a href="https://deepwiki.com/denful/den"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
  <a href="https://github.com/denful/den/releases"><img src="https://img.shields.io/github/v/release/denful/den?style=plastic&logo=github&color=purple"/></a>
  <a href="https://dendritic.oeiuwq.com"><img src="https://img.shields.io/badge/Dendritic-Nix-informational?logo=nixos&logoColor=white" alt="Dendritic Nix"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/denful/den" alt="License"/></a>
  <a href="https://github.com/denful/den/actions"><img src="https://github.com/denful/den/actions/workflows/test.yml/badge.svg" alt="CI Status"/></a>
</p>

> den and [vic](https://bsky.app/profile/oeiuwq.bsky.social)'s [dendritic libs](https://dendritic.oeiuwq.com) made for you with Love++ and AI--. If you like my work, consider [sponsoring](https://dendritic.oeiuwq.com/sponsor)

# den - Aspect-oriented, Context-driven Dendritic Nix configurations.

### Den allows creating parametric configurations by taking the Dendritic pattern to the function-level.

These configurations become specific when applied to your particular infra entities (hosts/users),
while allowing re-usable aspects to be shared between hosts, users, or across other flakes and non-flake projects.

<table>
<tr>
<td>

```nix
# An aspect is a function taking context and
# returning modules of different Nix classes
den.aspects.gaming = { host, user }: {
  nixos = { pkgs, ... }: ...;
  darwin = ...;
  hjem = ...;
  homeManager = ...;

  # aspects can depend on other aspects
  includes = [ den.aspects.performance ];

  # aspects can be organized in sub-aspects
  provides.emulation = {
    nixos = { pkgs, ... }: ... ;
  };
}
```

</td>
<td>

```nix
# These three lines is how Den instantiates a configuration.
# Other Nix configuration domains outside NixOS/nix-Darwin
# can use the same pattern. demo: templates/nvf-standalone

# Den resolves entities declared in den.hosts automatically.
# Policies drive topology (host->[users]->[homes]).
# The pipeline collects all aspects and produces per-class modules.

# For manual resolution outside the pipeline:
aspect = den.lib.aspects.resolve "nixos"
  (den.aspects.my-aspect { host = den.hosts.x86_64-linux.my-laptop; });
nixosConfigurations.my-laptop = lib.nixosSystem {
  modules = [ aspect ];
};
```

</td>
</tr>
</table>

Den has Zero Dependencies. `den.lib` is domain agnostic, it can be used to configure anything Nix-configurable.

On top of `den.lib`, Den also provides a [framework](https://den.oeiuwq.com/explanation/context-pipeline/) for the NixOS/nix-Darwin/Home-Manager Nix domains.

Den embraces your Nix choices and does not impose itself. All parts of Den are optional and replaceable. Works with your current setup, with/without flakes, flake-parts or any other Nix module system.

> [Den is a declarative data transformation pipeline](https://github.com/denful/den/discussions/355). Infra entities are traversed via `den.policies` and configurations for them are generated when `den.aspects` are applied at each entity resolution.

<table>
<tr>
<td>
<div style="max-width: 320px;">

<img width="300" height="300" alt="den" src="https://github.com/user-attachments/assets/af9c9bca-ab8b-4682-8678-31a70d510bbb" />

## [Documentation](https://den.oeiuwq.com)

- [From Zero To Den](https://den.oeiuwq.com/guides/from-zero-to-den/)

- [From Flake To Den](https://den.oeiuwq.com/guides/from-flake-to-den/)

- [Core Principles](https://den.oeiuwq.com/explanation/core-principles/)

- [Custom Nix Classes](https://den.oeiuwq.com/guides/custom-classes/)

- [Homes Integration](https://den.oeiuwq.com/guides/home-manager/)

- [Batteries](https://den.oeiuwq.com/guides/batteries/)

- [Mutual Providers](https://den.oeiuwq.com/guides/mutual/)

- [Sharing Namespaces](https://den.oeiuwq.com/guides/namespaces/)

- [`<angle/brackets>`](https://den.oeiuwq.com/guides/angle-brackets/)

- [Tests as Code Examples](https://den.oeiuwq.com/tutorials/ci/)

## Project

- [Versioning](https://den.oeiuwq.com/releases/)

- [Motivation](https://den.oeiuwq.com/motivation/)

- [Community](https://den.oeiuwq.com/community/)

- [Contributing](https://den.oeiuwq.com/contributing/)

</div>
</td>
<td>

### Templates:

[default](https://den.oeiuwq.com/tutorials/default/): +flake-file +flake-parts +home-manager

[minimal](https://den.oeiuwq.com/tutorials/minimal): +flakes -flake-parts -home-manager

[noflake](https://den.oeiuwq.com/tutorials/noflake): -flakes +npins +lib.evalModules +nix-maid

[nvf-standalone](https://den.oeiuwq.com/tutorials/nvf-standalone): Standalone neovim apps, showcasing Den without NixOS/Darwin.

[microvm](https://den.oeiuwq.com/tutorials/microvm): MicroVM runnable-pkg and guests. custom ctx-pipeline.

[flake-parts-modules](https://den.oeiuwq.com/tutorials/flake-parts-modules): Den forward classes for third-party perSystem submodules: nix-unit on aspects, mightyiam/files generation, devshells, etc.

[example](https://den.oeiuwq.com/tutorials/example): cross-platform

[ci](https://den.oeiuwq.com/tutorials/ci): Each feature tested as code examples

[bogus](https://den.oeiuwq.com/tutorials/bogus): Isolated test for bug reproduction

### Examples:

> Want yours featured? send me a DM via matrix or zulip (links at GH Discussions)

[`@vic`](https://github.com/vic/vix): Fleet sharing user, author spends more time in Den itself. (-flakes +npins +auto-update +ci)

[`@quasigod`](https://tangled.org/quasigod.xyz/nixconfig): Beautiful organization, uses custom Den namespaces and Den angle brackets (+flake-parts)

[`@Gwenodai`](https://github.com/Gwenodai/nixos): Clever organization with path-naming conventions, custom guarded and forwarding classes

[`@adda`](https://codeberg.org/Adda/nixos-config): Multiple hosts (+flake-parts +flake-file +home-manager +files)

> Den is also being used on internal infra at The European Commission.

Growing community adoption: [Usage Search](https://github.com/search?q=den.aspects+language%3ANix&type=code)

**❄️ Try it:**

```console
# Run virtio MicroVM from templates/microvm
nix run github:denful/den?dir=templates/microvm#runnable-microvm
```

```console
# Run NVF-Standalone neovim from templates/nvf-standalone
nix run github:denful/den?dir=templates/nvf-standalone#my-neovim
```

```console
# Run qemu VM from templates/example
nix run github:denful/den
```

</td>

</tr>
</table>

### Testimonials

> Den takes the Dendritic pattern to a whole new level, and I cannot imagine going back.\
> — `@adda` - Very early Den adopter after using Dendritic flake-parts and Unify.

> I’m super impressed with den so far, I’m excited to try out some new patterns that Unify couldn’t easily do.\
> — `@quasigod` - Author of [Unify](https://codeberg.org/quasigod/unify) dendritic-framework, on adopting Den.

> Massive work you did here!\
> — `@drupol` - Author of [“Flipping the Configuration Matrix”](https://not-a-number.io/2025/refactoring-my-infrastructure-as-code-configurations/#flipping-the-configuration-matrix) Dendritic blog post.

> Thanks for the awesome library and the support for non-flakes… it’s positively brilliant!. I really hope this gets wider adoption.\
> — `@vczf` - At [`#den-lib:matrix.org`](https://matrix.to/#/#den-lib:matrix.org) channel.

> Den is a playground for some very advanced concepts. I’m convinced that some of its ideas will play a role in future Nix areas. In my opinion there are some raw diamonds in Den.\
> — `@Doc-Steve` - Author of [Dendritic Design Guide](https://github.com/Doc-Steve/dendritic-design-with-flake-parts)

## Code examples (OS configuration framework)

### Defining hosts, users and homes.

Simplest example, one-liner definitions.

```nix
den.hosts.x86_64-linux.lap.users.vic = {};
den.hosts.aarch64-darwin.mac.users.vic = {};
den.homes.aarch64-darwin."vic@mac" = {};
```

The `den.aspects.vic` aspect is shared between
these two hosts and standalone home-manager.

The `vic@mac` homeConfiguration has `osConfig = mac.config`.

Activate with:

```console
$ nixos-rebuild  switch --flake .#lap
$ darwin-rebuild switch --flake .#mac
$ home-manager   switch --flake .#vic
```

### Extensible Schemas for hosts, users and homes.

These allow meta-configuration on entities, akin to
what Dendritic flake-parts users do with top-level
options, but here scoped to each entity type.

People use this for declaring host or user capabilities
that will later be used by aspects to implement configurations.

```nix
# extensible base modules for common, typed schemas
den.schema.user = { user, lib, ... }: {
  config.classes =
    if user.userName == "vic" then [ "hjem" "maid" ]
    else lib.mkDefault [ "homeManager" ];

  options.mainGroup = lib.mkOption { default = user.userName; };
};
```

### Dendritic Multi-Platform Hosts

A single aspect like `den.aspects.workstation` can be
shared between (included-at) NixOS/nix-Darwin/WSL hosts.

Each aspect uses several Nix classes to define behaviour.

```nix
# modules/workstation.nix
{ den, inputs, ... }: {
  den.aspects.workstation = {
    # re-usable configuration aspects. Den batteries and yours.
    includes = [ den.batteries.hostname den.aspects.work-vpn ];

    # regular nixos/darwin modules or any other Nix class
    nixos  = { pkgs, ... }: { imports = [ inputs.disko.nixosModules.disko ]; };
    darwin = { pkgs, ... }: { imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ]; };

    # Custom Nix classes. `os` applies to both nixos and darwin.
    # Contributed by @Risa-G.
    # See https://den.oeiuwq.com/guides/custom-classes/#user-contributed-examples
    os = { pkgs, ... }: {
      environment.systemPackages = [ pkgs.direnv ];
    };

    # host can contribute default home environments
    # to all its users.
    provides.to-users = {
      homeManager = { pkgs, ... }: {
        programs.vim.enable = true;
        home.packages = [ pkgs.neovide ];
      };
    };
  };
}
```

### Multiple User Home Environments

Each user can define configurations for different
home environments, aiding with migration from
homeManager to hjem or others.

```nix
# modules/vic.nix
{ den, ... }: {

  den.aspects.vic = {
    # supports multiple home environments
    homeManager = { pkgs, ... }: { };
    hjem.files.".envrc".text = "use flake ~/hk/home";
    maid.kconfig.settings.kwinrc.Desktops.Number = 3;

    # user can contribute OS-configurations
    # to all hosts it lives on
    darwin.services.karabiner-elements.enable = true;

    # user can specify config for specific host
    provides.rog-tower = {
      nixos = ...; # enable CUDA and gaming profile
    };

    # user class forwards into
    # {nixos/darwin}.users.users.<userName>
    user = { pkgs, ... }: {
      packages = [ pkgs.helix ];
      description = "oeiuwq";
    };

    includes = [
      den.batteries.primary-user        # re-usable batteries
      (den.batteries.user-shell "fish") # parametric aspects
      den.aspects.tiling-wm            # your own aspects
      den.aspects.gaming.provides.emulators
    ];
  };
}
```

### Custom Dendritic Nix Classes

[Custom classes](https://den.oeiuwq.com/guides/custom-classes) is how Den implements `user`, `homeManager`, `hjem`, `wsl`, `microvm` support. You can use the very same mechanism to create your own Nix classes.

The `den.batteries.forward` battery is the core of it.

```nix
# Example: A class for role-based configuration between users and hosts

roleClass =
  { host, user }:
  { class, aspect-chain }:
  den.batteries.forward {
    each = lib.intersectLists (host.roles or []) (user.roles or []);
    fromClass = lib.id;
    intoClass = _: host.class;
    intoPath = _: [ ];
    fromAspect = _: lib.head aspect-chain;
  };

den.schema.user.includes = [ roleClass ];

den.hosts.x86_64-linux.igloo = {
  roles = [ "devops" "gaming" ];
  users = {
    alice.roles = [ "gaming" ];
    bob.roles = [ "devops" ];
  };
};

den.aspects.alice = {
  # enabled when both support gaming role
  gaming = { pkgs, ... }: { programs.steam.enable = true; };
};

den.aspects.bob = {
  # enabled when both support devops role
  devops = { pkgs, ... }: { virtualisation.podman.enable = true; };

  # not enabled at igloo host (bob missing gaming role on that host)
  gaming = {};
};
```

### Guarded Forwarding Classes

Any module/file can contribute to any aspects directly
into their feature-concern Nix classes, without
having to deal with feature-detection or having
`mkIf`/`mkMerge` clutterring on all the codebase.

The logic (guard) for conditional inclusion of a
forwarded-class configuration is defined at a
single place.

#### Example: Platform Aware `homeManager` classes

This uses `pkgs.stdenv.isXYZ` to define `hmXYZ` classes,
because some hm configurations might be only available
on specific platforms.

```nix
# aspect `tux` is used on both platforms
den.hosts.x86_64-linux.igloo.users.tux = { };
den.hosts.aarch64-darwin.apple.users.tux = { };

den.aspects.hmPlatforms =
  { class, aspect-chain }:
  den.batteries.forward {
    each = [ "Linux" "Darwin" ];
    fromClass = platform: "hm${platform}";
    intoClass = _: "homeManager";
    intoPath = _: [ ];
    fromAspect = _: lib.head aspect-chain;
    guard = { pkgs, ... }: platform: lib.mkIf pkgs.stdenv."is${platform}";
    adaptArgs = { config, ... }: { osConfig = config; };
  };

den.aspects.tux = {
  includes = [ den.aspects.hmPlatforms ];

  hmDarwin = { pkgs, ... }: { home.packages = [ pkgs.iterm2 ]; };

  hmLinux = { pkgs, ... }: { home.packages = [ pkgs.wl-clipboard-rs ]; };
};
```

#### Example: Class for Impermanence Capability

Modules define configurations at aspects using the
`persys` class directly, without any conditional.

The guard guarantees they are applied **only**
when impermanence module is enabled at host.

> Inspired by @Doc-Steve

```nix
persys = { host }: den.batteries.forward {
  each = lib.singleton true;
  fromClass = _: "persys";
  intoClass = _: host.class;
  intoPath = _: [ "environment" "persistence" "/nix/persist/system" ];
  fromAspect = _: den.aspects.${host.aspect};
  guard = { options, config, ... }: options ? environment.persistence;
};

# enable on all hosts
den.schema.host.includes = [ persys ];

# aspects just attach config to custom class
den.aspects.my-laptop.persys.hideMounts = true;
```

### User-defined Extensions to Den context pipeline.

See example [`template/microvm`](https://den.oeiuwq.com/tutorials/microvm) for an example
of custom `den.schema` and `den.policies` extensions for supporting
Declarative [MicroVM](https://microvm-nix.github.io/microvm.nix/declarative.html) guests with automatic host-shared `/nix/store`.

```nix
den.hosts.x86_64-linux.guest = {};
den.hosts.x86_64-linux.host = {
  microvm.guests = [ den.hosts.x86_64-linux.guest ];
};

den.aspects.guest = {
  # propagated into host.nixos.microvm.vms.<name>;
  microvm.autostart = true;

  # guest supports all Den features.
  includes = [ den.batteries.hostname ];
  # As MicroVM guest propagated into host.nixos.microvm.vms.<name>.config;
  nixos = { pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; };
};
```
