// Sends one notification to the recipient's phones through Firebase Cloud
// Messaging (HTTP v1). Called by a database trigger with
// { notification_id }. It claims the row by setting pushed_at, so each
// notification is pushed at most once, whoever calls it.
//
// Secret: FCM_SERVICE_ACCOUNT = the Firebase service-account JSON
// (Firebase console -> Project settings -> Service accounts).
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { render } from "./messages.ts";

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return json({ skipped: "FCM_SERVICE_ACCOUNT is not set" });
  const account: ServiceAccount = JSON.parse(raw);

  const { notification_id } = await req.json().catch(() => ({}));
  if (typeof notification_id !== "string") return json({ error: "notification_id required" }, 400);

  // Claim it: only one call can move pushed_at from null.
  const { data: n } = await supabase
    .from("notifications")
    .update({ pushed_at: new Date().toISOString() })
    .eq("id", notification_id)
    .is("pushed_at", null)
    .select("id, recipient_id, type_key, title, body, data")
    .maybeSingle();
  if (!n) return json({ skipped: "already pushed or not found" });

  const [{ data: profile }, { data: tokens }] = await Promise.all([
    supabase.from("profiles").select("locale").eq("id", n.recipient_id).maybeSingle(),
    supabase.from("device_tokens").select("token").eq("user_id", n.recipient_id),
  ]);
  if (!tokens?.length) return json({ sent: 0 });

  const data = (n.data ?? {}) as Record<string, unknown>;
  let traineeName: string | undefined;
  if (typeof data.trainee_id === "string") {
    const { data: trainee } = await supabase.from("profiles").select("full_name").eq("id", data.trainee_id).maybeSingle();
    traineeName = trainee?.full_name;
  }
  const lang = profile?.locale === "en" ? "en" : "ar";
  const text = n.type_key === "custom"
    ? { title: n.title ?? "", body: n.body ?? "" }
    : render(n.type_key, data, lang, { trainee: traineeName });
  if (!text) return json({ skipped: `no push text for ${n.type_key}` });

  const accessToken = await googleAccessToken(account);
  // FCM data values must be strings; the app uses them to open the right screen.
  const payloadData: Record<string, string> = { notification_id: n.id, type: n.type_key };
  for (const [key, value] of Object.entries(data)) payloadData[key] = typeof value === "string" ? value : JSON.stringify(value);

  let sent = 0;
  for (const { token } of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: text.title, body: text.body },
          data: payloadData,
          android: { priority: "high", notification: { channel_id: "default" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    });
    if (res.ok) {
      sent++;
    } else if (res.status === 404 || res.status === 400) {
      // The app was uninstalled or the token is stale: forget it.
      const error = await res.text();
      if (error.includes("UNREGISTERED") || error.includes("INVALID_ARGUMENT")) {
        await supabase.from("device_tokens").delete().eq("token", token);
      }
    }
  }
  return json({ sent });
});

/** OAuth token for FCM from the service account (JWT bearer grant). */
async function googleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value: unknown) =>
    btoa(JSON.stringify(value)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const pem = account.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const jwt = `${unsigned}.${btoa(String.fromCharCode(...signature)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_")}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`Google token request failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}
