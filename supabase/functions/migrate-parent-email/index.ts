import { createClient } from "npm:@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', 
    )

    const body = await req.json().catch(() => ({}));
    const oldEmail = body.oldEmail?.toLowerCase().trim();
    const newEmail = body.newEmail?.toLowerCase().trim();

    if (!oldEmail || !newEmail) {
      return new Response(JSON.stringify({ error: "Missing email data for migration." }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
    }

    // 1. FAST POSTGRES SEARCH (Bypasses the buggy Supabase listUsers API entirely!)
    const { data: oldUserId, error: rpcError1 } = await supabaseAdmin.rpc('get_user_id_by_email', { user_email: oldEmail });
    const { data: newUserId, error: rpcError2 } = await supabaseAdmin.rpc('get_user_id_by_email', { user_email: newEmail });

    if (rpcError1 || rpcError2) {
         return new Response(JSON.stringify({ error: `RPC Search Error: ${rpcError1?.message || rpcError2?.message}` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
    }

    // 2. MIGRATE AUTH ACCOUNT
    if (newUserId) {
        // Phantom Email already exists! Delete the old redundant account to clean up.
        if (oldUserId) {
            await supabaseAdmin.auth.admin.deleteUser(oldUserId);
        }
    } else if (oldUserId) {
        // Swap the old real email for the new phantom email
        const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
            oldUserId,
            { email: newEmail, email_confirm: true }
        );
        if (updateError) {
             if (updateError.message.toLowerCase().includes("already been registered")) {
                 await supabaseAdmin.auth.admin.deleteUser(oldUserId);
             } else {
                 return new Response(JSON.stringify({ error: `Auth Update Failed: ${updateError.message}` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
             }
        }
    }

    // 3. UPDATE THE DATABASE DIRECTLY
    const { error: dbError } = await supabaseAdmin
        .from('students')
        .update({ parent_email: newEmail })
        .eq('parent_email', oldEmail);

    if (dbError) {
        return new Response(JSON.stringify({ error: `Database Sync Failed: ${dbError.message}` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
    }

    return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })

  } catch (error: any) {
    return new Response(JSON.stringify({ error: `Server Crash: ${error.message}` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
  }
})