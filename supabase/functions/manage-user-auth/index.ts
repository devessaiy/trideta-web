import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  try {
    const { action, email } = await req.json()

    if (action === 'delete') {
      // 1. Find the user by email
      const { data: listUsers, error: listError } = await supabaseAdmin.auth.admin.listUsers()
      if (listError) throw listError

      const userToDelete = listUsers.users.find(u => u.email === email)

      if (!userToDelete) {
        return new Response(JSON.stringify({ message: "User not found, nothing to delete." }), { status: 200 })
      }

      // 2. Delete the user from Auth
      const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(userToDelete.id)
      if (deleteError) throw deleteError

      return new Response(JSON.stringify({ message: "User auth deleted successfully" }), { status: 200 })
    }

    return new Response(JSON.stringify({ error: "Invalid action" }), { status: 400 })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
})