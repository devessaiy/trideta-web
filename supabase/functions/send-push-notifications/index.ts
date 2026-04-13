import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { JWT } from "npm:google-auth-library@9"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const payload = await req.json()
    // 'record' is for INSERT/UPDATE. 'old_record' is for DELETE.
    const { table, type, record, old_record } = payload
    
    const activeRecord = type === 'DELETE' ? old_record : record
    if (!activeRecord) throw new Error("No record found in payload.")

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, supabaseKey)

    let targetRole = ''
    let notificationTitle = ''
    let notificationBody = ''
    const schoolId = activeRecord.school_id

    // ==========================================
    // 🚦 THE RBAC ROUTER
    // ==========================================

    // 1. ALERTS (Admin creates/deletes a notice -> Notify Parents)
    if (table === 'alerts') {
      targetRole = 'parent'
      if (type === 'INSERT') {
        notificationTitle = activeRecord.title || "School Alert 🔔"
        notificationBody = activeRecord.message || "You have a new message from the school."
      } else if (type === 'DELETE') {
        notificationTitle = "Alert Removed 🗑️"
        notificationBody = "A previous school notice has been removed."
      }
    } 
    // 2. TRANSACTIONS/FEES (Parent pays -> Notify Admins)
    else if (table === 'transactions') {
      targetRole = 'admin'
      if (type === 'INSERT') {
        notificationTitle = "Payment Logged 💰"
        notificationBody = "A new fee payment has been recorded."
      } else if (type === 'DELETE') {
        notificationTitle = "Payment Voided ⚠️"
        notificationBody = "A fee record has been deleted from the system."
      }
    }
    // (You can easily add more tables here later!)
    else {
      return new Response(JSON.stringify({ message: "No RBAC rule for this table/action." }), { headers: corsHeaders, status: 200 })
    }

    // ==========================================
    // 🔍 FETCH FCM TOKENS FOR TARGET ROLE
    // ==========================================
    let targetTokens: string[] = []
    
    // Strict RBAC Query: Must match the School ID AND the specific Role
    const { data, error } = await supabase
      .from('profiles')
      .select('fcm_tokens')
      .eq('school_id', schoolId)
      .eq('role', targetRole)

    if (error) throw new Error(`Database error: ${error.message}`)

    data?.forEach(profile => {
      if (profile.fcm_tokens && Array.isArray(profile.fcm_tokens)) {
        targetTokens.push(...profile.fcm_tokens)
      }
    })

    // Remove duplicate tokens
    targetTokens = [...new Set(targetTokens)]

    if (targetTokens.length === 0) {
      console.log(`No tokens found for role: ${targetRole} in school: ${schoolId}`)
      return new Response(JSON.stringify({ success: true, message: "No tokens to notify" }), { headers: corsHeaders, status: 200 })
    }

    // ==========================================
    // 🚀 FIRE TO GOOGLE CLOUD MESSAGING
    // ==========================================
    const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!serviceAccountStr) throw new Error("Missing FIREBASE_SERVICE_ACCOUNT secret.")
    const serviceAccount = JSON.parse(serviceAccountStr)

    const jwtClient = new JWT({
      email: serviceAccount.client_email,
      key: serviceAccount.private_key,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })
    const tokens = await jwtClient.authorize()

    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`

    const sendPromises = targetTokens.map(token => {
      return fetch(fcmUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${tokens.access_token}`
        },
        body: JSON.stringify({
          message: {
            token: token,
            notification: { title: notificationTitle, body: notificationBody },
            data: { click_action: "FLUTTER_NOTIFICATION_CLICK" }
          }
        })
      })
    })

    await Promise.all(sendPromises)
    console.log(`✅ Success! Sent to ${targetTokens.length} ${targetRole}s.`)

    return new Response(JSON.stringify({ success: true }), { headers: corsHeaders, status: 200 })

  } catch (error) {
    console.error("🚨 Edge Function Crash:", error.message)
    return new Response(JSON.stringify({ error: error.message }), { headers: corsHeaders, status: 500 })
  }
})