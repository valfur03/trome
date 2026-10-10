/** The value of each sample of a metrics text, by its line before the value (the name and the labels). */
export function parseMetrics(text: string): Map<string, number> {
  const values = new Map<string, number>();
  for (const line of text.split("\n")) {
    if (line === "" || line.startsWith("#")) {
      continue;
    }
    const space = line.lastIndexOf(" ");
    values.set(line.slice(0, space), Number(line.slice(space + 1)));
  }
  return values;
}
