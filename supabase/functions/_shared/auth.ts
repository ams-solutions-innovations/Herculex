// Prebere `sub` iz ze platformsko preverjenega JWT. Ne preverja podpisa —
// to je ze naredila platforma (`verify_jwt = true` v config.toml za vsako
// funkcijo, ki to uporablja); ce bi bil ta pogoj kdaj izklopljen za katero
// od njih, ta funkcija zanjo ni vec dovolj in mora nazaj na
// `supabase.auth.getUser()`.
export function callerUserId(authHeader: string | null): string | null {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length);
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    let base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4 !== 0) base64 += "=";
    const claims = JSON.parse(atob(base64));
    return typeof claims.sub === "string" ? claims.sub : null;
  } catch {
    return null;
  }
}
