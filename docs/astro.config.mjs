// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import starlight from '@astrojs/starlight';

import mermaid from 'astro-mermaid';
import catppuccin from "@catppuccin/starlight";
import starlightLinksValidator from 'starlight-links-validator';
import { unified } from '@astrojs/markdown-remark';
import { wholeTokenTextMarkers } from './src/ec-whole-token-markers.mjs';

// https://astro.build/config
export default defineConfig({
	// Canonical URLs, the sitemap and Open Graph tags are built against this;
	// left unset, all three are either relative or absent.
	site: 'https://den.denful.dev',
	// Sätteri is Astro's default processor; the remark pipeline is opted into
	// explicitly, as gen's site does, so both sites render markdown the same way
	// and remark plugins (astro-mermaid's included) run on it.
	markdown: {
		processor: unified(),
	},
	// Weights must cover every weight the stylesheets request. Without them
	// only 400 is fetched and the browser synthesises bold by thickening the
	// 400 glyphs, which reads as blur — most visibly in the sidebar.
	fonts: [
		{
			provider: fontProviders.google(),
			name: "Victor Mono",
			cssVariable: "--font-victor-mono",
			weights: [400, 600, 700],
			styles: ["normal", "italic"],
		},
		{
			provider: fontProviders.google(),
			name: "JetBrains Mono",
			cssVariable: "--font-jetbrains-mono",
			weights: [400, 600],
			styles: ["normal", "italic"],
		},
	],
	integrations: [
		// Diagrams read the site palette instead of carrying their own scheme.
		// autoTheme only picks between mermaid's 'default' and 'dark', so it is
		// off and the 'base' theme is styled through themeCSS: the SVG resolves
		// --sl-color-* at paint time and follows the light/dark switch with no
		// re-render.
		mermaid({
			theme: 'base',
			autoTheme: false,
			mermaidConfig: {
				themeCSS: [
					'.node rect, .node circle, .node ellipse, .node polygon, .node path {',
					'  fill: color-mix(in srgb, var(--sl-color-accent) 12%, var(--sl-color-bg)) !important;',
					'  stroke: color-mix(in srgb, var(--sl-color-accent) 55%, transparent) !important;',
					'}',
					'.node .label, .nodeLabel, .node text { color: var(--sl-color-white) !important; fill: var(--sl-color-white) !important; }',
					'.edgePath .path, .flowchart-link, .messageLine0, .messageLine1 { stroke: var(--sl-color-gray-3) !important; }',
					'.arrowheadPath, marker path, defs marker path { fill: var(--sl-color-gray-3) !important; stroke: none !important; }',
					'.edgeLabel, .edgeLabel p { background: var(--sl-color-bg) !important; color: var(--sl-color-gray-2) !important; fill: var(--sl-color-bg) !important; }',
					'.edgeLabel .label text, .edgeLabel text { fill: var(--sl-color-gray-2) !important; }',
					'.cluster rect { fill: color-mix(in srgb, var(--sl-color-accent) 5%, var(--sl-color-bg)) !important; stroke: var(--sl-color-hairline-light) !important; }',
					'.cluster text, .cluster .label { fill: var(--sl-color-gray-2) !important; color: var(--sl-color-gray-2) !important; }',
				].join('\n'),
			},
		}),
		starlight({
			title: 'den',
			expressiveCode: {
				plugins: [wholeTokenTextMarkers()],
			},
			social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/denful/den' }
      ],
			// Starlight's own sidebar: a collapsible tree, as on gen's site. A tab
			// switcher used to live here, where picking a tab silently replaced the
			// panel below it.
			sidebar: [
				{
					label: 'Start',
					items: [
						{ label: 'Overview', slug: 'overview' },
						{ label: 'Why Den?', slug: 'motivation' },
						{ label: 'Coming from...', slug: 'explanation/coming-from', badge: { text: 'new', variant: 'success' } },
						{ label: 'From Zero to Den', slug: 'guides/from-zero-to-den' },
						{ label: 'From Flake to Den', slug: 'guides/from-flake-to-den' },
						{ label: 'Migrate to Den', slug: 'guides/migrate' },
						{ label: 'Future: den on gen', slug: 'future', badge: { text: 'new', variant: 'success' } },
					],
				},
				{
					label: 'Understand',
					items: [
						{ label: 'Core Principles', slug: 'explanation/core-principles' },
						{ label: 'Where Does My Config Land?', slug: 'explanation/where-config-lands', badge: { text: 'new', variant: 'success' } },
						{ label: 'Choosing a Mechanism', slug: 'explanation/choosing-a-mechanism', badge: { text: 'new', variant: 'success' } },
						{
							label: 'Entities',
							collapsed: false,
							items: [
								{ label: 'Entities & Schema', slug: 'explanation/entities' },
							],
						},
						{
							label: 'Aspects',
							collapsed: false,
							items: [
								{ label: 'Aspects & Functors', slug: 'explanation/aspects' },
								{ label: 'Class Modules', slug: 'explanation/class-modules' },
								{ label: 'Parametric Aspects', slug: 'explanation/parametric' },
							{ label: 'Structural Introspection', slug: 'explanation/structural-introspection', badge: { text: 'advanced', variant: 'caution' } },
							],
						},
						{
							label: 'Policies',
							collapsed: false,
							items: [
								{ label: 'Policies', slug: 'explanation/policies' },
								{ label: 'Policy Activation', slug: 'explanation/policy-activation' },
							],
						},
						{
							label: 'Quirks & Pipes',
							collapsed: false,
							items: [
								{ label: 'Quirks & Pipes', slug: 'explanation/quirks-and-pipes' },
								{ label: 'Fleets & Multi-Host', slug: 'explanation/fleet' },
							],
						},
						{ label: 'Resolution Pipeline', slug: 'explanation/context-pipeline' },
						{
							label: 'Deep Dives',
							collapsed: true,
							items: [
								{ label: 'Scope Partitioning', slug: 'explanation/scope-partitioning', badge: { text: 'advanced', variant: 'caution' } },
								{ label: 'ABC on Den Effects', slug: 'explanation/effects', badge: { text: 'advanced', variant: 'caution' } },
								{ label: 'Diagrams', slug: 'explanation/diagrams', badge: { text: 'advanced', variant: 'caution' } },
								{ label: 'Library vs Framework', slug: 'explanation/library-vs-framework', badge: { text: 'advanced', variant: 'caution' } },
							],
						},
					],
				},
				{
					label: 'Build',
					items: [
						{
							label: 'Hosts & Users',
							collapsed: false,
							items: [
								{ label: 'Declare Hosts & Users', slug: 'guides/declare-hosts' },
								{ label: 'Configure Aspects', slug: 'guides/configure-aspects' },
								{ label: 'Homes Integration', slug: 'guides/home-manager' },
								{ label: 'Standalone Home Manager', slug: 'guides/standalone-home-manager', badge: { text: 'new', variant: 'success' } },
								{ label: 'Host↔User Mutual Config', slug: 'guides/mutual' },
							],
						},
						{
							label: 'Data Flow',
							collapsed: false,
							items: [
								{ label: 'Quirks & Pipes', slug: 'guides/quirks' },
								{ label: 'Cross-Scope Pipes', slug: 'guides/quirks-cross-scope' },
								{ label: 'Quirk Recipes', slug: 'guides/quirk-recipes', badge: { text: 'new', variant: 'success' } },
								{ label: 'Aspect Settings', slug: 'guides/aspect-settings', badge: { text: 'new', variant: 'success' } },
							],
						},
						{ label: 'nixpkgs: Overlays & Channels', slug: 'guides/nixpkgs', badge: { text: 'new', variant: 'success' } },
						{ label: 'Flake Outputs from Aspects', slug: 'guides/flake-outputs', badge: { text: 'new', variant: 'success' } },
						{ label: 'Use Batteries', slug: 'guides/batteries' },
						{
							label: 'All Batteries',
							collapsed: true,
							items: [
								{ label: 'define-user — OS user accounts', link: '/reference/batteries/#denbatteriesdefine-user' },
								{ label: 'hostname — set system hostname', link: '/reference/batteries/#denbatterieshostname' },
								{ label: 'os class — cross-platform OS config', link: '/reference/batteries/#os-class' },
								{ label: 'user class — users.users forwarding', link: '/reference/batteries/#user-class' },
								{ label: 'primary-user — admin privileges', link: '/reference/batteries/#denbatteriesprimary-user' },
								{ label: 'user-shell — login shell', link: '/reference/batteries/#denbatteriesuser-shell' },
								{ label: 'mutual-provider — host↔user config', link: '/reference/batteries/#denbatteriesmutual-provider' },
								{ label: 'host-aspects — project host classes', link: '/reference/batteries/#denbatterieshost-aspects' },
								{ label: 'tty-autologin — TTY auto-login', link: '/reference/batteries/#denbatteriestty-autologin' },
								{ label: 'vm-autologin — auto-login for VMs', link: '/reference/batteries/#denbatteriesvm-autologin' },
								{ label: 'wsl class — WSL support', link: '/reference/batteries/#wsl-class' },
								{ label: 'forward — custom class factory', link: '/reference/batteries/#denbatteriesforward' },
								{ label: 'import-tree — legacy module import', link: '/reference/batteries/#denbatteriesimport-tree' },
								{ label: 'homeManager class — HM integration', link: '/reference/batteries/#homemanager-class' },
								{ label: 'hjem class — hjem integration', link: '/reference/batteries/#hjem-class' },
								{ label: 'maid class — nix-maid integration', link: '/reference/batteries/#maid-class' },
								{ label: 'unfree — allow unfree packages', link: '/reference/batteries/#denbatteriesunfree' },
								{ label: 'insecure — allow insecure packages', link: '/reference/batteries/#denbatteriesinsecure' },
								{ label: "inputs' — flake-parts inputs", link: '/reference/batteries/#denbatteriesinputs' },
								{ label: "self' — flake-parts self outputs", link: '/reference/batteries/#denbatteriesself' },
								{ label: "flake-scope — lib/inputs/den to pipeline", link: '/reference/batteries/#denbatteriesflake-scope' },
							],
						},
						{
							label: 'Extend',
							collapsed: true,
							items: [
								{ label: 'Custom Nix Classes', slug: 'guides/custom-classes' },
								{ label: 'Share with Namespaces', slug: 'guides/namespaces' },
								{ label: 'Angle Brackets Syntax', slug: 'guides/angle-brackets' },
							],
						},
						{
							label: 'Troubleshooting',
							collapsed: true,
							items: [
								{ label: 'Debug Configurations', slug: 'guides/debug' },
								{ label: 'Bug Reproduction', slug: 'tutorials/bogus' },
							],
						},
					],
				},
				{
					label: 'Examples',
					items: [
						{ label: 'Fleet Demo', slug: 'tutorials/fleet-demo' },
						{ label: 'MicroVM', slug: 'tutorials/microvm' },
						{ label: 'Terranix Demo', slug: 'tutorials/terranix-demo' },
						{ label: 'Custom Class Examples', slug: 'guides/custom-class-examples' },
						{ label: 'Case Study: Kubernetes', slug: 'tutorials/case-study-kubernetes', badge: { text: 'new', variant: 'success' } },
						{ label: 'Case Study: Access Control & Environments', slug: 'guides/acl-environments', badge: { text: 'new', variant: 'success' } },
						{ label: 'Case Study: Disks & Impermanence', slug: 'tutorials/case-study-disks-impermanence', badge: { text: 'new', variant: 'success' } },
						{ label: 'Case Study: Visualising a Fleet', slug: 'tutorials/case-study-diagrams', badge: { text: 'new', variant: 'success' } },
						{
							label: 'Templates',
							collapsed: true,
							items: [
								{ label: 'Overview', slug: 'tutorials/overview' },
								{ label: 'Minimal', slug: 'tutorials/minimal' },
								{ label: 'Default', slug: 'tutorials/default' },
								{ label: 'No-Flake', slug: 'tutorials/noflake' },
								{ label: 'NVF Standalone', slug: 'tutorials/nvf-standalone' },
								{ label: 'Example', slug: 'tutorials/example' },
								{ label: 'Flake Parts Modules', slug: 'tutorials/flake-parts-modules' },
								{ label: 'CI Tests', slug: 'tutorials/ci' },
							],
						},
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Glossary', slug: 'reference/glossary' },
						{ label: 'den.schema', slug: 'reference/schema' },
						{ label: 'den.aspects', slug: 'reference/aspects' },
						{ label: 'den.batteries', slug: 'reference/batteries' },
						{ label: 'den.quirks', slug: 'reference/quirks' },
						{ label: 'den.policies', slug: 'reference/policies' },
						{ label: 'den.lib', slug: 'reference/lib' },
						{ label: 'den.lib.capture & den-diagram', slug: 'reference/diag' },
						{ label: 'flake.*', slug: 'reference/output' },
						{
							label: 'Legacy',
							collapsed: true,
							items: [
								{ label: 'den.ctx (compat)', slug: 'explanation/context-system', badge: { text: 'legacy', variant: 'note' } },
								{ label: 'den.lib (deprecated)', slug: 'reference/lib-deprecated', badge: { text: 'legacy', variant: 'note' } },
								{ label: 'Migrating from den.ctx', slug: 'guides/migrate-ctx', badge: { text: 'legacy', variant: 'note' } },
							],
						},
					],
				},
				{
					label: 'Project',
					collapsed: true,
					items: [
						{ label: 'Versioning', slug: 'releases' },
						{ label: 'Community', slug: 'community' },
						{ label: 'Contributors Guide', slug: 'contributing' },
						{ label: 'Maintainers Guide', slug: 'maintainers' },
					],
				},
			],
			components: {
				Head: './src/components/Head.astro',
				Footer: './src/components/Footer.astro',
				SocialIcons: './src/components/SocialIcons.astro',
				PageSidebar: './src/components/PageSidebar.astro',
				Hero: './src/components/Hero.astro',
			},
			plugins: [
				// A broken cross-reference renders as ordinary text, so nothing on the
				// page says the link went nowhere. Fail the build on one instead.
				starlightLinksValidator({
					errorOnRelativeLinks: false,
					errorOnLocalLinks: false,
				}),
				catppuccin({
					dark: { flavor: "macchiato", accent: "mauve" },
					light: { flavor: "latte", accent: "mauve" },
				}),
			],
			editLink: {
				baseUrl: 'https://github.com/denful/den/edit/main/docs/',
			},
			customCss: [
				'./src/styles/layout.css',
				'./src/styles/custom.css'
			],
		}),
	],
});
