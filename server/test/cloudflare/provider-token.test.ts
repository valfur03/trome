import { describe, expect, it } from "vitest";
import { ProviderTokens } from "../../src/core/push/provider-token";

/** The token of Apple's push service is signed with Web Crypto: this proves that the Cloudflare runtime reads the `.p8` key and signs as Apple checks. */
describe("the provider token in the Cloudflare runtime", () => {
  it("is an ES256 token that the public key of the key checks", async () => {
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
    const tokens = new ProviderTokens("TEAMID1234", { now: () => Date.parse("2026-10-24T08:00:00Z") });

    const token = await tokens.token({ environment: "production", keyId: "KEYID12345", key: pem });

    const [header = "", claims = "", signature = ""] = token.split(".");
    expect(JSON.parse(atob(header))).toEqual({ alg: "ES256", kid: "KEYID12345" });
    expect(JSON.parse(atob(claims))).toEqual({ iss: "TEAMID1234", iat: Date.parse("2026-10-24T08:00:00Z") / 1000 });
    const bytes = Uint8Array.from(atob(signature.replace(/-/g, "+").replace(/_/g, "/")), (character) => character.charCodeAt(0));
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, bytes, new TextEncoder().encode(`${header}.${claims}`))).toBe(true);
  });
});
