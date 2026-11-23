/**
 * Cloud Functions for the ambulance dashboard.
 *
 *  - placesAutocomplete / placeDetails / nearbyPlaces:
 *      Google Places proxy callables (secrets-based, App Check enforced).
 *  - notifyEmergencyEscape:
 *      Firestore trigger. When an EMERGENCY_ESCAPE alert is created it sends
 *      an FCM push to every verified, active traffic police officer assigned
 *      to the target intersection (matched by assignedIntersectionId or by
 *      the assigned intersection name). Tokens live on
 *      `users/{uid}.fcmTokens` and are registered by the officer app
 *      (PushNotificationService).
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

initializeApp();

const googlePlacesApiKey = defineSecret('GOOGLE_PLACES_API_KEY');
const placesBaseUrl = 'https://places.googleapis.com/v1';
const maxRadiusMeters = 30000;

function requireRequest(request: any) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign-in is required.');
  }
  if (!request.app) {
    throw new HttpsError(
      'failed-precondition',
      'App verification is required.'
    );
  }
  return request.data ?? {};
}

function coordinates(data: any) {
  const latitude = Number(data.latitude);
  const longitude = Number(data.longitude);
  if (
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    throw new HttpsError('invalid-argument', 'Valid latitude and longitude are required.');
  }
  return { latitude, longitude };
}

function placeType(value: any) {
  if (value !== 'hospital' && value !== 'pharmacy') {
    throw new HttpsError('invalid-argument', 'Unsupported place type.');
  }
  return value;
}

async function placesRequest(path: string, body: unknown, fieldMask: string) {
  const response = await fetch(`${placesBaseUrl}/${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': googlePlacesApiKey.value(),
      'X-Goog-FieldMask': fieldMask,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    throw new HttpsError('internal', `Places request failed with status ${response.status}.`);
  }
  return (await response.json());
}

export const placesAutocomplete = onCall(
  { region: 'us-central1', enforceAppCheck: true, secrets: [googlePlacesApiKey] },
  async (request) => {
    const data = requireRequest(request);
    const input = typeof data.input === 'string' ? data.input.trim() : '';
    if (input.length < 2 || input.length > 120) {
      throw new HttpsError('invalid-argument', 'Search text must be 2 to 120 characters.');
    }
    const center = coordinates(data);
    const result = await placesRequest(
      'places:autocomplete',
      {
        input,
        includedRegionCodes: ['bd'],
        locationBias: { circle: { center, radius: maxRadiusMeters } },
      },
      'suggestions.placePrediction.placeId,suggestions.placePrediction.text.text'
    );
    return result;
  }
);

export const placeDetails = onCall(
  { region: 'us-central1', enforceAppCheck: true, secrets: [googlePlacesApiKey] },
  async (request) => {
    const data = requireRequest(request);
    const placeId = typeof data.placeId === 'string' ? data.placeId.trim() : '';
    if (!placeId || placeId.length > 200) {
      throw new HttpsError('invalid-argument', 'A valid place ID is required.');
    }
    const response = await fetch(
      `${placesBaseUrl}/places/${encodeURIComponent(placeId)}`,
      {
        headers: {
          'X-Goog-Api-Key': googlePlacesApiKey.value(),
          'X-Goog-FieldMask':
            'id,displayName,formattedAddress,location,currentOpeningHours,types',
        },
      }
    );
    if (!response.ok) {
      throw new HttpsError('internal', `Place details request failed with status ${response.status}.`);
    }
    return (await response.json());
  }
);

export const nearbyPlaces = onCall(
  { region: 'us-central1', enforceAppCheck: true, secrets: [googlePlacesApiKey] },
  async (request) => {
    const data = requireRequest(request);
    const center = coordinates(data);
    const type = placeType(data.type);
    const result = await placesRequest(
      'places:searchNearby',
      {
        includedTypes: [type],
        maxResultCount: 20,
        rankPreference: 'DISTANCE',
        locationRestriction: { circle: { center, radius: maxRadiusMeters } },
      },
      'places.id,places.displayName,places.formattedAddress,places.location,places.currentOpeningHours,places.types'
    );
    return result;
  }
);

// ── Emergency escape push ───────────────────────────────────────────────────

interface EscapeAlert {
  type?: unknown;
  officerId?: unknown;
  driverName?: unknown;
  intersectionId?: unknown;
  intersectionName?: unknown;
  intersection?: unknown;
  distanceMeters?: unknown;
  estimatedArrivalMinutes?: unknown;
  approachDirection?: unknown;
}

function tokenMapKeys(value: unknown): string[] {
  if (!value || typeof value !== 'object') return [];
  return Object.keys(value as Record<string, unknown>);
}

export const notifyEmergencyEscape = onDocumentCreated(
  'emergency_alerts/{alertId}',
  async (event) => {
    const alert = (event.data?.data() ?? {}) as EscapeAlert;
    if (alert.type !== 'EMERGENCY_ESCAPE') return;

    const intersectionId =
      typeof alert.intersectionId === 'string' ? alert.intersectionId : '';
    const intersectionName =
      typeof alert.intersectionName === 'string'
        ? alert.intersectionName
        : typeof alert.intersection === 'string'
          ? alert.intersection
          : '';
    // Only the PRIMARY escape record (officerId '') triggers pushes — each
    // per-officer duplicate doc would otherwise fan out again per officer.
    if (typeof alert.officerId === 'string' && alert.officerId !== '') return;
    if (!intersectionId && !intersectionName) return;

    const supabaseUrl = process.env.SUPABASE_URL ?? '';
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
    let officers: Array<{ assignedIntersectionId?: unknown; assignedIntersection?: unknown; fcmTokens?: unknown }> = [];
    if (supabaseUrl && serviceKey) {
      try {
        const res = await fetch(`${supabaseUrl}/rest/v1/users?select=assigned_intersection_id,assigned_intersection,fcm_tokens&role=eq.traffic_police&is_verified=eq.true&is_active=eq.true`, {
          headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
        });
        if (res.ok) {
          officers = await res.json();
        }
      } catch (error) {
        console.error('Supabase officer lookup failed:', error);
      }
    }
    const tokens: string[] = [];
    for (const data of officers) {
      const assignedId =
        typeof data.assignedIntersectionId === 'string'
          ? data.assignedIntersectionId
          : '';
      const assignedName =
        typeof data.assignedIntersection === 'string'
          ? data.assignedIntersection.trim().toLowerCase()
          : '';
      const matches =
        (intersectionId !== '' && assignedId === intersectionId) ||
        (intersectionName !== '' &&
          assignedName !== '' &&
          assignedName === intersectionName.toLowerCase());
      if (!matches) continue;
      tokens.push(...tokenMapKeys(data.fcmTokens));
    }
    if (tokens.length === 0) return;

    const driverName =
      typeof alert.driverName === 'string' && alert.driverName.length > 0
        ? alert.driverName
        : 'An ambulance driver';
    const distance =
      typeof alert.distanceMeters === 'number'
        ? Math.round(alert.distanceMeters)
        : null;
    const eta =
      typeof alert.estimatedArrivalMinutes === 'number'
        ? Math.round(alert.estimatedArrivalMinutes)
        : null;
    const etaText =
      eta !== null ? ` ~${eta} min away` : distance !== null ? ` ${distance} m away` : '';
    const direction =
      typeof alert.approachDirection === 'string' && alert.approachDirection
        ? ` (${alert.approachDirection} approach)`
        : '';

    const message = {
      notification: {
        title: '🚑 Emergency escape request',
        body: `${driverName} needs a green at ${intersectionName}${direction}${etaText}.`,
      },
      data: {
        type: 'EMERGENCY_ESCAPE',
        alertId: event.params.alertId,
        intersectionId,
        intersectionName,
      },
      tokens,
    };

    try {
      const response = await getMessaging().sendEachForMulticast(message);
      if (response.failureCount > 0) {
        response.responses.forEach((result, index) => {
          if (!result.success) {
            console.error(
              `FCM push failed for token ${index}: ${result.error?.code ?? ''} ${result.error?.message ?? ''}`
            );
          }
        });
      }
    } catch (error) {
      console.error('FCM push failed:', error);
    }

    // Stamp the primary record (this trigger's doc IS the primary) so the
    // driver / dashboards can see that pushes were attempted.
    await getFirestore().collection('emergency_alerts').doc(event.params.alertId).update({
      pushSentAt: FieldValue.serverTimestamp(),
      pushRecipientCount: tokens.length,
    });
  }
);
