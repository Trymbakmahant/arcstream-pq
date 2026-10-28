import { Check, Info, Minus } from 'lucide-react'

const ROWS = [
  {
    topic: 'Who must authorize a release',
    classic: 'One wallet signature (ECDSA secp256k1).',
    pq: 'Wallet signature plus a hash-based one-time secret unlocked by Touch ID / Face ID.',
  },
  {
    topic: 'Quantum exposure',
    classic: 'A large quantum computer running Shor\u2019s algorithm could derive the private key from its public key.',
    pq: 'The release and refund secrets sit behind keccak256 Merkle commitments, which Shor\u2019s algorithm does not break.',
  },
  {
    topic: 'Employer refund after delivery',
    classic: 'The employer can usually pull funds back whenever they like.',
    pq: 'Blocked while submitted work awaits approval. Disputes go through a split both sides must accept.',
  },
  {
    topic: 'Secret reuse',
    classic: 'The same key signs everything, forever.',
    pq: 'Every secret is revealed once and never reused, one per milestone plus one for refund.',
  },
]

export function WhyPostQuantum() {
  return (
    <section id="security" className="mx-auto max-w-6xl scroll-mt-28 px-4 py-16 sm:px-6">
      <p className="label-caps text-brandHighlight/70">Why post-quantum?</p>
      <h2 className="display mt-2 max-w-2xl text-balance text-3xl font-bold text-brandHighlight sm:text-4xl">
        Classical escrows rely on one key. This one asks for a second factor.
      </h2>

      <div className="mt-10 overflow-x-auto rounded-2xl border border-brandSecondary">
        <table className="w-full min-w-[40rem] border-collapse text-left text-sm">
          <caption className="sr-only">Classical escrows compared with ArcStream-PQ</caption>
          <thead>
            <tr>
              <th scope="col" className="w-1/5 bg-brandSecondary/30 p-4 label-caps text-brandHighlight/70">
                &nbsp;
              </th>
              <th scope="col" className="w-2/5 bg-brandSecondary/30 p-4 font-semibold text-brandHighlight">
                Classical escrows (ECDSA secp256k1)
              </th>
              <th scope="col" className="w-2/5 bg-brandHighlight p-4 font-semibold text-brandMain">
                ArcStream-PQ
              </th>
            </tr>
          </thead>
          <tbody>
            {ROWS.map((row) => (
              <tr key={row.topic} className="border-t border-brandSecondary/70 align-top">
                <th scope="row" className="p-4 font-semibold text-brandHighlight">
                  {row.topic}
                </th>
                <td className="p-4 text-brandHighlight/80">
                  <span className="flex gap-2">
                    <Minus className="mt-0.5 size-4 shrink-0 text-brandHighlight/50" />
                    {row.classic}
                  </span>
                </td>
                <td className="bg-brandSecondary/20 p-4 text-brandHighlight">
                  <span className="flex gap-2">
                    <Check className="mt-0.5 size-4 shrink-0" />
                    {row.pq}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="mt-6 flex gap-3 rounded-2xl border border-brandSecondary bg-brandSecondary/20 p-5 text-sm text-brandHighlight">
        <Info className="mt-0.5 size-5 shrink-0" />
        <p className="text-pretty">
          <strong>What this does not do.</strong> Your wallet key is still a standard key, and the passkey itself
          is not post-quantum. A stolen wallet key could approve milestones (which pays the contractor) but cannot
          release or refund a protected escrow. ArcStream-PQ runs on Arc Testnet and has not had an independent
          audit.
        </p>
      </div>
    </section>
  )
}
