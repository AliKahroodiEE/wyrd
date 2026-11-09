/**
 * Caller authentication for Edge Functions.
 *
 * - End users present their Supabase access token (JWT) as a bearer token.
 *   It is verified with `auth.getClaims`: locally against the project's
 *   signing keys (`SUPABASE_JWKS`, else the cached JWKS endpoint) on projects
 *   with asymmetric keys, through the Auth server on legacy HS256 projects.
 *   No JWT secret is configured anywhere. A token stays valid until it
 *   expires (`jwt_expiry`, one hour) even after sign-out.
 * - Internal callers (pg_cron and database triggers via pg_net, other
 *   functions) present a project secret key in the `apikey` header (legacy
 *   projects: the service-role key, also accepted as a bearer token), or
 *   INTERNAL_FUNCTION_SECRET in `x-internal-secret`. Functions they call are
 *   deployed with verify_jwt = false, so this check is the only one.
 */
import { HttpError } from './http.ts';
import { bearerToken, type EnvReader, isInternalCaller, parseJwks, userIdFromClaims } from './keys.ts';
import { adminClient, optionalEnv } from './supabase.ts';

export { timingSafeEqual } from './keys.ts';

export type Caller = { kind: 'user'; userId: string } | { kind: 'service' };

const env: EnvReader = (name) => Deno.env.get(name);

export function isServiceRequest(req: Request): boolean {
  return isInternalCaller(req.headers, env);
}

type ClaimsResult = Awaited<ReturnType<ReturnType<typeof adminClient>['auth']['getClaims']>>;

/** getClaims with the injected key set; on a key it cannot use, retried with the JWKS endpoint. */
async function claimsOf(token: string): Promise<ClaimsResult | null> {
  const jwks = parseJwks(optionalEnv('SUPABASE_JWKS'));
  try {
    return await adminClient().auth.getClaims(token, jwks ? { jwks } : undefined);
  } catch {
    if (jwks === null) return null; // a token the library cannot parse (e.g. an unsupported alg)
  }
  try {
    return await adminClient().auth.getClaims(token);
  } catch {
    return null;
  }
}

async function verifyUser(token: string): Promise<string | null> {
  const verified = await claimsOf(token);
  if (verified === null) return null;
  const { data, error } = verified;
  if (error?.name === 'AuthRetryableFetchError') {
    throw new HttpError(503, 'auth_unavailable', 'The session could not be verified right now.');
  }
  if (error || !data) return null;
  return userIdFromClaims(data.claims);
}

export async function authenticate(req: Request, options: { allowService: boolean }): Promise<Caller> {
  if (options.allowService && isServiceRequest(req)) return { kind: 'service' };
  const token = bearerToken(req.headers);
  if (token === null) throw new HttpError(401, 'unauthorized', 'Missing bearer token.');
  const userId = await verifyUser(token);
  if (userId === null) throw new HttpError(401, 'unauthorized', 'Invalid or expired session.');
  return { kind: 'user', userId };
}

export async function requireUser(req: Request): Promise<string> {
  const caller = await authenticate(req, { allowService: false });
  if (caller.kind !== 'user') throw new HttpError(401, 'unauthorized');
  return caller.userId;
}

export function requireService(req: Request): void {
  if (!isServiceRequest(req)) throw new HttpError(401, 'unauthorized', 'Internal endpoint.');
}
