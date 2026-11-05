// Edge Function: create-user
// Lets a super admin create a sign-in account and give it a role in one step.
// The secret (service role) key stays on Supabase's server; the app never sees it.
//
// Body: { email, password, role: "admin" | "super_admin", branch_id? }

import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Use POST" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Who is calling? Must be a signed-in super admin.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth } = await admin.auth.getUser(token);
  if (!auth?.user) return reply(401, { error: "Please sign in again" });

  const { data: caller } = await admin
    .from("profiles")
    .select("role")
    .eq("user_id", auth.user.id)
    .maybeSingle();
  if (caller?.role !== "super_admin") {
    return reply(403, { error: "Only a super admin can add users" });
  }

  // Validate the request.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "Invalid request" });
  }
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const role = String(body.role ?? "");
  const branchId = body.branch_id ? String(body.branch_id) : null;

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return reply(400, { error: "Enter a valid email" });
  }
  if (password.length < 8) {
    return reply(400, { error: "Password must be at least 8 characters" });
  }
  if (role !== "admin" && role !== "super_admin") {
    return reply(400, { error: "Choose a role" });
  }
  if (role === "admin") {
    if (!branchId) return reply(400, { error: "Choose a branch for the admin" });
    const { data: branch } = await admin
      .from("branches").select("id").eq("id", branchId).maybeSingle();
    if (!branch) return reply(400, { error: "Branch not found" });
  }

  // Create the login, already confirmed so they can sign in straight away.
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createError || !created.user) {
    const msg = createError?.message ?? "Could not create user";
    return reply(400, {
      error: /already|registered|exists/i.test(msg)
        ? "A user with this email already exists"
        : msg,
    });
  }

  // Give the role. If that fails, remove the login so nothing is half-made.
  const { error: profileError } = await admin.from("profiles").insert({
    user_id: created.user.id,
    role,
    branch_id: role === "admin" ? branchId : null,
  });
  if (profileError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return reply(400, { error: profileError.message });
  }

  return reply(200, { user_id: created.user.id, email });
});
