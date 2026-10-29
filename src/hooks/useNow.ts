import { useEffect, useState } from 'react'

/** Current unix time in seconds, refreshed on an interval so countdowns stay current. */
export function useNow(intervalMs = 30_000): number {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000))
  useEffect(() => {
    const id = window.setInterval(() => setNow(Math.floor(Date.now() / 1000)), intervalMs)
    return () => window.clearInterval(id)
  }, [intervalMs])
  return now
}
