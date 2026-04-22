import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', 
    )

    // We only need the parent's email (login ID) and the new password the admin typed
    const { email, newPassword } = await req.json()

    if (!email || !newPassword) {
      throw new Error("Email and new password are required.");
    }

    // 1. Find the user ID based on the email
    const { data: users, error: searchError } = await supabaseAdmin.auth.admin.listUsers()
    if (searchError) throw searchError;

    const user = users.users.find(u => u.email === email);
    if (!user) throw new Error("Parent account not found in Auth system.");

    // 2. "God Mode" Password Update
    const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
      user.id,
      { password: newPassword }
    );

    if (updateError) throw updateError;

    return new Response(JSON.stringify({ status: 'success' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})