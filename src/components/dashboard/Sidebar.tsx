import { useAccount } from 'wagmi'
import { ArrowLeft, ArrowUpRight, Droplets, Fingerprint, Home, Plus, ShieldCheck, X } from 'lucide-react'
import { ARC_CHAIN_ID } from '@/config'
import { VAULT_ADDRESS, addressUrl } from '@/contracts/vault'
import { usePasskey } from '@/hooks/usePasskey'
import { shortAddress } from '@/lib/money'
import { NETWORK } from '@/lib/network'
import { Link } from '@/lib/router'

interface Props {
  open: boolean
  onClose: () => void
  onCreate: () => void
  onFund: () => void
}

const itemBase =
  'flex min-h-11 w-full items-center gap-3 rounded-xl px-3 text-sm font-medium transition-all'

export function Sidebar({ open, onClose, onCreate, onFund }: Props) {
  const { address, isConnected, chainId } = useAccount()
  const passkey = usePasskey()
  const onArc = chainId === ARC_CHAIN_ID

  return (
    <>
      {open && (
        <button
          type="button"
          aria-label="Close menu"
          className="fixed inset-0 z-30 bg-black/80 backdrop-blur-sm lg:hidden"
          onClick={onClose}
        />
      )}
      <aside
        className={`fixed inset-y-0 left-0 z-40 flex w-64 flex-col border-r border-white/5 bg-[#0b0e14] p-4 transition-transform lg:translate-x-0 ${
          open ? 'translate-x-0' : '-translate-x-full'
        }`}
        aria-label="Sidebar"
      >
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-[#11151f] border border-neonLime/30 text-neonLime shadow-glow-lime">
              <ShieldCheck className="size-5" />
            </span>
            <div>
              <p className="display text-base font-bold leading-none text-white tracking-tight">ArcStream-PQ</p>
              <p className="mt-1 text-[0.6875rem] font-mono leading-tight text-zinc-400">USDC Milestone Escrows</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="flex size-9 items-center justify-center rounded-lg text-zinc-400 hover:text-white hover:bg-white/5 lg:hidden"
            aria-label="Close menu"
          >
            <X className="size-4" />
          </button>
        </div>

        <span className="neu-sunken mt-3 inline-flex w-fit items-center gap-2 rounded-full border border-white/5 px-3 py-1 font-mono text-[0.6875rem] font-medium text-zinc-300">
          <span className={`size-2 rounded-full ${!isConnected || onArc ? 'bg-neonLime shadow-[0_0_8px_#d4ff3f]' : 'bg-amber-400'}`} />
          {NETWORK.label} ({ARC_CHAIN_ID})
        </span>

        <nav className="mt-8 flex-1 space-y-6 overflow-y-auto" aria-label="Dashboard">
          <div>
            <p className="label-caps px-3 text-zinc-500">Core workspace</p>
            <div className="mt-2 space-y-1.5">
              <button
                type="button"
                className={`${itemBase} neu-card border border-neonLime/40 text-neonLime font-bold shadow-glow-lime`}
                aria-current="page"
                onClick={onClose}
              >
                <Home className="size-4" />
                Dashboard
              </button>
              <button
                type="button"
                className={`${itemBase} text-zinc-400 hover:text-white hover:bg-white/5`}
                onClick={() => {
                  onClose()
                  onCreate()
                }}
              >
                <Plus className="size-4 text-neonLime" />
                Create Escrow
              </button>
              <button
                type="button"
                className={`${itemBase} text-zinc-400 hover:text-white hover:bg-white/5`}
                onClick={() => {
                  onClose()
                  onFund()
                }}
              >
                <Droplets className="size-4 text-neonPink" />
                Fund with USDC
              </button>
            </div>
          </div>

          <div>
            <p className="label-caps px-3 text-zinc-500">Post-quantum security</p>
            <div className="mt-2">
              <button
                type="button"
                className={`${itemBase} justify-between text-zinc-300 hover:text-white hover:bg-white/5`}
                disabled={passkey.registered || !isConnected || passkey.busy || !passkey.supported}
                onClick={() => {
                  void passkey.register()
                }}
                title={
                  passkey.registered
                    ? 'Touch ID / Face ID key is set up for this wallet'
                    : 'Set up your Touch ID / Face ID key'
                }
              >
                <span className="flex items-center gap-3">
                  <Fingerprint className="size-4 text-neonPink" />
                  Passkey Hardware
                </span>
                <span
                  className={`rounded-md px-1.5 py-0.5 font-mono text-[0.625rem] font-bold ${
                    passkey.registered
                      ? 'bg-neonPink/20 text-neonPink border border-neonPink/50 shadow-glow-pink'
                      : 'border border-white/10 text-zinc-500'
                  }`}
                >
                  {passkey.registered ? 'PQ GATED' : 'SET UP'}
                </span>
              </button>
            </div>
          </div>

          <div>
            <p className="label-caps px-3 text-zinc-500">On-chain &amp; docs</p>
            <div className="mt-2 space-y-1">
              {VAULT_ADDRESS && (
                <a
                  href={addressUrl(VAULT_ADDRESS)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={`${itemBase} justify-between text-zinc-400 hover:text-white hover:bg-white/5`}
                >
                  <span className="flex items-center gap-3">
                    <ArrowUpRight className="size-4" />
                    Explorer
                  </span>
                </a>
              )}
              <Link to="/" className={`${itemBase} text-zinc-400 hover:text-white hover:bg-white/5`}>
                <ArrowLeft className="size-4" />
                Back to Landing Page
              </Link>
            </div>
          </div>
        </nav>

        {isConnected && address && (
          <div className="neu-sunken mt-4 flex items-center gap-3 rounded-xl border border-white/5 p-3">
            <span className="flex size-8 items-center justify-center rounded-full bg-neonLime/20 border border-neonLime/30 text-xs font-bold font-mono text-neonLime">
              {address.slice(2, 4).toUpperCase()}
            </span>
            <div className="min-w-0">
              <p className="flex items-center gap-1.5 truncate font-mono text-xs font-semibold text-zinc-200">
                {shortAddress(address)}
                <span className="size-1.5 shrink-0 rounded-full bg-neonLime shadow-[0_0_6px_#d4ff3f]" />
              </p>
              <p className="font-mono text-[0.625rem] text-zinc-500">{onArc ? NETWORK.label : 'Wrong network'}</p>
            </div>
          </div>
        )}
      </aside>
    </>
  )
}
