import { useState, useEffect } from 'react'
import Button from '../components/ui/Button'
import { supabase } from '../lib/supabase'
import { debugAction, debugLog, debugError } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { isRevenueEntry } from '../lib/revenueUtils'
import RevenueChart from './statistics/RevenueChart'
import { FleetUtilization, TopMotoRevenue, BranchComparison } from './statistics/FleetCharts'
import { BookingsByStatus, CustomerRetention } from './statistics/BookingCharts'

export default function Statistics() {
  const debugMode = useDebugMode()
  const [error, setError] = useState(null)
  const [generating, setGenerating] = useState(false)
  const [stats, setStats] = useState({ bookings: 0, customers: 0, motos: 0, revenue: 0 })
  const [chartErrors, setChartErrors] = useState([])

  useEffect(() => { debugLog('page.mount', 'Statistics'); loadQuickStats() }, [])

  async function loadQuickStats() {
    try {
      const [bk, pr, mo, ae] = await debugAction('statistics.quickStats', 'Statistics', () => Promise.all([
        supabase.from('bookings').select('id', { count: 'exact', head: true }),
        supabase.from('profiles').select('id', { count: 'exact', head: true }),
        supabase.from('motorcycles').select('id', { count: 'exact', head: true }).eq('status', 'active'),
        supabase.from('accounting_entries').select('type, amount, category, description'),
      ]))
      setStats({
        bookings: bk.count || 0,
        customers: pr.count || 0,
        motos: mo.count || 0,
        revenue: (ae.data || []).filter(e => isRevenueEntry(e)).reduce((s, e) => s + Math.abs(e.amount || 0), 0),
      })
    } catch (e) { debugError('statistics.quickStats', 'Statistics', e) }
  }

  async function handleGenerateReport() {
    debugLog('report.generate', 'Statistics', { action: 'start' })
    setGenerating(true)
    setError(null)
    try {
      const now = new Date()
      const period = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
      const { data, error } = await debugAction('report.generate', 'Statistics', () =>
        supabase.functions.invoke('generate-report', {
          body: { type: 'monthly', period },
        })
      )
      if (error) throw error
      if (data?.url) window.open(data.url, '_blank')
    } catch (e) {
      debugError('report.generate', 'Statistics', e)
      setError('Generování reportu selhalo: ' + e.message)
    } finally {
      setGenerating(false)
    }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <Button green onClick={handleGenerateReport} disabled={generating}>
          {generating ? 'Generuji…' : 'Generovat report'}
        </Button>
        {error && <span className="text-sm" style={{ color: '#dc2626' }}>{error}</span>}
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Statistics</strong><br/>
        <div>bookings: {stats.bookings}, customers: {stats.customers}, active motos: {stats.motos}</div>
        <div>total revenue (accounting): {fmt(stats.revenue)}</div>
        {chartErrors.length > 0 && <div style={{ color: '#dc2626' }}>Chart errors: {chartErrors.join(', ')}</div>}
      </div>
      )}

      <div className="grid grid-cols-2 gap-5">
        <div className="col-span-2">
          <ChartWrapper name="RevenueChart" onError={e => setChartErrors(ce => [...ce, 'Revenue: ' + e])}>
            <RevenueChart />
          </ChartWrapper>
        </div>
        <ChartWrapper name="FleetUtilization" onError={e => setChartErrors(ce => [...ce, 'FleetUtil: ' + e])}>
          <FleetUtilization />
        </ChartWrapper>
        <ChartWrapper name="TopMotoRevenue" onError={e => setChartErrors(ce => [...ce, 'TopMoto: ' + e])}>
          <TopMotoRevenue />
        </ChartWrapper>
        <ChartWrapper name="BranchComparison" onError={e => setChartErrors(ce => [...ce, 'Branch: ' + e])}>
          <BranchComparison />
        </ChartWrapper>
        <ChartWrapper name="BookingsByStatus" onError={e => setChartErrors(ce => [...ce, 'Bookings: ' + e])}>
          <BookingsByStatus />
        </ChartWrapper>
        <div className="col-span-2">
          <ChartWrapper name="CustomerRetention" onError={e => setChartErrors(ce => [...ce, 'Retention: ' + e])}>
            <CustomerRetention />
          </ChartWrapper>
        </div>
      </div>
    </div>
  )
}

import { Component } from 'react'

class ChartWrapper extends Component {
  constructor(props) {
    super(props)
    this.state = { hasError: false, error: null }
  }
  static getDerivedStateFromError(error) {
    return { hasError: true, error: error.message }
  }
  componentDidCatch(error) {
    if (this.props.onError) this.props.onError(error.message)
  }
  render() {
    if (this.state.hasError) {
      return (
        <div className="p-4 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 12 }}>
          <strong>{this.props.name}</strong>: Chyba při načítání grafu — {this.state.error}
        </div>
      )
    }
    return this.props.children
  }
}
