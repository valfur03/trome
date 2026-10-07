export type BrokenPackage = { name: string; reason: string };

export async function brokenPackages(names: string[], load: (name: string) => Promise<unknown>): Promise<BrokenPackage[]> {
  const broken: BrokenPackage[] = [];
  for (const name of names) {
    try {
      await load(name);
    } catch (error) {
      broken.push({ name, reason: error instanceof Error ? error.message : String(error) });
    }
  }
  return broken;
}
