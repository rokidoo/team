// Supabase Edge Function: send-push  (yeni proje · Remaks Ekip v2)
// Supabase Dashboard → Edge Functions → send-push → kod editörüne yapıştır → Deploy
// Secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY  (SUPABASE_URL ve SERVICE_ROLE otomatik)
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
webpush.setVapidDetails("mailto:satin.yasin1999@gmail.com", Deno.env.get("VAPID_PUBLIC_KEY")!, Deno.env.get("VAPID_PRIVATE_KEY")!);

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const task = payload.record;
    if (!task || !task.user_id) return new Response("no task record", { status: 200 });
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const { data: subs, error } = await supabase.from("push_subscriptions").select("*").eq("user_id", task.user_id);
    if (error) return new Response("db error: " + error.message, { status: 500 });
    if (!subs || subs.length === 0) return new Response("no subscriptions", { status: 200 });
    const body = JSON.stringify({ title: "Yeni görev atandı", body: task.title, tag: "remaks-task-" + task.id });
    for (const sub of subs) {
      try { await webpush.sendNotification({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } }, body); }
      catch (err) { const s = err?.statusCode; if (s === 404 || s === 410) await supabase.from("push_subscriptions").delete().eq("id", sub.id); }
    }
    return new Response("ok", { status: 200 });
  } catch (e) { return new Response("error: " + e.message, { status: 500 }); }
});
