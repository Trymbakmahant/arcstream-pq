import { useState, useSyncExternalStore } from 'react'
import { useAccount } from 'wagmi'
import { toast } from 'sonner'
import {
  BiometricError,
  isPasskeySupported,
  passkeyFingerprint,
  passkeySnapshot,
  registerBiometricPQKey,
  subscribePasskey,
} from '@/lib/webauthn'

/** Touch ID / Face ID key for the connected wallet, stored in this browser. */
export function usePasskey() {
  const { address } = useAccount()
  const credentialId = useSyncExternalStore(
    subscribePasskey,
    () => passkeySnapshot(address),
    () => '',
  )
  const [busy, setBusy] = useState(false)

  const register = async (): Promise<boolean> => {
    if (!address) {
      toast('Connect your wallet first.')
      return false
    }
    setBusy(true)
    try {
      const { prf } = await registerBiometricPQKey(address)
      toast.success(
        prf
          ? 'Touch ID / Face ID key created.'
          : 'Touch ID / Face ID key created. This browser cannot derive secrets from the passkey, so a device-bound secret is kept in this browser instead.',
      )
      return true
    } catch (error) {
      toast.error(error instanceof BiometricError ? error.message : 'Could not create the Touch ID / Face ID key.')
      return false
    } finally {
      setBusy(false)
    }
  }

  return {
    supported: isPasskeySupported(),
    registered: credentialId !== '',
    fingerprint: address && credentialId ? passkeyFingerprint(address) : null,
    busy,
    register,
  }
}
