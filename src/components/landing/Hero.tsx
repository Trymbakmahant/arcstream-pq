import { useQuery } from '@tanstack/react-query'
import { usePublicClient } from 'wagmi'
import { ArrowRight, ExternalLink, Fingerprint, ShieldCheck, Coins, Lock } from 'lucide-react'
import { motion } from 'framer-motion'
import { ARC_CHAIN_ID } from '@/config'
import { VAULT_ADDRESS, addressUrl, arcStreamVaultAbi } from '@/contracts/vault'
import { Link } from '@/lib/router'

function useEscrowCount() {
  const client = usePublicClient({ chainId: ARC_CHAIN_ID })
  return useQuery({
    queryKey: ['escrow-count', VAULT_ADDRESS],
    enabled: !!client && !!VAULT_ADDRESS,
    refetchInterval: 15000,
    queryFn: async () => {
      if (!client || !VAULT_ADDRESS) return 0n
      return client.readContract({ address: VAULT_ADDRESS, abi: arcStreamVaultAbi, functionName: 'escrowCount' })
    },
  })
}

const STATS = [
  {
    icon: Coins,
    title: 'USDC-native gas',
    body: 'Fees are paid in USDC on Arc, so there is no second token to buy or hold.',
  },
  {
    icon: Lock,
    title: 'Refund lock',
    body: 'Once a contractor submits proof, the employer cannot refund until that work is approved.',
  },
  {
    icon: Fingerprint,
    title: 'Post-quantum signature lock',
    body: 'Touch ID or Face ID unlocks an SLH-DSA key (FIPS 205). Arc verifies its signature before an employer can release or refund.',
  },
]

export function Hero() {
  const { data: count } = useEscrowCount()

  return (
    <section className="mx-auto max-w-6xl px-4 pb-16 pt-14 sm:px-6 sm:pt-20">
      <motion.div
        className="mx-auto max-w-3xl text-center"
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.45, ease: 'easeOut' }}
      >
        <span className="inline-flex min-h-9 items-center gap-2 rounded-full border border-brandSecondary bg-brandSecondary/30 px-4 text-xs font-semibold tracking-[0.04em] text-brandHighlight">
          <ShieldCheck className="size-4" />
          Quantum-resistant 2FA • Native USDC on Arc
        </span>

        <h1 className="display mt-6 text-balance text-4xl font-bold text-brandHighlight sm:text-6xl sm:leading-[1.05]">
          Pay for finished work, milestone by milestone.
        </h1>
        <p className="display mt-2 text-balance text-2xl font-medium text-brandHighlight/70 sm:text-3xl">
          With a post-quantum signature on every release.
        </p>

        <p className="mx-auto mt-6 max-w-2xl text-pretty text-base text-brandHighlight/80 sm:text-lg">
          A noncustodial USDC milestone escrow on Arc. Employer releases and refunds can require a post-quantum
          SLH-DSA signature, unlocked with Touch ID or Face ID and verified by Arc's native precompile.
        </p>

        <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
          <Link
            to="/dashboard"
            className="inline-flex min-h-12 items-center gap-2 rounded-xl bg-brandHighlight px-6 py-3 text-sm font-semibold text-brandMain transition-opacity hover:opacity-90"
          >
            Launch App
            <ArrowRight className="size-4" />
          </Link>
          {VAULT_ADDRESS && (
            <a
              href={addressUrl(VAULT_ADDRESS)}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex min-h-12 items-center gap-2 rounded-xl border border-brandHighlight/30 px-6 py-3 text-sm font-semibold text-brandHighlight transition-colors hover:bg-brandSecondary/30"
            >
              View Contract on Explorer
              <ExternalLink className="size-4" />
            </a>
          )}
        </div>

        <p className="mt-4 text-xs tabular-nums text-brandHighlight/70">
          Live on Arc Testnet
          {count !== undefined ? ` • ${count.toString()} ${count === 1n ? 'escrow' : 'escrows'} created` : ''}
        </p>
      </motion.div>

      <ul className="mt-14 grid gap-4 md:grid-cols-3">
        {STATS.map(({ icon: Icon, title, body }, i) => (
          <motion.li
            key={title}
            className="rounded-2xl border border-brandSecondary bg-brandSecondary/20 p-6"
            initial={{ opacity: 0, y: 12 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.4, delay: i * 0.08 }}
          >
            <span className="flex size-11 items-center justify-center rounded-xl bg-brandHighlight text-brandMain">
              <Icon className="size-5" />
            </span>
            <h3 className="display mt-4 text-lg font-bold text-brandHighlight">{title}</h3>
            <p className="mt-1 text-sm text-pretty text-brandHighlight/80">{body}</p>
          </motion.li>
        ))}
      </ul>
    </section>
  )
}
