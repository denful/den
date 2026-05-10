// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import starlight from '@astrojs/starlight';

import mermaid from 'astro-mermaid';
import catppuccin from "@catppuccin/starlight";

// https://astro.build/config
export default defineConfig({
	experimental: {
		fonts: [
			{
				provider: fontProviders.google(),
				name: "Victor Mono",
				cssVariable: "--font-victor-mono",
			},
			{
				provider: fontProviders.google(),
				name: "JetBrains Mono",
				cssVariable: "--font-jetbrains-mono",
			},
		],
	},
	integrations: [
		mermaid({
			theme: 'forest',
			autoTheme: true
		}),
		starlight({
			title: 'den',
			social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/denful/den' }
      ],
			sidebar: [
				{
					label: 'Den',
					items: [
						{ label: 'Overview', slug: 'overview' },
						{ label: 'Motivation', slug: 'motivation' },
						{ label: 'Versioning', slug: 'releases' },
						{ label: 'Community', slug: 'community' },
						{ label: 'Contributors Guide', slug: 'contributing' },
						{ label: 'Maintainers Guide', slug: 'maintainers' },
					],
				},
				{
					label: 'Understand',
					items: [
						{ label: 'Core Principles', slug: 'explanation/core-principles' },
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
					label: 'Start',
					items: [
						{ label: 'Coming from...', slug: 'explanation/coming-from', badge: { text: 'new', variant: 'success' } },
						{ label: 'From Zero to Den', slug: 'guides/from-zero-to-den' },
						{ label: 'From Flake to Den', slug: 'guides/from-flake-to-den' },
						{ label: 'Migrate to Den', slug: 'guides/migrate' },
						{
							label: 'Templates',
							collapsed: true,
							items: [
								{ label: 'Overview', slug: 'tutorials/overview' },
								{ label: 'Minimal', slug: 'tutorials/minimal' },
								{ label: 'Default', slug: 'tutorials/default' },
								{ label: 'No-Flake', slug: 'tutorials/noflake' },
								{ label: 'NVF Standalone', slug: 'tutorials/nvf-standalone' },
								{ label: 'MicroVM', slug: 'tutorials/microvm' },
								{ label: 'Example', slug: 'tutorials/example' },
								{ label: 'Fleet Demo', slug: 'tutorials/fleet-demo' },
								{ label: 'Terranix Demo', slug: 'tutorials/terranix-demo' },
								{ label: 'Bug Reproduction', slug: 'tutorials/bogus' },
								{ label: 'CI Tests', slug: 'tutorials/ci' },
								{ label: 'Flake Parts Modules', slug: 'tutorials/flake-parts-modules' },
							],
						},
					],
				},
				{
					label: 'Build',
					items: [
						{ label: 'Declare Hosts & Users', slug: 'guides/declare-hosts' },
						{ label: 'Configure Aspects', slug: 'guides/configure-aspects' },
						{ label: 'Homes Integration', slug: 'guides/home-manager' },
						{ label: 'Use Batteries', slug: 'guides/batteries' },
						{
							label: 'Batteries',
							collapsed: true,
							items: [
								{ label: 'define-user — OS user accounts', link: '/reference/batteries/#den_define-user' },
								{ label: 'hostname — set system hostname', link: '/reference/batteries/#den_hostname' },
								{ label: 'os-class — cross-platform os class', link: '/reference/batteries/#den_os-class' },
								{ label: 'os-user — user class forwarding', link: '/reference/batteries/#den_os-user' },
								{ label: 'primary-user — admin privileges', link: '/reference/batteries/#den_primary-user' },
								{ label: 'user-shell — login shell', link: '/reference/batteries/#den_user-shell' },
								{ label: 'mutual-provider — host↔user config', link: '/reference/batteries/#den_mutual-provider' },
								{ label: 'host-aspects — project host classes', link: '/reference/batteries/#den_host-aspects' },
								{ label: 'tty-autologin — TTY auto-login', link: '/reference/batteries/#den_tty-autologin' },
								{ label: 'wsl — WSL support', link: '/reference/batteries/#den_wsl' },
								{ label: 'forward — custom class factory', link: '/reference/batteries/#den_forward' },
								{ label: 'import-tree — legacy module import', link: '/reference/batteries/#den_import-tree' },
								{ label: 'home-manager — HM integration', link: '/reference/batteries/#den_home-manager' },
								{ label: 'hjem — hjem integration', link: '/reference/batteries/#den_hjem' },
								{ label: 'maid — nix-maid integration', link: '/reference/batteries/#den_maid' },
								{ label: 'unfree — allow unfree packages', link: '/reference/batteries/#den_unfree' },
								{ label: 'insecure — allow insecure packages', link: '/reference/batteries/#den_insecure' },
								{ label: "inputs' — flake-parts inputs", link: '/reference/batteries/#den_inputs' },
								{ label: "self' — flake-parts self outputs", link: '/reference/batteries/#den_self' },
							],
						},
						{ label: 'Host↔User Mutual Config', slug: 'guides/mutual' },
						{ label: 'Share with Namespaces', slug: 'guides/namespaces' },
						{ label: 'Quirks & Pipes', slug: 'guides/quirks' },
						{ label: 'Custom Nix Classes', slug: 'guides/custom-classes' },
						{ label: 'Angle Brackets Syntax', slug: 'guides/angle-brackets' },
						{
							label: 'Troubleshooting',
							collapsed: true,
							items: [
								{ label: 'Debug Configurations', slug: 'guides/debug' },
								{ label: 'Migrating from den.ctx', slug: 'guides/migrate-ctx', badge: { text: 'legacy', variant: 'note' } },
							],
						},
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'den.schema', slug: 'reference/schema' },
						{ label: 'den.aspects', slug: 'reference/aspects' },
						{ label: 'den.batteries', slug: 'reference/batteries' },
						{ label: 'den.ctx (compat)', slug: 'explanation/context-system', badge: { text: 'legacy', variant: 'note' } },
						{ label: 'den.quirks', slug: 'reference/quirks' },
						{ label: 'den.policies', slug: 'reference/policies' },
						{ label: 'den.lib', slug: 'reference/lib' },
						{ label: 'den.lib', slug: 'reference/lib-deprecated', badge: { text: 'legacy', variant: 'note' } },
						{ label: 'den.lib.diag', slug: 'reference/diag' },
						{ label: 'flake.*', slug: 'reference/output' },
						{ label: 'Glossary', slug: 'reference/glossary' },
					],
				},
			],
			components: {
				Head: './src/components/Head.astro',
				Sidebar: './src/components/Sidebar.astro',
				Footer: './src/components/Footer.astro',
				SocialIcons: './src/components/SocialIcons.astro',
				PageSidebar: './src/components/PageSidebar.astro',
				Hero: './src/components/Hero.astro',
			},
			plugins: [
				catppuccin({
					dark: { flavor: "macchiato", accent: "mauve" },
					light: { flavor: "latte", accent: "mauve" },
				}),
			],
			editLink: {
				baseUrl: 'https://github.com/denful/den/edit/main/docs/',
			},
			customCss: [
				'./src/styles/custom.css'
			],
		}),
	],
});
