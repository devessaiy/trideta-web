import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Initialize Supabase Client with SERVICE ROLE KEY
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // 2. Get data from the request body
    // Note: We also accept 'passport_url' now
    const { email, password, first_name, last_name, school_id, role, phone, designation, passport_url } = await req.json()

    // 3. Create the User in Supabase Auth
    // We keep first_name and last_name in metadata for flexibility, but Auth doesn't care about table columns
    const { data: user, error: userError } = await supabaseAdmin.auth.admin.createUser({
      email: email,
      password: password,
      email_confirm: true, // Auto-confirm the user
      user_metadata: { 
        first_name: first_name,
        last_name: last_name,
        school_id: school_id,
        role: role 
      }
    })

    if (userError) throw userError

    // 4. Create the Profile Entry (THE FIX IS HERE)
    // We combine names into 'full_name' to match your database schema
    const fullName = `${first_name} ${last_name}`.trim();

    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .insert({
        id: user.user.id,
        role: role,
        email: email,
        full_name: fullName, // Replaces first_name, last_name
        school_id: school_id,
        phone_number: phone,
        designation: designation || 'Educator',
        passport_url: passport_url || null // Save the uploaded photo URL
      })

    if (profileError) throw profileError

    // 5. Success Response
    return new Response(
      JSON.stringify({ 
        user_id: user.user.id, 
        message: "Staff account created successfully" 
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
        status: 200 
      }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
        status: 400 
      }
    )
  }
})