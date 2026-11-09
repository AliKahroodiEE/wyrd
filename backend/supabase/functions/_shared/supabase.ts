/**
 * Server-side Supabase client with the project's secret key (the
 * `service_role` Postgres role). It bypasses RLS, so it is used only after
 * the caller has been authenticated and authorised in code, and it never
 * leaves the Edge Function runtime.
 *
 * The key is the `default` entry of SUPABASE_SECRET_KEYS on projects with the
 * new API keys, or the legacy SUPABASE_SERVICE_ROLE_KEY (see keys.ts).
 */
import { createClient, type SupabaseClient } from './deps.ts';
import { HttpError } from './http.ts';
import { type EnvReader, serverKey as resolveServerKey } from './keys.ts';

const env: EnvReader = (name) => Deno.env.get(name);

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined || value.trim() === '') {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

export function optionalEnv(name: string): string | null {
  const value = Deno.env.get(name);
  return value === undefined || value.trim() === '' ? null : value.trim();
}

/** The project's server key, or null when the runtime provides none. */
export function serverKey(): string | null {
  return resolveServerKey(env);
}

let admin: SupabaseClient | null = null;

export function adminClient(): SupabaseClient {
  if (admin === null) {
    const key = serverKey();
    if (key === null) {
      throw new Error('Missing server key: SUPABASE_SECRET_KEYS (default) or SUPABASE_SERVICE_ROLE_KEY');
    }
    admin = createClient(requireEnv('SUPABASE_URL'), key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
  }
  return admin;
}

/**
 * SQLSTATEs raised deliberately by the RPCs (see the migrations) and the
 * HTTP status they map to. Anything else is an internal error whose details
 * are not returned to the caller.
 */
const SQLSTATE_TO_HTTP: Record<string, [number, string]> = {
  P0002: [404, 'not_found'],
  '22023': [400, 'invalid_request'],
  '42501': [403, 'forbidden'],
  '54000': [429, 'limit_reached'],
};

/** Calls a Postgres function and throws on error. */
export async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await adminClient().rpc(name, args);
  if (error) {
    const mapped = SQLSTATE_TO_HTTP[error.code];
    if (mapped) throw new HttpError(mapped[0], error.hint || mapped[1], error.message);
    throw new Error(`${name} failed (${error.code}): ${error.message}`);
  }
  return data as T;
}
