# Hero Canvas Animation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static hero image on the docs landing page with an animated canvas showing a branching topology.

**Architecture:** Override Starlight's Hero.astro component to conditionally render a LogoAnimation.astro component on the index page. LogoAnimation is self-contained: canvas markup, scoped styles, and a client-side script with the topology animation algorithm adapted from ~/foo-wip.html.

**Tech Stack:** Astro components, HTML Canvas 2D API, Catppuccin CSS custom properties, IntersectionObserver, MutationObserver

**Spec:** `docs/superpowers/specs/2026-05-07-hero-canvas-animation-design.md`

---

### Task 1: Create LogoAnimation.astro component

**Goal:** Create the self-contained canvas animation component with topology algorithm, theme-aware colors, visibility pausing, and SPA cleanup.

**Files:**
- Create: `docs/src/components/LogoAnimation.astro`
- Reference: `/home/sini/foo-wip.html` (source algorithm, outside repo)

**Acceptance Criteria:**
- [ ] Canvas renders at 400×400
- [ ] Animation cycles: grow topology → photon walk → rewind → regenerate (infinite loop)
- [ ] Colors read from `--sl-color-blue`, `--sl-color-purple`, `--sl-color-white` CSS custom properties
- [ ] Theme toggle (light/dark) updates colors via MutationObserver on `data-theme`
- [ ] IntersectionObserver pauses animation when canvas is off-screen
- [ ] `astro:before-swap` listener cleans up (cancelAnimationFrame, clearTimeouts, disconnect observers)
- [ ] No "den" text overlay
- [ ] Component wrapper has correct sizing styles for hero slot

**Verify:** Visual inspection — component can be tested by temporarily importing it directly in index.mdx body.

**Steps:**

- [ ] **Step 1: Create LogoAnimation.astro with markup and scoped styles**

```astro
---
// No server-side logic needed
---

<div class="logo-animation">
  <canvas width="400" height="400"></canvas>
</div>

<style>
  /* Mobile: matches Starlight's .hero > img sizing */
  .logo-animation {
    object-fit: contain;
    width: min(70%, 20rem);
    height: auto;
    margin-inline: auto;
  }

  .logo-animation canvas {
    display: block;
    width: 100%;
    height: auto;
  }

  @media (min-width: 50rem) {
    .logo-animation {
      order: 2;
      width: min(100%, 25rem);
    }
  }
</style>
```

- [ ] **Step 2: Add client-side script with color resolution and observers**

Add a `<script>` block after the `<style>`. The script:

1. Queries the canvas via `document.querySelector('.logo-animation canvas')` (Astro `<script>` tags are globally bundled, not scoped — only one LogoAnimation instance exists on the page so a class selector is sufficient)
2. Resolves Catppuccin colors from CSS custom properties:
   ```js
   function readColors() {
     const style = getComputedStyle(document.documentElement);
     return {
       blue: style.getPropertyValue('--sl-color-blue').trim() || '#8aadf4',
       purple: style.getPropertyValue('--sl-color-purple').trim() || '#c6a0f6',
       white: style.getPropertyValue('--sl-color-white').trim() || '#ffffff',
     };
   }
   ```
3. Sets up MutationObserver on `document.documentElement` for `data-theme` attribute changes → calls `readColors()` to update
4. Sets up IntersectionObserver on the canvas → pauses/resumes `requestAnimationFrame`
5. Listens for `astro:before-swap` → cancels animation frame, clears all timeouts, disconnects both observers

- [ ] **Step 3: Port the animation algorithm from foo-wip.html**

Adapt the topology algorithm with these changes from the original:
- Canvas size: 500×450 → 400×400
- Tier positions: `[40, 120, 200, 280]` → `[35, 135, 235, 335]` (proportionally scaled to 400px height, with padding)
- `gridOffset`: 55 → 50 (slightly tighter for 400px width)
- `originX`: `canvas.width / 2` (stays 200)
- `maxLimit`: 165 → 150 (proportional boundary)
- Remove brand text div and all references to it
- Replace hardcoded `ACCENT_BLUE` / `ACCENT_PURPLE` / `"#ffffff"` with values from `readColors()`
- `getGlobalGradient()` uses resolved blue/purple colors
- `drawNode()` uses resolved white for fill, alternating blue/purple for glow
- Photon rendering uses resolved white for fill, alternating glow

The five animation states, branching logic, bezier curve generation, photon walk, and rewind mechanics are unchanged.

- [ ] **Step 4: Verify component renders standalone**

Temporarily add to `index.mdx` body to test:
```mdx
import LogoAnimation from '../../components/LogoAnimation.astro';

<LogoAnimation />
```

Run the docs dev server and verify:
```bash
cd docs && npm run dev
```
Check: animation runs, colors match theme, toggling theme updates colors, scrolling away pauses animation.

Remove the temporary import after verification.

---

### Task 2: Create Hero.astro override

**Goal:** Override Starlight's Hero component to render LogoAnimation on the index page, preserving all other hero behavior.

**Files:**
- Create: `docs/src/components/Hero.astro`
- Reference: `docs/node_modules/@astrojs/starlight/components/Hero.astro` (original to copy from)

**Acceptance Criteria:**
- [ ] Index page renders `<LogoAnimation />` in the image slot
- [ ] Non-index pages with hero images still render correctly (Image tags, raw HTML)
- [ ] All hero markup (title, tagline, actions) preserved
- [ ] All hero styles (grid layout, responsive breakpoints) preserved

**Verify:** Visual inspection — index page shows animation, other pages unchanged.

**Steps:**

- [ ] **Step 1: Copy Starlight's Hero.astro and add LogoAnimation import**

Copy the full content of `node_modules/@astrojs/starlight/components/Hero.astro` to `src/components/Hero.astro`. Add the LogoAnimation import:

```astro
---
import { Image } from 'astro:assets';
import { PAGE_TITLE_ID } from '@astrojs/starlight/constants';
import LinkButton from '@astrojs/starlight/components/LinkButton.astro';
// Note: Starlight's source uses relative '../user-components/LinkButton.astro'
// but the public package path works from src/components/ and is more stable.
import LogoAnimation from './LogoAnimation.astro';

const { data } = Astro.locals.starlightRoute.entry;
const { title = data.title, tagline, image, actions = [] } = data.hero || {};

const isIndex = Astro.locals.starlightRoute.entry.id === 'index.mdx';

const imageAttrs = {
  loading: 'eager' as const,
  decoding: 'async' as const,
  width: 400,
  height: 400,
  alt: image?.alt || '',
};

let darkImage: ImageMetadata | undefined;
let lightImage: ImageMetadata | undefined;
let rawHtml: string | undefined;
if (image) {
  if ('file' in image) {
    darkImage = image.file;
  } else if ('dark' in image) {
    darkImage = image.dark;
    lightImage = image.light;
  } else {
    rawHtml = image.html;
  }
}
---
```

- [ ] **Step 2: Replace the image rendering block with conditional logic**

In the template, replace the three image rendering lines:
```astro
{isIndex && <LogoAnimation />}
{!isIndex && darkImage && (
  <Image
    src={darkImage}
    {...imageAttrs}
    class:list={{ 'light:sl-hidden': Boolean(lightImage) }}
  />
)}
{!isIndex && lightImage && <Image src={lightImage} {...imageAttrs} class="dark:sl-hidden" />}
{!isIndex && rawHtml && <div class="hero-html sl-flex" set:html={rawHtml} />}
```

- [ ] **Step 3: Keep all styles verbatim from the original**

Copy the entire `<style>` block from Starlight's Hero.astro unchanged. The `.logo-animation` sizing is handled by LogoAnimation's own scoped styles.

---

### Task 3: Wire up config and clean up index.mdx

**Goal:** Register the Hero override in astro.config.mjs and remove the static image from index.mdx frontmatter.

**Files:**
- Modify: `docs/astro.config.mjs:171-177` (add Hero to component overrides)
- Modify: `docs/src/content/docs/index.mdx:8-9` (remove hero.image.html)

**Acceptance Criteria:**
- [ ] `astro.config.mjs` has `Hero: './src/components/Hero.astro'` in components
- [ ] `index.mdx` frontmatter has no `hero.image` section
- [ ] Docs site builds without errors
- [ ] Landing page shows animated canvas in hero image slot
- [ ] Other doc pages render normally

**Verify:**
```bash
cd docs && npm run build
```
Expected: Build succeeds with no errors.

**Steps:**

- [ ] **Step 1: Add Hero override to astro.config.mjs**

In the `components` object (line ~171), add the Hero entry:

```js
components: {
  Head: './src/components/Head.astro',
  Sidebar: './src/components/Sidebar.astro',
  Footer: './src/components/Footer.astro',
  SocialIcons: './src/components/SocialIcons.astro',
  PageSidebar: './src/components/PageSidebar.astro',
  Hero: './src/components/Hero.astro',
},
```

- [ ] **Step 2: Remove hero.image from index.mdx frontmatter**

Remove the `image:` and `html:` lines from the hero frontmatter:

Before:
```yaml
hero:
  tagline: One aspect. Every platform. NixOS, Darwin, home-manager — composed, not duplicated.
  image:
    html: |
      <img width="100%" src="https://github.com/user-attachments/assets/af9c9bca-ab8b-4682-8678-31a70d510bbb" />
  actions:
```

After:
```yaml
hero:
  tagline: One aspect. Every platform. NixOS, Darwin, home-manager — composed, not duplicated.
  actions:
```

- [ ] **Step 3: Build and verify**

```bash
cd docs && npm run build
```

Open the built site and verify:
- Landing page: animated topology in hero image slot, title/tagline/buttons on the left
- Toggle light/dark theme: animation colors update
- Scroll down: animation pauses (check devtools performance tab)
- Navigate to another page and back: no errors, animation restarts cleanly

```bash
git add docs/src/components/LogoAnimation.astro docs/src/components/Hero.astro docs/astro.config.mjs docs/src/content/docs/index.mdx
git commit -m "feat(docs): replace static hero image with animated canvas topology"
```
