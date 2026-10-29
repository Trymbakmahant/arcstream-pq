import { useCallback, useEffect, useRef, useState } from 'react'
import { useAccount, useSignMessage } from 'wagmi'
import { toast } from 'sonner'
import { CreditCard, ExternalLink, Loader2, ShieldCheck } from 'lucide-react'
import type { OnrampIframeOptions, OnrampSession, OnrampWidget } from '@circle-fin/app-kit'
import { NETWORK } from '@/lib/network'
import {
  ONRAMP_ASSETS,
  ONRAMP_AUTH_HEADER,
  onrampAppUserId,
  onrampAuthMessage,
} from '@/lib/onrampAuth'

/** Arc's hosted fiat deposit page (real money, delivers USDC on Arc Mainnet). */
const HOSTED_ONRAMP_URL = 'https://portal.arc.io/deposit/fiat'

const widgetBaseUrl = import.meta.env.VITE_ONRAMP_WIDGET_BASE_URL as string | undefined

type Phase = 'idle' | 'signing' | 'loading' | 'open' | 'error'

/**
 * Buy USDC with a card or Apple Pay through Circle Onramp.
 * - Arc Mainnet: opens Arc's hosted page (real money, no server involved).
 * - Arc Testnet: embeds Circle's sandbox widget. A small server mints the session with the secret API key;
 *   the wallet signs a message first so a session can only be minted for the wallet that asked.
 */
export function OnrampSection({ onDone }: { onDone: () => void }) {
  if (NETWORK.isMainnet) return <HostedOnramp />
  return <SandboxOnramp onDone={onDone} />
}

function HostedOnramp() {
  return (
    <section className="mt-4 rounded-xl border border-brandHighlight/15 bg-white p-4">
      <h3 className="flex items-center gap-2 font-semibold text-brandHighlight">
        <CreditCard className="size-4" />
        Buy USDC with a card or Apple Pay
      </h3>
      <p className="mt-2 text-sm text-brandHighlight/80">
        Circle Onramp, hosted by Arc, delivers USDC on Arc to the wallet address you give it. Copy your address
        above and paste it there. This spends real money, and identity checks, fees and limits are shown before you
        pay.
      </p>
      <a
        href={HOSTED_ONRAMP_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="btn-primary mt-3 inline-flex min-h-11"
      >
        Buy USDC with card
        <ExternalLink className="size-4" />
      </a>
    </section>
  )
}

function SandboxOnramp({ onDone }: { onDone: () => void }) {
  const { address, isConnected } = useAccount()
  const { signMessageAsync } = useSignMessage()
  const [phase, setPhase] = useState<Phase>('idle')
  const [error, setError] = useState<string | null>(null)
  const [session, setSession] = useState<OnrampSession | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const kitRef = useRef<{ mountIframe: (options: OnrampIframeOptions) => OnrampWidget } | null>(null)

  const fail = useCallback((message: string) => {
    setError(message)
    setPhase('error')
    setSession(null)
  }, [])

  const start = useCallback(async () => {
    if (!address) return
    setError(null)
    try {
      setPhase('signing')
      const issuedAt = new Date().toISOString()
      const signature = await signMessageAsync({ message: onrampAuthMessage(address, issuedAt) })

      setPhase('loading')
      const { AppKit } = await import('@circle-fin/app-kit')
      const kit = new AppKit({ onramp: { widgetBaseUrl } })
      const minted = await kit.onramp.fetchSession({
        url: '/api/onramp/sessions',
        body: {
          appUserId: onrampAppUserId(address),
          destinationAddress: address,
          assets: ONRAMP_ASSETS,
        },
        headers: { [ONRAMP_AUTH_HEADER]: JSON.stringify({ address, issuedAt, signature }) },
      })
      kitRef.current = kit.onramp
      setSession(minted)
      setPhase('open')
    } catch (e) {
      const name = e instanceof Error ? e.name : ''
      if (name === 'UserRejectedRequestError' || (e instanceof Error && /reject|denied/i.test(e.message))) {
        setPhase('idle')
        return
      }
      fail('Could not start the card purchase. Check that the onramp service is running and try again.')
    }
  }, [address, signMessageAsync, fail])

  // Mount the widget once the session exists and the container is in the DOM; close it on cleanup.
  useEffect(() => {
    if (!session || !containerRef.current || !kitRef.current) return
    const widget = kitRef.current.mountIframe(
      mountOptions(session, containerRef.current, {
        onSubmitted: () => {
          toast.success('Purchase submitted. Test funds may take a moment.')
          onDone()
        },
        onSettled: onDone,
        onNotCompleted: (code) => {
          if (code === 'SESSION_TIMEOUT') fail('The session timed out. Start again.')
        },
        onInitError: () => fail('The card widget could not load. Try again.'),
      }),
    )
    return () => widget.close()
  }, [session, onDone, fail])

  return (
    <section className="mt-4 rounded-xl border border-brandHighlight/15 bg-white p-4">
      <h3 className="flex items-center gap-2 font-semibold text-brandHighlight">
        <CreditCard className="size-4" />
        Buy USDC with a card or Apple Pay (sandbox)
      </h3>
      <p className="mt-2 text-sm text-brandHighlight/80">
        This is Circle&apos;s test environment: no real money moves, and it may not send USDC to Arc Testnet. Use the
        Circle Faucet above when you just need test USDC. Real purchases are available on Arc Mainnet.
      </p>

      {phase !== 'open' && (
        <button
          type="button"
          className="btn-primary mt-3 min-h-11"
          disabled={!isConnected || phase === 'signing' || phase === 'loading' || !widgetBaseUrl}
          onClick={() => {
            void start()
          }}
        >
          {(phase === 'signing' || phase === 'loading') && <Loader2 className="size-4 animate-spin" />}
          {phase === 'signing' ? 'Sign in your wallet...' : phase === 'loading' ? 'Opening...' : 'Try the card flow'}
        </button>
      )}
      {!isConnected && <p className="mt-2 text-xs text-brandHighlight/70">Connect a wallet to try it.</p>}
      {isConnected && phase === 'idle' && (
        <p className="mt-2 flex items-start gap-1.5 text-xs text-brandHighlight/70">
          <ShieldCheck className="mt-0.5 size-3.5 shrink-0" />
          You sign a short message that proves this wallet is yours. It moves no funds.
        </p>
      )}
      {error && <p className="mt-2 text-sm font-medium text-brandHighlight">{error}</p>}

      {phase === 'open' && (
        <div className="mt-3">
          <div ref={containerRef} className="h-[640px] w-full overflow-hidden rounded-xl border border-brandSecondary" />
          <button
            type="button"
            className="btn-ghost mt-3 min-h-11"
            onClick={() => {
              setSession(null)
              setPhase('idle')
            }}
          >
            Close card flow
          </button>
        </div>
      )}
    </section>
  )
}

interface Handlers {
  onSubmitted: () => void
  onSettled: () => void
  onNotCompleted: (code: string) => void
  onInitError: () => void
}

function mountOptions(session: OnrampSession, container: HTMLElement, h: Handlers): OnrampIframeOptions {
  return {
    session,
    container,
    onDepositSubmitted: h.onSubmitted,
    onDepositSettled: h.onSettled,
    onDepositNotCompleted: ({ code }: { code: string }) => h.onNotCompleted(code),
    onInitializationError: h.onInitError,
  }
}
