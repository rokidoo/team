// Supabase Edge Function: admin-delete-user
// Bu dosyanın TAMAMINI Supabase Dashboard → Edge Functions → admin-delete-user
// fonksiyonunun Code sekmesine yapıştır, sonra Deploy et.
//
// Ekstra secret gerekmez: SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY her
// Edge Function'a Supabase tarafından otomatik tanımlanır.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  // Tarayıcının CORS ön kontrolü (preflight) isteğine yanıt
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace("Bearer ", "");
    if (!jwt) return json({ ok: false, error: "Oturum bulunamadı" }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Çağıranın kimliğini doğrula
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ ok: false, error: "Geçersiz oturum" }, 401);
    const callerId = userData.user.id;

    // Çağıranın gerçekten admin olduğunu doğrula
    const { data: callerProfile } = await admin.from("profiles").select("role").eq("id", callerId).maybeSingle();
    if (callerProfile?.role !== "admin") return json({ ok: false, error: "Bu işlem için yetkin yok" }, 403);

    const { targetUserId } = await req.json();
    if (!targetUserId) return json({ ok: false, error: "targetUserId gerekli" }, 400);
    if (targetUserId === callerId) return json({ ok: false, error: "Kendi hesabını silemezsin" }, 400);

    const { error: delErr } = await admin.auth.admin.deleteUser(targetUserId);
    if (delErr) return json({ ok: false, error: delErr.message }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
});
