// @ts-check
// User documentation site (docs/adr/0015-node-toolchain-for-user-docs.md). Pages link to each
// other by root-relative routes (`/guides/package/`); `zig build check-docs` and the links
// validator below both resolve them against src/content/docs. Chinese pages live under
// src/content/docs/zh/ and their UI strings in src/content/i18n/zh-CN.json
// (docs/adr/0017-chinese-user-documentation.md), which keeps this file English.
import { defineConfig } from 'astro/config';
import { satteri } from '@astrojs/markdown-satteri';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';
import starlightLlmsTxt from 'starlight-llms-txt';
import en from './src/content/i18n/en.json' with { type: 'json' };
import zh from './src/content/i18n/zh-CN.json' with { type: 'json' };
import { baseLinks } from './src/markdown/base-links.mjs';
import { docsBase } from './src/site-version.mjs';

const repository = 'https://github.com/niobium-project/niobium';
const legacyPages = [
  'start',
  'guides/**',
  'concepts/{trust,channels,app-bootstrap}',
  'reference/{manifest,setup-cli,nbpack-cli,exit-codes,events,c-abi,artifact-format,repository-layout}',
];

/** Sidebar label in both locales. @param {keyof typeof en & keyof typeof zh} key */
const label = (key) => ({ label: en[key], translations: { 'zh-CN': zh[key] } });

export default defineConfig({
  site: 'https://niobium-project.dev',
  base: docsBase,
  trailingSlash: 'always',
  // `## Heading { #id }` keeps a translated heading's anchor equal to the English one.
  markdown: {
    processor: satteri({
      mdastPlugins: [baseLinks(docsBase)],
      features: { headingAttributes: true },
    }),
  },
  integrations: [
    starlight({
      title: 'Niobium',
      description:
        'An installation and distribution DSL with an AOT compiler and precompiled native runtime.',
      customCss: ['./src/styles/custom.css'],
      defaultLocale: 'root',
      locales: {
        root: { label: en['niobium.locale.label'], lang: 'en' },
        zh: { label: zh['niobium.locale.label'], lang: 'zh-CN' },
      },
      social: [{ icon: 'github', label: 'GitHub', href: repository }],
      editLink: { baseUrl: `${repository}/edit/main/apps/user-docs/` },
      components: {
        Banner: './src/components/Banner.astro',
        LanguageSelect: './src/components/LanguageSelect.astro',
      },
      plugins: [
        starlightLinksValidator(),
        starlightLlmsTxt({
          projectName: 'Niobium',
          demote: legacyPages,
          exclude: legacyPages,
        }),
      ],
      sidebar: [
        {
          ...label('niobium.sidebar.startHere'),
          items: [
            { ...label('niobium.sidebar.overview'), slug: 'index' },
            { ...label('niobium.sidebar.tutorial'), slug: 'tutorial' },
          ],
        },
        {
          ...label('niobium.sidebar.tutorial'),
          items: [
            {
              ...label('niobium.sidebar.tutorialProduct'),
              items: [
                'tutorial/setup',
                'tutorial/first-installer',
                'tutorial/configure-update-remove',
              ],
            },
            {
              ...label('niobium.sidebar.tutorialModel'),
              items: [
                'tutorial/syntax',
                'tutorial/values-bindings',
                'tutorial/content-capabilities',
                'tutorial/functions-modules',
                'tutorial/compilation-diagnostics',
              ],
            },
          ],
        },
        {
          ...label('niobium.sidebar.concepts'),
          items: [
            'concepts/desired-state',
            'concepts/artifacts',
            'concepts/transactions',
            'concepts/privilege',
          ],
        },
        'security',
        'status',
        'platforms',
        'roadmap',
        'troubleshooting',
        'about',
        {
          ...label('niobium.sidebar.reference'),
          items: ['reference/glossary'],
        },
        {
          ...label('niobium.sidebar.legacy'),
          collapsed: true,
          items: [
            { ...label('niobium.sidebar.legacyTutorial'), slug: 'start' },
            {
              ...label('niobium.sidebar.concepts'),
              items: ['concepts/trust', 'concepts/channels', 'concepts/app-bootstrap'],
            },
            {
              ...label('niobium.sidebar.guides'),
              items: [
                'guides/package',
                'guides/sign-and-keys',
                'guides/publish-and-host',
                'guides/app-bootstrap',
                'guides/embed-c-abi',
                'guides/silent-install',
              ],
            },
            {
              ...label('niobium.sidebar.reference'),
              items: [
                'reference/manifest',
                'reference/setup-cli',
                'reference/nbpack-cli',
                'reference/exit-codes',
                'reference/events',
                'reference/c-abi',
                'reference/artifact-format',
                'reference/repository-layout',
              ],
            },
          ],
        },
      ],
    }),
  ],
});
