/**
 * Supabase API keys and caller credentials, for both key systems:
 *
 * - New projects have no legacy JWT keys. The runtime injects
 *   `SUPABASE_SECRET_KEYS` and `SUPABASE_PUBLISHABLE_KEYS` as JSON
 *   dictionaries keyed by key name (`{"default": "sb_secret_…"}`) and
 *   `SUPABASE_JWKS`, the public keys that sign user JWTs.
 * - Older projects inject `SUPABASE_SERVICE_ROLE_KEY` (a service_role JWT).
 * - The local CLI may provide a single `SUPABASE_SECRET_KEY`.
 *
 * Secret keys are not JWTs: they travel in the `apikey` header, never as
 * `Authorization: Bearer` (that header is for user access tokens and legacy
 * JWT keys). Everything here is pure over an env reader so it can be tested
 * in Node without Deno.
 */

/** Reads an environment variable; `Deno.env.get` in the functions. */
export type EnvReader = (name: string) => string | undefined;

function nonEmpty(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

/** Constant-time string comparison (avoids leaking secrets through timing). */
export function timingSafeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  const length = Math.max(x.length, y.length);
  for (let i = 0; i < length; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** True for a compact JWS (`header.payload.signature`), i.e. a legacy JWT key or a user token. */
export function isJwt(value: string): boolean {
  return /^eyJ[\w-]*\.[\w-]+\.[\w-]+$/.test(value);
}

/** Parses a key dictionary such as `SUPABASE_SECRET_KEYS`; anything malformed yields `{}`. */
export function parseKeyDictionary(raw: string | null | undefined): Record<string, string> {
  const text = nonEmpty(raw);
  if (text === null) return {};
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return {};
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return {};
  const keys: Record<string, string> = {};
  for (const [name, value] of Object.entries(parsed as Record<string, unknown>)) {
    const key = typeof value === 'string' ? nonEmpty(value) : null;
    if (key !== null) keys[name] = key;
  }
  return keys;
}

/**
 * The key the server-side admin client uses: the `default` secret key, else
 * the legacy service-role key, else any other secret key.
 */
export function serverKey(env: EnvReader): string | null {
  const secrets = parseKeyDictionary(env('SUPABASE_SECRET_KEYS'));
  return secrets['default'] ?? nonEmpty(env('SUPABASE_SERVICE_ROLE_KEY')) ?? nonEmpty(env('SUPABASE_SECRET_KEY')) ??
    Object.values(secrets)[0] ?? null;
}

/**
 * Credentials an internal caller (pg_cron, database triggers, another
 * function) may present: any of the project's secret keys — so a key can be
 * rotated without downtime — or the legacy service-role key.
 */
export function internalCredentials(env: EnvReader): string[] {
  const credentials = new Set(Object.values(parseKeyDictionary(env('SUPABASE_SECRET_KEYS'))));
  for (const name of ['SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY']) {
    const key = nonEmpty(env(name));
    if (key !== null) credentials.add(key);
  }
  return [...credentials];
}

/** The token of an `Authorization: Bearer …` header, or null. */
export function bearerToken(headers: Headers): string | null {
  const match = /^Bearer\s+(\S+)\s*$/i.exec((headers.get('Authorization') ?? '').trim());
  return match ? (match[1] as string) : null;
}

/**
 * True when the request comes from an internal caller: a project secret key
 * (or the legacy service-role key) in the `apikey` header or as a bearer
 * token, or `INTERNAL_FUNCTION_SECRET` in `x-internal-secret`. A publishable
 * key or a user token never matches.
 */
export function isInternalCaller(headers: Headers, env: EnvReader): boolean {
  const presented = [nonEmpty(headers.get('apikey')), bearerToken(headers)].filter((v): v is string => v !== null);
  const credentials = internalCredentials(env);
  let match = false;
  for (const value of presented) {
    for (const credential of credentials) match = timingSafeEqual(value, credential) || match;
  }
  if (match) return true;
  const secret = nonEmpty(env('INTERNAL_FUNCTION_SECRET'));
  const sent = nonEmpty(headers.get('x-internal-secret'));
  return secret !== null && sent !== null && timingSafeEqual(sent, secret);
}

/**
 * Headers for calling another Edge Function of this project as an internal
 * caller. The key goes in `apikey`; a legacy JWT key is also sent as a bearer
 * token so it passes a gateway JWT check. `INTERNAL_FUNCTION_SECRET`, when
 * configured, is added as a second credential.
 */
export function internalHeaders(key: string, env: EnvReader): Record<string, string> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', apikey: key };
  if (isJwt(key)) headers['Authorization'] = `Bearer ${key}`;
  const secret = nonEmpty(env('INTERNAL_FUNCTION_SECRET'));
  if (secret !== null) headers['x-internal-secret'] = secret;
  return headers;
}

/** A public JSON Web Key as auth-js expects it (`key_ops` always present). */
export interface Jwk {
  kty: string;
  key_ops: string[];
  kid?: string;
  alg?: string;
  [parameter: string]: unknown;
}

/**
 * Parses `SUPABASE_JWKS` (`{"keys": [...]}` or a bare array) into public
 * verification keys; null when absent or malformed.
 */
export function parseJwks(raw: string | null | undefined): { keys: Jwk[] } | null {
  const text = nonEmpty(raw);
  if (text === null) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  const list = Array.isArray(parsed)
    ? parsed
    : typeof parsed === 'object' && parsed !== null && Array.isArray((parsed as { keys?: unknown }).keys)
    ? (parsed as { keys: unknown[] }).keys
    : null;
  if (list === null) return null;
  const keys: Jwk[] = [];
  for (const entry of list) {
    if (typeof entry !== 'object' || entry === null || typeof (entry as { kty?: unknown }).kty !== 'string') continue;
    const key = entry as Record<string, unknown> & { kty: string };
    const ops = Array.isArray(key['key_ops']) ? (key['key_ops'] as unknown[]).filter((o) => typeof o === 'string') : [];
    keys.push({ ...key, key_ops: ops.length > 0 ? (ops as string[]) : ['verify'] });
  }
  return keys.length > 0 ? { keys } : null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The user id in verified access-token claims, or null unless they describe
 * a signed-in, non-anonymous user (role `authenticated`, UUID `sub`).
 */
export function userIdFromClaims(claims: unknown): string | null {
  if (typeof claims !== 'object' || claims === null) return null;
  const c = claims as Record<string, unknown>;
  if (c['role'] !== 'authenticated' || c['is_anonymous'] === true) return null;
  const sub = c['sub'];
  return typeof sub === 'string' && UUID.test(sub) ? sub.toLowerCase() : null;
}
