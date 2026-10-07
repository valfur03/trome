import { brokenPackages } from './required-packages.ts';

const broken = await brokenPackages(['@astrojs/check', 'typescript'], (name) => import(name));
if (broken.length > 0) {
  for (const { name, reason } of broken) {
    console.error(`astro check needs ${name}, but it does not load: ${reason}`);
  }
  console.error("Run 'npm ci' in docs/, then run make docs-check again.");
  process.exit(1);
}
