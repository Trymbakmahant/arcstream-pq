import Dashboard from '@/pages/Dashboard'
import Landing from '@/pages/Landing'
import { usePath } from '@/lib/router'

export default function App() {
  const path = usePath()
  return path === '/dashboard' ? <Dashboard /> : <Landing />
}
