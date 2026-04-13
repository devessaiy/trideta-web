import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  // 1. Setup the "Master Key" client
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  try {
    // 2. Get the student data from your Flutter app
    const { email, phone, studentName } = await req.json()

    // 3. Create the Parent Account (Phone = Password)
    const { data: user, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email: email,
      password: phone, // Sets their phone number as the initial password!
      email_confirm: true, // Auto-confirms so they don't have to check email
      user_metadata: { role: 'parent', student_name: studentName }
    })

    if (createError) throw createError

    return new Response(
      JSON.stringify({ message: "Parent account created!", userId: user.user.id }),
      { headers: { "Content-Type": "application/json" }, status: 200 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { "Content-Type": "application/json" }, status: 400 }
    )
  }
})