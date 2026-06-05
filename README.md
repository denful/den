<p align="right">
  <a href="https://denful.dev/sponsor"><img src="https://img.shields.io/badge/sponsor-vic-white?logo=githubsponsors&logoColor=white&labelColor=%23FF0000" alt="Sponsor Vic"/></a>
  <a href="https://deepwiki.com/denful/den"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
  <a href="https://github.com/denful/den/releases"><img src="https://img.shields.io/github/v/release/denful/den?style=plastic&logo=github&color=purple"/></a>
  <a href="https://denful.dev"><img src="https://img.shields.io/badge/Aspect_oriented-Nix-informational?logo=nixos&logoColor=white" alt="Aspect-oriented Nix"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/denful/den" alt="License"/></a>
  <a href="https://github.com/denful/den/actions"><img src="https://github.com/denful/den/actions/workflows/test.yml/badge.svg" alt="CI Status"/></a>
</p>

> den and [vic](https://bsky.app/profile/oeiuwq.bsky.social)'s [aspect libs](https://denful.dev) made for you with Love++ and AI--. If you like my work, consider [sponsoring](https://denful.dev/sponsor)

# den — Aspect-oriented, Context-driven Nix

**Write a feature once. Run it on every host, user, and platform you have — and share it with anyone, flake or not.**

Den turns Nix configuration into composable **features** instead of per-host piles of modules. A Den *aspect* is a plain function: give it context (your hosts and users) and it returns configuration for every Nix class it touches — `nixos`, `darwin`, `homeManager`, `hjem`, or a class you invent.

```nix
# An aspect is a function of context that returns
# configuration for many Nix classes at once.
den.aspects.gaming = { host, user }: {
  nixos       = { pkgs, ... }: { programs.steam.enable = true; };
  darwin      = { pkgs, ... }: { /* ... */ };
  homeManager = { pkgs, ... }: { /* ... */ };

  includes = [ den.aspects.performance ];   # aspects compose
  provides.emulation = { nixos = { /* ... */ }; };  # and nest
};
```

That one idea — **a feature as a function** — is what makes the rest possible.

## What Den makes possible

- **One feature, everywhere, in one place.** Stop scattering a single concern across separate `nixos`, `darwin`, and `homeManager` files. An aspect holds all of it together.
- **Reuse across hosts, users — and across projects.** Share aspects between machines, between people, and between *flake and non-flake* setups, without forcing everyone to download each other's inputs.
- **No `mkIf` / `enable` clutter.** The shape of the context *is* the condition — a function that asks for `{ host, user }` simply doesn't run where there's no user. Conditionals disappear.
- **Hosts shape their users, users shape their hosts.** Cross-entity configuration flows both ways, without coupling them together.
- **Add a capability in one line; remove it by deleting that line.** Hosts just pick the aspects they want.
- **Bring your own classes and whole pipelines.** Custom Nix classes, machine fleets, MicroVM guests, terranix, standalone neovim — if you can walk it as data, Den can configure it.

## Principles

Four concepts, one job each:

- **Entity** — *what exists*: a host, user, or home.
- **Aspect** — *what it does*: a feature, spanning Nix classes.
- **Policy** — *how entities relate*: topology and routing between them.
- **Quirk** — *structured data aspects share*, without coupling.

**Feature-first, not host-first.** Traditional setups start from hosts and push modules down; Den [flips that](https://den.denful.dev/explanation/core-principles/) — features are primary, hosts just select them.

**Den embraces your Nix.** With or without flakes, flake-parts, or home-manager. Zero dependencies. Every part is optional and replaceable — Den works with the setup you already have, and gets out of the way.

## Try it now

```console
# a MicroVM
nix run github:denful/den?dir=templates/microvm#runnable-microvm

# a standalone neovim
nix run github:denful/den?dir=templates/nvf-standalone#my-neovim

# a qemu VM
nix run github:denful/den
```

<table>
<tr>
<td>
<div style="max-width: 320px;">

<img width="300" height="300" alt="den" src="https://github.com/user-attachments/assets/af9c9bca-ab8b-4682-8678-31a70d510bbb" />

## [Documentation](https://den.denful.dev)

**Start here**
- [From Zero to Den](https://den.denful.dev/guides/from-zero-to-den/)
- [From Flake to Den](https://den.denful.dev/guides/from-flake-to-den/)
- [Core Principles](https://den.denful.dev/explanation/core-principles/)

**Go further**
- [Custom Nix Classes](https://den.denful.dev/guides/custom-classes/)
- [Homes Integration](https://den.denful.dev/guides/home-manager/)
- [Batteries](https://den.denful.dev/guides/batteries/)
- [Mutual Providers](https://den.denful.dev/guides/mutual/)
- [Sharing Namespaces](https://den.denful.dev/guides/namespaces/)
- [`<angle/brackets>`](https://den.denful.dev/guides/angle-brackets/)
- [Tests as Code Examples](https://den.denful.dev/tutorials/ci/)

**Project**
- [Motivation](https://den.denful.dev/motivation/)
- [Versioning](https://den.denful.dev/releases/)
- [Community](https://den.denful.dev/community/)
- [Contributing](https://den.denful.dev/contributing/)

</div>
</td>
<td>

### Templates

Pick a starting point and grow from there:

- [default](https://den.denful.dev/tutorials/default/) — flake-file + flake-parts + home-manager
- [minimal](https://den.denful.dev/tutorials/minimal) — flakes, nothing else
- [noflake](https://den.denful.dev/tutorials/noflake) — npins + `lib.evalModules` + nix-maid
- [nvf-standalone](https://den.denful.dev/tutorials/nvf-standalone) — neovim apps, no NixOS/Darwin needed
- [microvm](https://den.denful.dev/tutorials/microvm) — runnable VM + declarative guests
- [flake-parts-modules](https://den.denful.dev/tutorials/flake-parts-modules) — third-party perSystem classes
- [example](https://den.denful.dev/tutorials/example) — cross-platform

### In the wild

- [`@vic`](https://github.com/vic/vix) — fleet-sharing config from Den's author
- [`@quasigod`](https://tangled.org/quasigod.xyz/nixconfig) — custom namespaces + angle brackets
- [`@Gwenodai`](https://github.com/Gwenodai/nixos) — path-naming conventions, custom guarded/forwarding classes
- [`@adda`](https://codeberg.org/Adda/nixos-config) — multiple hosts, flake-parts + home-manager

> Den is also running on internal infra at **The European Commission**.

Growing adoption: [usage search](https://github.com/search?q=den.aspects+language%3ANix&type=code)

</td>
</tr>
</table>

## What people say

> Den takes the Dendritic pattern to a whole new level, and I cannot imagine going back.\
> — `@adda`, early Den adopter (after Dendritic flake-parts and Unify)

> I'm super impressed with den so far, I'm excited to try out some new patterns that Unify couldn't easily do.\
> — `@quasigod`, author of [Unify](https://codeberg.org/quasigod/unify)

> Massive work you did here!\
> — `@drupol`, author of [“Flipping the Configuration Matrix”](https://not-a-number.io/2025/refactoring-my-infrastructure-as-code-configurations/#flipping-the-configuration-matrix)

> Thanks for the awesome library and the support for non-flakes… it's positively brilliant! I really hope this gets wider adoption.\
> — `@vczf`, at [`#den-lib:matrix.org`](https://matrix.to/#/#den-lib:matrix.org)

> Den is a playground for some very advanced concepts… some of its ideas will play a role in future Nix areas. There are some raw diamonds in Den.\
> — `@Doc-Steve`, author of the [Dendritic Design Guide](https://github.com/Doc-Steve/dendritic-design-with-flake-parts)

---

<p align="center">
  <a href="https://den.denful.dev"><b>Read the docs →</b></a> ·
  <a href="https://denful.dev/sponsor">Sponsor</a> ·
  <a href="LICENSE">License</a>
</p>
