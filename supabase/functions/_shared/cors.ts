// CORS za Edge Functions.
//
// Mobilna aplikacija Origin glave sploh ne poslje, zato zanjo CORS ni
// pomemben. Spletna aplikacija (app.herculex.app) jo poslje, in brskalnik
// odgovor sprejme le, ce ga streznik izrecno dovoli. Dovoljeni so:
//   - produkcijski izvori iz ALLOWED_ORIGINS (privzeto app.herculex.app in
//     herculex.app),
//   - Cloudflare Pages predogledi projekta herculex-app,
//   - localhost za razvoj (`flutter run -d chrome --web-port 5555`).
// Zahteva iz katerega koli drugega brskalniskega izvora dobi 403 se preden
// funkcija karkoli naredi; `verify_jwt` ostaja dejanska meja dostopa.

const defaultAllowedOrigins = [
  "https://app.herculex.app",
  "https://herculex.app",
];

const allowedOrigins = new Set(
  (Deno.env.get("ALLOWED_ORIGINS") ?? defaultAllowedOrigins.join(","))
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0),
);

const previewOrigin = /^https:\/\/[a-z0-9-]+\.herculex-app\.pages\.dev$/;
const localOrigin = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

export function isAllowedOrigin(origin: string): boolean {
  return allowedOrigins.has(origin) ||
    previewOrigin.test(origin) ||
    localOrigin.test(origin);
}

/// Glave, ki veljajo za vsak odgovor. `Access-Control-Allow-Origin` doda
/// [withCors] za vsako zahtevo posebej, ker jih je dovoljenih vec.
export const corsHeaders = {
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

/// Ovije handler funkcije: preverjanje izvora, odgovor na preflight in
/// `Access-Control-Allow-Origin` za dovoljene brskalniske izvore.
export function withCors(
  handler: (req: Request) => Promise<Response> | Response,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    const origin = req.headers.get("Origin");
    if (origin !== null && !isAllowedOrigin(origin)) {
      return new Response("Origin not allowed", {
        status: 403,
        headers: { "Vary": "Origin" },
      });
    }

    const response = req.method === "OPTIONS"
      ? new Response("ok", { headers: corsHeaders })
      : await handler(req);

    if (origin === null) return response;
    const headers = new Headers(response.headers);
    headers.set("Access-Control-Allow-Origin", origin);
    for (const [key, value] of Object.entries(corsHeaders)) {
      headers.set(key, value);
    }
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  };
}
