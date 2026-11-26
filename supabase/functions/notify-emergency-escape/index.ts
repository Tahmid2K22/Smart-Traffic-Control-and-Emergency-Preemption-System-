// Supabase Edge Function (Free tier — no Firebase Blaze plan required).
// Sends FCM HTTP v1 push notifications to assigned traffic police officers
// when an ambulance triggers an emergency escape.
//
// Required Supabase secrets:
//   - FIREBASE_SERVICE_ACCOUNT: JSON string from Firebase Console ->
//     Project Settings -> Service Accounts -> Generate new private key
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-provided by Supabase.)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface EscapePushPayload {
  alertId?: string;
  intersectionId?: string;
  intersectionName?: string;
  driverName?: string;
  approachDirection?: string;
  distanceMeters?: number | null;
  estimatedArrivalMinutes?: number | null;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = base64UrlEncode(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!tokenRes.ok) {
    throw new Error(`OAuth token exchange failed: ${tokenRes.status}`);
  }
  const tokenJson = await tokenRes.json();
  return tokenJson.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const payload = (await req.json()) as EscapePushPayload;
    const intersectionId = (payload.intersectionId ?? '').trim();
    const intersectionName = (payload.intersectionName ?? '').trim();
    if (!intersectionId && !intersectionName) {
      return new Response(JSON.stringify({ sent: 0, reason: 'missing_intersection' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const saRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '';
    if (!saRaw) {
      return new Response(JSON.stringify({ sent: 0, reason: 'missing_firebase_service_account' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const serviceAccount = JSON.parse(saRaw) as ServiceAccount;

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const supabase = createClient(supabaseUrl, serviceKey);

    const { data: officers, error } = await supabase
      .from('users')
      .select('assigned_intersection_id, assigned_intersection, fcm_tokens')
      .eq('role', 'traffic_police')
      .eq('is_verified', true)
      .eq('is_active', true);

    if (error) {
      throw error;
    }

    const tokens = new Set<string>();
    for (const officer of officers ?? []) {
      const assignedId = typeof officer.assigned_intersection_id === 'string'
        ? officer.assigned_intersection_id.trim()
        : '';
      const assignedName = typeof officer.assigned_intersection === 'string'
        ? officer.assigned_intersection.trim().toLowerCase()
        : '';
      const matches =
        (intersectionId !== '' && assignedId === intersectionId) ||
        (intersectionName !== '' &&
          assignedName !== '' &&
          assignedName === intersectionName.toLowerCase());
      if (!matches) continue;
      if (officer.fcm_tokens && typeof officer.fcm_tokens === 'object') {
        for (const token of Object.keys(officer.fcm_tokens as Record<string, unknown>)) {
          if (token) tokens.add(token);
        }
      }
    }

    if (tokens.size === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: 'no_tokens' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const driverName = payload.driverName?.trim() || 'An ambulance driver';
    const eta = typeof payload.estimatedArrivalMinutes === 'number'
      ? Math.round(payload.estimatedArrivalMinutes)
      : null;
    const distance = typeof payload.distanceMeters === 'number'
      ? Math.round(payload.distanceMeters)
      : null;
    const etaText = eta !== null
      ? ` ~${eta} min away`
      : distance !== null
      ? ` ${distance} m away`
      : '';
    const direction = payload.approachDirection?.trim()
      ? ` (${payload.approachDirection.trim()} approach)`
      : '';

    const accessToken = await getGoogleAccessToken(serviceAccount);
    const fcmEndpoint =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    let sent = 0;
    for (const token of tokens) {
      const res = await fetch(fcmEndpoint, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: '🚑 Emergency escape request',
              body: `${driverName} needs a green at ${intersectionName || intersectionId}${direction}${etaText}.`,
            },
            data: {
              type: 'EMERGENCY_ESCAPE',
              alertId: payload.alertId ?? '',
              intersectionId,
              intersectionName,
            },
            android: {
              priority: 'HIGH',
            },
          },
        }),
      });
      if (res.ok) sent++;
    }

    return new Response(JSON.stringify({ sent, total: tokens.size }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
