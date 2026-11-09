/**
 * Unit tests for API key resolution and caller authentication (keys.ts):
 * new-style secret keys, legacy service-role JWTs, internal callers.
 *
 *   node --test backend/supabase/functions/_shared/keys.test.ts
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  type EnvReader,
  internalCredentials,
  internalHeaders,
  isInternalCaller,
  isJwt,
  parseJwks,
  parseKeyDictionary,
  serverKey,
  timingSafeEqual,
  userIdFromClaims,
} from './keys.ts';

const LEGACY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJl';
const SECRET = 'sb_secret_0123456789abcdefABCDEF';
const ROTATED = 'sb_secret_rotated_9876543210';
const PUBLISHABLE = 'sb_publishable_0123456789abcdef';

function envOf(vars: Record<string, string>): EnvReader {
  return (name) => vars[name];
}

const newProject = envOf({
  SUPABASE_SECRET_KEYS: JSON.stringify({ default: SECRET, cron: ROTATED }),
  SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: PUBLISHABLE }),
});
const legacyProject = envOf({ SUPABASE_SERVICE_ROLE_KEY: LEGACY });

function headers(values: Record<string, string>): Headers {
  return new Headers(values);
}

describe('key resolution', () => {
  test('key dictionaries are parsed defensively', () => {
    assert.deepEqual(parseKeyDictionary(JSON.stringify({ default: ` ${SECRET} `, empty: '', n: 1 })), {
      default: SECRET,
    });
    assert.deepEqual(parseKeyDictionary('not json'), {});
    assert.deepEqual(parseKeyDictionary('["sb_secret_x"]'), {});
    assert.deepEqual(parseKeyDictionary(undefined), {});
  });

  test('the admin client prefers the default secret key', () => {
    assert.equal(serverKey(newProject), SECRET);
    const both = envOf({
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: SECRET }),
      SUPABASE_SERVICE_ROLE_KEY: LEGACY,
    });
    assert.equal(serverKey(both), SECRET);
  });

  test('legacy projects use the service-role key', () => {
    assert.equal(serverKey(legacyProject), LEGACY);
    assert.equal(serverKey(envOf({ SUPABASE_SECRET_KEYS: '', SUPABASE_SERVICE_ROLE_KEY: LEGACY })), LEGACY);
  });

  test('fallbacks: the local single secret key, then any named secret key', () => {
    assert.equal(serverKey(envOf({ SUPABASE_SECRET_KEY: SECRET })), SECRET);
    assert.equal(serverKey(envOf({ SUPABASE_SECRET_KEYS: JSON.stringify({ server: ROTATED }) })), ROTATED);
    assert.equal(serverKey(envOf({})), null);
  });

  test('every secret key and the legacy key are internal credentials, publishable keys are not', () => {
    const credentials = internalCredentials(envOf({
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: SECRET, cron: ROTATED }),
      SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: PUBLISHABLE }),
      SUPABASE_SERVICE_ROLE_KEY: LEGACY,
    }));
    assert.deepEqual(credentials.sort(), [LEGACY, ROTATED, SECRET].sort());
  });
});

describe('internal callers', () => {
  test('a secret key in the apikey header is accepted (pg_net, triggers)', () => {
    assert.equal(isInternalCaller(headers({ apikey: SECRET }), newProject), true);
    assert.equal(isInternalCaller(headers({ apikey: ROTATED }), newProject), true, 'any project secret key');
  });

  test('the legacy service-role key is accepted as apikey or bearer token', () => {
    assert.equal(isInternalCaller(headers({ Authorization: `Bearer ${LEGACY}` }), legacyProject), true);
    assert.equal(isInternalCaller(headers({ apikey: LEGACY }), legacyProject), true);
  });

  test('publishable keys, user tokens and wrong keys are rejected', () => {
    assert.equal(isInternalCaller(headers({ apikey: PUBLISHABLE }), newProject), false);
    assert.equal(
      isInternalCaller(headers({ apikey: PUBLISHABLE, Authorization: 'Bearer eyJ.user.token' }), newProject),
      false,
    );
    assert.equal(isInternalCaller(headers({ apikey: `${SECRET}x` }), newProject), false);
    assert.equal(isInternalCaller(headers({ apikey: SECRET.slice(0, -1) }), newProject), false);
    assert.equal(isInternalCaller(headers({}), newProject), false);
    assert.equal(isInternalCaller(headers({ apikey: SECRET }), envOf({})), false, 'no keys configured');
  });

  test('INTERNAL_FUNCTION_SECRET in x-internal-secret is accepted when configured', () => {
    const env = envOf({ INTERNAL_FUNCTION_SECRET: 'shared-secret' });
    assert.equal(isInternalCaller(headers({ 'x-internal-secret': 'shared-secret' }), env), true);
    assert.equal(isInternalCaller(headers({ 'x-internal-secret': 'other' }), env), false);
    assert.equal(
      isInternalCaller(headers({ 'x-internal-secret': '' }), envOf({ INTERNAL_FUNCTION_SECRET: '' })),
      false,
    );
  });

  test('function-to-function calls send a secret key only as apikey', () => {
    assert.deepEqual(internalHeaders(SECRET, envOf({})), { 'Content-Type': 'application/json', apikey: SECRET });
    const legacy = internalHeaders(LEGACY, envOf({ INTERNAL_FUNCTION_SECRET: 's' }));
    assert.equal(legacy['Authorization'], `Bearer ${LEGACY}`);
    assert.equal(legacy['apikey'], LEGACY);
    assert.equal(legacy['x-internal-secret'], 's');
    assert.equal(isInternalCaller(new Headers(internalHeaders(SECRET, envOf({}))), newProject), true, 'round trip');
  });

  test('JWT detection and constant-time comparison', () => {
    assert.equal(isJwt(LEGACY), true);
    assert.equal(isJwt(SECRET), false);
    assert.equal(isJwt('eyJ.only-two'), false);
    assert.equal(timingSafeEqual('abc', 'abc'), true);
    assert.equal(timingSafeEqual('abc', 'abd'), false);
    assert.equal(timingSafeEqual('abc', 'abcd'), false);
  });
});

describe('user tokens', () => {
  const user = '6f1d2a3b-4c5d-4e6f-8a9b-0c1d2e3f4a5b';

  test('only signed-in, non-anonymous users are accepted', () => {
    assert.equal(userIdFromClaims({ sub: user.toUpperCase(), role: 'authenticated', is_anonymous: false }), user);
    assert.equal(userIdFromClaims({ sub: user, role: 'anon' }), null);
    assert.equal(userIdFromClaims({ sub: user, role: 'service_role' }), null);
    assert.equal(userIdFromClaims({ sub: user, role: 'authenticated', is_anonymous: true }), null);
    assert.equal(userIdFromClaims({ sub: 'not-a-uuid', role: 'authenticated' }), null);
    assert.equal(userIdFromClaims(null), null);
  });

  test('SUPABASE_JWKS is accepted as a key set or a bare array', () => {
    const key = { kid: 'k1', kty: 'EC', crv: 'P-256', x: 'x', y: 'y' };
    const verifying = { ...key, key_ops: ['verify'] };
    assert.deepEqual(parseJwks(JSON.stringify({ keys: [key] })), { keys: [verifying] });
    assert.deepEqual(parseJwks(JSON.stringify([key, { nope: true }])), { keys: [verifying] });
    assert.deepEqual(
      parseJwks(JSON.stringify({ keys: [{ ...key, key_ops: ['verify'], alg: 'ES256' }] }))?.keys[0]?.alg,
      'ES256',
    );
    assert.equal(parseJwks('{"keys": []}'), null);
    assert.equal(parseJwks('garbage'), null);
    assert.equal(parseJwks(undefined), null);
  });
});
