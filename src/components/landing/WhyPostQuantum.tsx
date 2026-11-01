import { Check } from 'lucide-react'
import { addressUrl, VAULT_ADDRESS } from '@/contracts/vault'
import { NETWORK } from '@/lib/network'

const explorerHref = VAULT_ADDRESS ? addressUrl(VAULT_ADDRESS) : NETWORK.explorerUrl

export function WhyPostQuantum() {
  return (
    <section className="py-24 px-6 border-t border-white/5 relative" id="security">
      <div className="max-w-6xl mx-auto">
        <div className="text-center max-w-3xl mx-auto mb-16">
          <div className="inline-flex items-center gap-2 neu-inset px-3 py-1 rounded-full text-xs font-mono text-neonPink border border-neonPink/20 mb-3">
            <span className="size-2 rounded-full bg-neonPink shadow-glow-pink"></span>
            <span>Cryptographic Threat Modeling</span>
          </div>
          <h2 className="text-3xl sm:text-4xl font-extrabold text-white">Classical Web3 Escrow vs. ArcStream-PQ</h2>
          <p className="text-zinc-400 text-sm sm:text-base mt-2">
            Why single-signature ECDSA contracts fail enterprise standards in the post-quantum era.
          </p>
        </div>

        {/* Comparison Matrix Table in Neumorphic Panel */}
        <div className="neu-panel rounded-3xl p-6 sm:p-8 border border-white/5 overflow-x-auto">
          <table className="w-full text-left text-sm border-collapse min-w-[620px]">
            <thead>
              <tr className="border-b border-white/10 text-xs font-mono text-zinc-400">
                <th className="py-4 px-4 font-semibold uppercase tracking-wider">Security Vector</th>
                <th className="py-4 px-4 font-semibold uppercase tracking-wider text-zinc-400">Classical Escrows (ECDSA)</th>
                <th className="py-4 px-4 font-semibold uppercase tracking-wider text-neonLime font-bold">ArcStream-PQ Protocol</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5 font-medium text-xs sm:text-sm">
              <tr>
                <td className="py-4 px-4 text-white font-semibold">Quantum Resistance</td>
                <td className="py-4 px-4 text-rose-400/90 font-mono text-xs">
                  Vulnerable to Shor's polynomial-time attack
                </td>
                <td className="py-4 px-4 text-neonLime font-mono text-xs font-bold">
                  <span className="flex items-center gap-1.5">
                    <Check className="size-4 shrink-0 text-neonLime" />
                    Stateless SLH-DSA Hash Trees (FIPS 205)
                  </span>
                </td>
              </tr>
              <tr>
                <td className="py-4 px-4 text-white font-semibold">Authorization Factor</td>
                <td className="py-4 px-4 text-zinc-400">
                  Single Metamask private key (1-Factor)
                </td>
                <td className="py-4 px-4 text-white font-semibold">
                  <span className="flex items-center gap-1.5">
                    <Check className="size-4 shrink-0 text-neonLime" />
                    Passkey Biometrics + ECDSA Dual Authentication
                  </span>
                </td>
              </tr>
              <tr>
                <td className="py-4 px-4 text-white font-semibold">Client Ghosting Safeguard</td>
                <td className="py-4 px-4 text-rose-400/90 font-mono text-xs">
                  Employer can stall or cancel unilaterally
                </td>
                <td className="py-4 px-4 text-neonLime font-mono text-xs font-bold">
                  <span className="flex items-center gap-1.5">
                    <Check className="size-4 shrink-0 text-neonLime" />
                    Artifact Proof freezes refund; auto-payout timer
                  </span>
                </td>
              </tr>
              <tr>
                <td className="py-4 px-4 text-white font-semibold">Stolen Key Exploitation</td>
                <td className="py-4 px-4 text-rose-400/90 font-mono text-xs">
                  Attacker can drain funds instantly
                </td>
                <td className="py-4 px-4 text-neonLime font-mono text-xs font-bold">
                  <span className="flex items-center gap-1.5">
                    <Check className="size-4 shrink-0 text-neonLime" />
                    Physical Biometric hardware signature mandatory
                  </span>
                </td>
              </tr>
              <tr>
                <td className="py-4 px-4 text-white font-semibold">Fee Medium &amp; Friction</td>
                <td className="py-4 px-4 text-zinc-400">
                  Secondary gas tokens (ETH/SOL) with slippage
                </td>
                <td className="py-4 px-4 text-white font-semibold">
                  <span className="flex items-center gap-1.5">
                    <Check className="size-4 shrink-0 text-neonLime" />
                    Direct native Circle USDC gas on Arc L1
                  </span>
                </td>
              </tr>
            </tbody>
          </table>

          {/* Security Callout Footer */}
          <div className="mt-6 p-4 rounded-2xl neu-inset flex flex-wrap items-center justify-between gap-3 text-xs font-mono text-zinc-300">
            <div className="flex items-center gap-2.5">
              <span className="size-2 rounded-full bg-neonLime"></span>
              <span>
                Audited on {NETWORK.label} • Smart Contract verified at{' '}
                {VAULT_ADDRESS ? `${VAULT_ADDRESS.slice(0, 6)}...${VAULT_ADDRESS.slice(-4)}` : '0x4645...c0fd'}
              </span>
            </div>
            <a
              className="text-neonLime hover:underline inline-flex items-center gap-1"
              href={explorerHref}
              rel="noopener noreferrer"
              target="_blank"
            >
              Inspect Bytecode →
            </a>
          </div>
        </div>
      </div>
    </section>
  )
}
