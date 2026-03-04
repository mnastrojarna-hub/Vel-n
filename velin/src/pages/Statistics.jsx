import { useState } from 'react'
import Button from '../components/ui/Button'
import { supabase } from '../lib/supabase'
import RevenueChart from './statistics/RevenueChart'
import { FleetUtilization, TopMotoRevenue, BranchComparison } from './statistics/FleetCharts'
import { BookingsByStatus, CustomerRetention } from './statistics/BookingCharts'

export default function Statistics() {
  const [error, setError] = useState(null)
  const [generating, setGenerating] = useState(false)

  async function handleGenerateReport() {
    setGenerating(true)
    setError(null)
    try {
      const now = new Date()
      const period = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
      const { data, error } = await supabase.functions.invoke('generate-report', {
        body: { type: 'monthly', period },
      })
      if (error) throw error
      if (data?.url) window.open(data.url, '_blank')
    } catch (e) {
      setError('Generování reportu selhalo: ' + e.message)
    } finally {
      setGenerating(false)
    }
  }

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <Button green onClick={handleGenerateReport} disabled={generating}>
          {generating ? 'Generuji…' : 'Generovat report'}
        </Button>
        {error && <span className="text-sm" style={{ color: '#dc2626' }}>{error}</span>}
      </div>

      <div className="grid grid-cols-2 gap-5">
        <div className="col-span-2">
          <RevenueChart />
        </div>
        <FleetUtilization />
        <TopMotoRevenue />
        <BranchComparison />
        <BookingsByStatus />
        <div className="col-span-2">
          <CustomerRetention />
        </div>
      </div>
    </div>
  )
}
