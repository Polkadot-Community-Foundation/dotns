import { createPublicClient, http, namehash, hexToBytes, zeroAddress } from 'viem';

export interface Env {
  REGISTRY: string;
  RESOLVER: string;
  GATEWAY_URL: string;
  RPC_URL: string;
}

const alphabet32 = 'abcdefghijklmnopqrstuvwxyz234567';
const alphabet58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

const REGISTRY_ABI = [
  {
    inputs: [{ name: 'node', type: 'bytes32' }],
    name: 'resolver',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

const RESOLVER_ABI = [
  {
    inputs: [{ name: 'node', type: 'bytes32' }],
    name: 'contenthash',
    outputs: [{ name: '', type: 'bytes' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      let reqPath = url.pathname;
      let host = request.headers.get('host') || url.hostname;
      let nameFromPath = '';

      if (host.includes('localhost') || host === 'paritytech.io') {
        const parts = reqPath.split('/').filter(Boolean);
        if (parts.length === 0) {
          return new Response('Usage: http://localhost:{PORT}/<name>.dot', { status: 400 });
        }
        nameFromPath = parts[0];
        host = `${nameFromPath}.paseo-dotns.paritytech.io`;
        reqPath = '/' + parts.slice(1).join('/');
      }

      if (host === 'paseo-dotns.paritytech.io') {
        const parts = reqPath.split('/').filter(Boolean);
        if (parts.length === 0) {
          return new Response(
            'Usage: https://paseo-dotns.paritytech.io/<name>.dot or https://<name>.dot.paseo-dotns.paritytech.io/',
            { status: 400 }
          );
        }
        nameFromPath = parts[0];
        host = `${nameFromPath}.paseo-dotns.paritytech.io`;
        reqPath = '/' + parts.slice(1).join('/');
      }

      if (!host.endsWith('.paseo-dotns.paritytech.io')) {
        return new Response(`Invalid domain: ${host}`, { status: 400 });
      }

      const name = host.replace('.paseo-dotns.paritytech.io', '');

      if (!name.endsWith('.dot')) {
        return new Response(`Invalid DotNS name: ${name} (must end with .dot)`, { status: 400 });
      }

      const node = namehash(name);

      const client = createPublicClient({
        transport: http(env.RPC_URL),
      });

      const resolver = await client.readContract({
        address: env.REGISTRY as `0x${string}`,
        abi: REGISTRY_ABI,
        functionName: 'resolver',
        args: [node],
      });

      if (!resolver || resolver === zeroAddress) {
        return new Response(`No resolver set for ${name}`, { status: 404 });
      }

      const rawContenthash = await client.readContract({
        address: resolver as `0x${string}`,
        abi: RESOLVER_ABI,
        functionName: 'contenthash',
        args: [node],
      });

      if (!rawContenthash || rawContenthash === '0x') {
        return new Response(`No contenthash found for ${name}`, { status: 404 });
      }

      const decoded = decodeContentHash(hexToBytes(rawContenthash));
      if (!decoded) return new Response('Unsupported contenthash', { status: 400 });

      const base = `${env.GATEWAY_URL}${decoded}`;
      const fileUrl = `${base}${reqPath}`;

      const response = await fetch(fileUrl);

      if (response.ok) {
        return handleResponse(response, base, nameFromPath);
      }

      const indexResponse = await fetch(`${base}/index.html/`);
      if (indexResponse.ok) {
        return handleResponse(indexResponse, base, nameFromPath);
      }

      return indexResponse;
    } catch (e) {
      const error = e as Error;
      return new Response(`Error: ${error.message}`, { status: 500 });
    }
  },
};

async function handleResponse(
  response: Response,
  ipfsBase: string,
  nameFromPath: string
): Promise<Response> {
  const contentType = response.headers.get('content-type') || '';

  if (contentType.includes('text/html')) {
    const html = await response.text();
    const rewritten = rewriteHTML(html, ipfsBase, nameFromPath);

    return new Response(rewritten, {
      status: response.status,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'access-control-allow-origin': '*',
      },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: response.headers,
  });
}

function rewriteHTML(html: string, ipfsBase: string, nameFromPath: string): string {
  let rewritten = html;

  rewritten = rewritten.replace(/((?:src|href)=["'])\/(?!\/)/g, `$1${ipfsBase}/`);

  if (nameFromPath) {
    const baseTag = `<base href="${ipfsBase}/">`;
    rewritten = rewritten.replace(/<head>/i, `<head>${baseTag}`);
  }

  return rewritten;
}

function decodeContentHash(bytes: Uint8Array): string | null {
  if (bytes[0] === 0xe3 && bytes[1] === 0x01) return base58Encode(bytes.slice(2));
  if (bytes[0] === 0x01 && bytes[1] === 0x55 && bytes[2] === 0x12)
    return base32Encode(bytes.slice(2));
  return null;
}

function base58Encode(buffer: Uint8Array): string {
  let digits = [0];
  for (let i = 0; i < buffer.length; i++) {
    let carry = buffer[i] ?? 0;
    for (let j = 0; j < digits.length; j++) {
      carry += (digits[j] ?? 0) << 8;
      digits[j] = carry % 58;
      carry = (carry / 58) | 0;
    }
    while (carry > 0) {
      digits.push(carry % 58);
      carry = (carry / 58) | 0;
    }
  }
  let out = '';
  for (let i = 0; i < buffer.length && buffer[i] === 0; i++) out += '1';
  for (let i = digits.length - 1; i >= 0; i--) out += alphabet58[digits[i] ?? 0];
  return out;
}

function base32Encode(buffer: Uint8Array): string {
  let bits = 0,
    value = 0,
    out = '';
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += alphabet32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += alphabet32[(value << (5 - bits)) & 31];
  return out;
}
