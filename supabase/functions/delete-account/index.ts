// Account deletion — the server half of "delete my account".
//
// Required by App Store Guideline 5.1.1(v) (an app that lets a user create an
// account must let them delete it from inside the app) and by GDPR Article 17.
// The client cannot do this itself: `auth.users` is not reachable from the
// anon/authenticated roles, so deletion has to run behind the service-role
// key, which is exactly what an Edge Function is for.
//
// The heavy lifting is already in the schema. Every one of the 36 synced
// tables declares `user_id uuid not null references auth.users(id) on delete
// cascade` (0001/0002), so removing the auth row removes every row the user
// ever synced, in one statement, with no table list to keep in step.
//
// Two things the cascade does NOT cover, handled explicitly below:
//
//   1. `sync_tombstones.user_id` is deliberately not a FK — 0005 explains why
//      (the cascade deletes the parent auth row *before* the child deletes
//      run, so a tombstone written by a cascaded delete would reference a
//      user that no longer exists and abort the whole deletion). So the
//      cascade both leaves the user's existing tombstones behind AND writes a
//      fresh one per deleted row. They are swept after 90 days by 0006's
//      pg_cron job, but "deleted" should mean deleted now, so they are
//      removed here — after the auth delete, or the cascade would just
//      re-create them.
//
//   2. Storage objects in the private `user-photos` bucket (0008). No client
//      code writes to that bucket today, so this is currently a no-op; it is
//      here so that the day progress-photo upload lands, deletion is already
//      complete rather than silently leaving a folder of body photos behind.
//
// `product_catalogue.contributed_by` is `on delete set null` on purpose and is
// NOT cleaned up here: those rows are shared community nutrition data, not
// personal data, and the cascade already anonymizes them.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const photoBucket = "user-photos";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Account deletion is not configured on the server." }, 503);
  }

  // verify_jwt = true in config.toml, so the platform has already rejected
  // anything with an invalid signature — reading the `sub` claim is enough,
  // and it is the ONLY id this function will ever act on. There is
  // deliberately no user id in the request body: a caller can only ever
  // delete themselves.
  const userId = callerUserId(req.headers.get("authorization"));
  if (!userId) {
    return json({ error: "Unauthorized." }, 401);
  }

  // Best-effort, and deliberately before the point of no return: a storage
  // failure must not leave the account half-deleted, so it only logs.
  await deleteUserPhotos(userId);

  const deleted = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${userId}`,
    {
      method: "DELETE",
      headers: {
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
    },
  );

  // 404 means the auth row is already gone — a retry of a call that partly
  // succeeded, or a double tap. Treat it as success so the client can finish
  // wiping the device instead of being stuck with an undeletable account.
  if (!deleted.ok && deleted.status !== 404) {
    const body = await deleted.text();
    console.error("auth admin delete failed", deleted.status, body);
    return json({ error: "Failed to delete account." }, 502);
  }

  // Must run after the auth delete: the cascade writes one tombstone per
  // deleted row, so anything removed before it would come straight back.
  const tombstones = await fetch(
    `${supabaseUrl}/rest/v1/sync_tombstones?user_id=eq.${userId}`,
    {
      method: "DELETE",
      headers: {
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
        "Prefer": "return=minimal",
      },
    },
  );

  if (!tombstones.ok) {
    // The account itself is gone, which is the part the user asked for and
    // the part the store guideline is about. Orphaned tombstones carry no
    // personal data beyond a dead user id and 0006's retention job sweeps
    // them within 90 days, so this is logged, not surfaced as a failure.
    console.error(
      "sync_tombstones cleanup failed",
      tombstones.status,
      await tombstones.text(),
    );
  }

  return json({ ok: true });
});

/// Removes everything under `<user_id>/` in the private photo bucket.
///
/// 0008 documents the layout as `<user_id>/<photo_category>/<uuid>.jpg`, so
/// this walks exactly those two levels rather than recursing blindly. Any
/// failure is logged and swallowed — see the call site.
async function deleteUserPhotos(userId: string): Promise<void> {
  try {
    const categories = await listStorage(`${userId}/`);
    const paths: string[] = [];
    for (const category of categories) {
      const objects = await listStorage(`${userId}/${category}/`);
      for (const object of objects) {
        paths.push(`${userId}/${category}/${object}`);
      }
    }
    if (paths.length === 0) return;

    const removed = await fetch(
      `${supabaseUrl}/storage/v1/object/${photoBucket}`,
      {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "apikey": serviceRoleKey!,
          "Authorization": `Bearer ${serviceRoleKey}`,
        },
        body: JSON.stringify({ prefixes: paths }),
      },
    );
    if (!removed.ok) {
      console.error("photo delete failed", removed.status, await removed.text());
    }
  } catch (error) {
    console.error("photo cleanup threw", error);
  }
}

async function listStorage(prefix: string): Promise<string[]> {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/list/${photoBucket}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey!,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({ prefix, limit: 1000 }),
    },
  );
  if (!response.ok) {
    console.error("storage list failed", response.status, await response.text());
    return [];
  }
  const rows = await response.json() as { name?: string }[];
  return rows.map((row) => row.name).filter((name): name is string => !!name);
}

/// Extracts the `sub` claim from the already-platform-verified JWT. Same
/// helper, same reasoning as `product-catalogue-publish`.
function callerUserId(authHeader: string | null): string | null {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length);
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    let base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4 !== 0) base64 += "=";
    const payload = JSON.parse(atob(base64));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
