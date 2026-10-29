import { slh_dsa_sha2_128s } from '@noble/post-quantum/slh-dsa.js'
import { bytesToHex, hexToBytes, type Hex } from 'viem'

/** Runs SLH-DSA-SHA2-128s key derivation and signing off the main thread. Secrets never leave this worker. */

interface Request {
  id: number
  op: 'derive' | 'sign'
  seed: Hex
  message?: Hex
}

const scope = self as unknown as {
  onmessage: ((event: MessageEvent<Request>) => void) | null
  postMessage: (message: unknown) => void
}

scope.onmessage = (event) => {
  const { id, op, seed, message } = event.data
  try {
    const { secretKey, publicKey } = slh_dsa_sha2_128s.keygen(hexToBytes(seed))
    if (op === 'derive') {
      scope.postMessage({ id, ok: true, result: { publicKey: bytesToHex(publicKey) } })
      return
    }
    if (!message) throw new Error('Missing message to sign.')
    const signature = slh_dsa_sha2_128s.sign(hexToBytes(message), secretKey)
    scope.postMessage({ id, ok: true, result: { publicKey: bytesToHex(publicKey), signature: bytesToHex(signature) } })
  } catch (error) {
    scope.postMessage({ id, ok: false, error: error instanceof Error ? error.message : 'Signing failed.' })
  }
}
