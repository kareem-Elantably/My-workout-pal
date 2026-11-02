// Deletes the signed-in user's account: their files in storage first, then
// the auth user, which cascades to all their data in the database.
// Subscriptions are kept with the trainee/coach set to null (earnings history).
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// Buckets whose files live under "<user id>/".
const BUCKETS = ["milestone-images", "certificates", "avatars"];

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "not signed in" }, 401);
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) return json({ error: "not signed in" }, 401);

  for (const bucket of BUCKETS) {
    const paths = await listAll(bucket, user.id);
    for (let i = 0; i < paths.length; i += 100) {
      await admin.storage.from(bucket).remove(paths.slice(i, i + 100));
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return json({ error: deleteError.message }, 500);
  return json({ deleted: true });
});

/** Every file under a folder, including sub-folders. */
async function listAll(bucket: string, folder: string): Promise<string[]> {
  const paths: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data } = await admin.storage.from(bucket).list(folder, { limit: 1000, offset });
    if (!data?.length) break;
    for (const entry of data) {
      const path = `${folder}/${entry.name}`;
      if (entry.id === null) paths.push(...(await listAll(bucket, path))); // a sub-folder
      else paths.push(path);
    }
    if (data.length < 1000) break;
  }
  return paths;
}
