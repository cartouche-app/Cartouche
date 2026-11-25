// The documentation's pages, src/content/docs/: English at the root, and
// French, Spanish and German under fr/, es/ and de/ (astro.config.mjs). The
// words of Starlight's own interface that it does not translate, as the
// search's in French, are in src/content/i18n/.
import { defineCollection } from 'astro:content';
import { docsLoader, i18nLoader } from '@astrojs/starlight/loaders';
import { docsSchema, i18nSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
	i18n: defineCollection({ loader: i18nLoader(), schema: i18nSchema() }),
};
