import { supabase } from '../../lib/supabase'

export const MSG_TEMPLATES = {
  reserved: (b) => `Vaše rezervace motorky ${b.motorcycles?.model || ''} (${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}) byla potvrzena. Smlouvu a fakturu najdete v sekci Dokumenty.`,
  active: (b) => `Motorka ${b.motorcycles?.model || ''} byla vydána. Přejeme příjemnou jízdu! V případě problému nás kontaktujte nebo použijte SOS tlačítko.`,
  completed: (b) => `Vaše jízda na ${b.motorcycles?.model || ''} byla dokončena. Děkujeme a těšíme se na příště! Konečnou fakturu najdete v sekci Dokumenty.`,
}

export async function logAudit(action, details) {
  try { const { data: { user } } = await supabase.auth.getUser(); await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details }) } catch {}
}

export async function sendBookingMessage(status, bk) {
  const template = MSG_TEMPLATES[status]
  if (!template || !bk.user_id) return
  try {
    let { data: thread } = await supabase.from('message_threads').select('id').eq('customer_id', bk.user_id).limit(1).single()
    if (!thread) {
      const { data: newThread } = await supabase.from('message_threads').insert({ customer_id: bk.user_id, subject: 'Rezervace', channel: 'app' }).select('id').single()
      thread = newThread
    }
    if (!thread) return
    await supabase.from('messages').insert({ thread_id: thread.id, direction: 'admin', sender_name: 'MotoGo', content: template(bk) })
    await supabase.from('message_threads').update({ last_message_at: new Date().toISOString() }).eq('id', thread.id)
  } catch {}
}
