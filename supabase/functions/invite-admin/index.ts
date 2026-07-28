import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const respond = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  const { email, name, role, locationIds } = await req.json();

  // Verify the caller is actually a super_admin before doing anything
  const authHeader = req.headers.get("Authorization")!;
  const callerClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  );
  const { data: { user } } = await callerClient.auth.getUser();
  if (!user) {
    return respond({ error: "Not authenticated" }, 401);
  }
  const { data: callerProfile } = await callerClient
    .from("admin_profiles")
    .select("role")
    .eq("id", user.id)
    .single();
  if (callerProfile?.role !== "super_admin") {
    return respond({ error: "Not authorized" }, 403);
  }

  // Now use the service role key (only available server-side, inside this function)
  const adminClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );
  const { data: invited, error } = await adminClient.auth.admin.inviteUserByEmail(email);
  if (error) {
    return respond({ error: error.message }, 400);
  }

  const { error: profileError } = await adminClient
    .from("admin_profiles")
    .insert({ id: invited.user.id, name, role, status: "Invited" });
  if (profileError) {
    return respond({ error: profileError.message }, 400);
  }

  if (role === "location_admin" && Array.isArray(locationIds) && locationIds.length > 0) {
    const { error: accessError } = await adminClient
      .from("admin_location_access")
      .insert(locationIds.map((location_id: string) => ({ user_id: invited.user.id, location_id })));
    if (accessError) {
      return respond({ error: accessError.message }, 400);
    }
  }

  return respond({ success: true });
});
