# Hero Canvas Animation — Design Spec

Replace the static hero image on the docs landing page with an animated canvas showing a branching topology that grows, sends photon particles, rewinds, and regenerates.

## Decisions

| Question | Answer |
|----------|--------|
| Animation loop | Infinite — grow, photon walk, rewind, regenerate |
| Canvas sizing | Fixed 400×400, fits within Starlight's hero image slot |
| "den" text overlay | Removed — topology stands alone, Starlight renders the title |
| Colors | Catppuccin palette, read from CSS vars, supports light/dark toggle |
| Off-screen behavior | Pause via IntersectionObserver |
| Integration approach | Hero component override with dedicated LogoAnimation component |

## Component Architecture

### Files

| File | Action | Purpose |
|------|--------|---------|
| `src/components/LogoAnimation.astro` | Create | Self-contained canvas animation component |
| `src/components/Hero.astro` | Create | Override of Starlight's Hero, renders LogoAnimation in image slot |
| `astro.config.mjs` | Modify | Add `Hero: './src/components/Hero.astro'` to component overrides |
| `src/content/docs/index.mdx` | Modify | Remove `hero.image.html` from frontmatter |

### Hero.astro Override

A near-copy of Starlight's `Hero.astro` (`node_modules/@astrojs/starlight/components/Hero.astro`). The only change: the image rendering block (`<Image>`, `hero-html` div) is replaced with conditional logic:

- **Index page** (detected via `Astro.locals.starlightRoute.entry.id === 'index.mdx'`): Render `<LogoAnimation />`
- **Other pages:** Fall back to original image rendering (dark/light `<Image>`, raw HTML)

All existing hero markup (title, tagline, actions) and styles (7fr/4fr grid, responsive breakpoints) are preserved verbatim.

### LogoAnimation.astro

**Markup:**
```html
<div class="logo-animation">
  <canvas width="400" height="400"></canvas>
</div>
```

No `id` attribute on the canvas — the script queries within its own component scope.

**Scoped styles:**
- `.logo-animation` wrapper styled with `width: min(100%, 25rem); margin-inline: auto;` to match the hero image slot sizing (Starlight's CSS targets `.hero > img` and `.hero > .hero-html` specifically, so our wrapper needs its own rule)
- On desktop (`min-width: 50rem`): `order: 2; width: min(100%, 25rem);` to match Starlight's image positioning

**Client-side script — responsibilities:**

1. **Init** — get canvas from component scope, set up 2D context, read Catppuccin colors from computed CSS custom properties
2. **Theme observation** — `MutationObserver` on `document.documentElement` for `data-theme` attribute changes. Re-reads colors on toggle.
3. **Visibility** — `IntersectionObserver` on the canvas. Pauses `requestAnimationFrame` when off-screen, resumes when visible.
4. **Cleanup** — listens for `astro:before-swap` (Astro SPA navigation event) to cancel animation frame, clear all timeouts, disconnect both observers.
5. **Animation loop** — the topology algorithm from `foo-wip.html`, unchanged in behavior.

**Color mapping (resolved from CSS custom properties at runtime):**

| Role | CSS Variable | Dark (Macchiato) | Light (Latte) |
|------|-------------|-----------------|---------------|
| Gradient start | `--sl-color-blue` | `#8aadf4` | `#1e66f5` |
| Gradient end | `--sl-color-purple` | `#c6a0f6` | `#8839ef` |
| Nodes | `--sl-color-white` | `#cad3f5` | `#4c4f69` |
| Node glow | Alternates blue/purple | Same | Same |

### Animation Algorithm

Carried over from `~/foo-wip.html` (source file at `/home/sini/foo-wip.html`, outside the repo — copy algorithm during implementation):

- **Topology:** 4 tiers, bezier curves connecting nodes between tiers
- **Branching:** Random child count per node (0–3), biased toward splitting. One "prime" path guaranteed to reach the bottom tier. Hard boundary at ±165px from center prevents horizontal sprawl.
- **Growth:** Lines draw progressively with eased animation (`easeOutCubic`). When a line completes, its endpoint branches.
- **Photon walk:** After topology completes, photon particles spawn at leaf nodes and walk up parent paths toward the root. Spawn window is 6 seconds.
- **Rewind:** After photons finish, lines retract leaf-first (children must fully retract before parents begin).
- **Regenerate:** After rewind completes, 800ms pause, then a new random topology grows.

Canvas dimensions change from 500×450 to 400×400 (square). Tier positions adjusted proportionally.
