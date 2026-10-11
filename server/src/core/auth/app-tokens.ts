const separators = /[\s,]+/;

/**
 * The app tokens that the server accepts, read from the `APP_TOKEN` secret: one token, or several separated by commas.
 * Every build that riders hold keeps its token, so a new token joins the list and an old one leaves it later, never in the same change.
 * Spaces around a token are ignored, so `old, new` and `old,new` give the same list; a token never holds a comma or a space.
 */
export function appTokens(secret: string | undefined): string[] {
  return (secret ?? "").split(separators).filter((token) => token.length > 0);
}
