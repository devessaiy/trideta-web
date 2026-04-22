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

    const { email, password, phone, studentName, usePhoneForLogin } = await req.json()

    // 1. FORMAT PHONE TO E.164
    let formattedPhone = phone;
    if (formattedPhone) {
      formattedPhone = formattedPhone.replace(/\s+/g, ''); 
      if (formattedPhone.startsWith('0')) {
        formattedPhone = '+234' + formattedPhone.substring(1);
      } else if (!formattedPhone.startsWith('+')) {
        formattedPhone = '+234' + formattedPhone;
      }
    }

    if (usePhoneForLogin && (!formattedPhone || !password)) throw new Error("Phone and Password required.")
    if (!usePhoneForLogin && (!email || !password)) throw new Error("Email and Password required.")

    // 2. PREPARE AUTH PAYLOAD
    const userPayload: any = {
      password: password, 
      user_metadata: { role: 'parent', display_name: `Parent of ${studentName}` }
    }

    if (usePhoneForLogin) {
      userPayload.phone = formattedPhone; 
      userPayload.phone_confirm = true;
    } else {
      userPayload.email = email;
      userPayload.email_confirm = true;
    }

    // 3. CREATE AUTH USER
    const { data, error } = await supabaseAdmin.auth.admin.createUser(userPayload)

    if (error) {
      if (error.message.includes("already been registered")) {
        return new Response(JSON.stringify({ message: "User exists" }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        })
      }
      throw error
    }

    // 🚨 4. CREATE THE PUBLIC PROFILE SAFELY
    // Using upsert prevents crashes if your database triggers already created the profile!
    const { error: profileError } = await supabaseAdmin.from('profiles').upsert({
      id: data.user.id,
      role: 'parent',
      full_name: `Parent of ${studentName}`,
    }, { onConflict: 'id' });

    if (profileError) {
        console.error("Profile Upsert Warning:", profileError);
        // We don't throw an error here because the Auth account was already successfully created!
    }

    return new Response(JSON.stringify({ status: 'success', userId: data.user.id }), {
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