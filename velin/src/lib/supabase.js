import { createClient } from '@supabase/supabase-js'

export const supabaseUrl = 'https://vnwnqteskbykeucanlhk.supabase.co'
export const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZud25xdGVza2J5a2V1Y2FubGhrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0OTEzNjMsImV4cCI6MjA4ODA2NzM2M30.AiHfmfEQK9KD9TvxX5XLWVGaOhEV7kiMwwMwMWp0Ruo'

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
