// Cartouche's documentation for players, at https://docs.cartouche.cloud/
// (README.md). Starlight builds it into static pages, in English, French,
// Spanish and German, with its search inside the pages (Pagefind): no font,
// script or request of another site. A page not translated yet shows in
// English, with a note that says so.
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// The groups of the sidebar, in the four languages; each page takes the
// title of its own language.
const group = (en, fr, es, de, items) => ({ label: en, translations: { fr, es, de }, items });

export default defineConfig({
	site: 'https://docs.cartouche.cloud',
	trailingSlash: 'ignore',
	integrations: [
		starlight({
			title: 'Cartouche',
			description: 'How to install Cartouche, build your games and play them on iPhone, iPad and Mac.',
			logo: { src: './src/assets/cartouche.svg', alt: '' },
			favicon: '/favicon.svg',
			defaultLocale: 'root',
			locales: {
				root: { label: 'English', lang: 'en' },
				fr: { label: 'Français', lang: 'fr' },
				es: { label: 'Español', lang: 'es' },
				de: { label: 'Deutsch', lang: 'de' },
			},
			social: [
				{ icon: 'discord', label: 'Discord', href: 'https://discord.gg/wG3DZjdAeF' },
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/cartouche-app/Cartouche' },
			],
			customCss: ['./src/styles/cartouche.css'],
			lastUpdated: false,
			pagination: true,
			credits: false,
			sidebar: [
				group('Start here', 'Pour commencer', 'Primeros pasos', 'Erste Schritte', [
					'start/requirements',
					'start/install',
					'start/sidestore',
					'start/first-game',
				]),
				group('On iPhone and iPad', 'Sur iPhone et iPad', 'En iPhone y iPad', 'Auf iPhone und iPad', [
					'iphone/console',
					'iphone/game-sheet',
					'iphone/game-settings',
					'iphone/playing',
					'iphone/storage',
					'iphone/saves',
					'iphone/system',
					'iphone/ipad',
				]),
				group('Cartouche for Mac', 'Cartouche pour Mac', 'Cartouche para Mac', 'Cartouche für Mac', [
					'mac/install',
					'mac/builder',
					'mac/console',
					'mac/iphone',
				]),
				group('Cartouche Installer', 'Installeur de Cartouche', 'Instalador de Cartouche', 'Cartouche-Installer', [
					'installer',
					'installer/own-certificate',
				]),
				group('Cartouche Cloud', 'Cartouche Cloud', 'Cartouche Cloud', 'Cartouche Cloud', [
					'cloud',
					'cloud/iphone',
				]),
				group('Help', 'Aide', 'Ayuda', 'Hilfe', [
					'help/troubleshooting',
					'help/faq',
					'help/support',
				]),
				group('About', 'À propos', 'Acerca de', 'Über', [
					'about/privacy',
					'about/legal',
				]),
			],
		}),
	],
});
