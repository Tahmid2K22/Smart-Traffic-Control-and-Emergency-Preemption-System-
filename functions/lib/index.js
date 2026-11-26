"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyEmergencyEscape = exports.nearbyPlaces = exports.placeDetails = exports.placesAutocomplete = void 0;
/** Cloud Functions: Places proxies + emergency-escape FCM push. */
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const messaging_1 = require("firebase-admin/messaging");
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
const firestore_2 = require("firebase-functions/v2/firestore");
(0, app_1.initializeApp)();
const googlePlacesApiKey = (0, params_1.defineSecret)('GOOGLE_PLACES_API_KEY');
const supabaseUrlParam = (0, params_1.defineString)('SUPABASE_URL');
const supabaseServiceRoleKey = (0, params_1.defineSecret)('SUPABASE_SERVICE_ROLE_KEY');
const placesBaseUrl = 'https://places.googleapis.com/v1';
const maxRadiusMeters = 30000;
function requireRequest(request) {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Sign-in is required.');
    }
    if (!request.app) {
        throw new https_1.HttpsError('failed-precondition', 'App verification is required.');
    }
    return request.data ?? {};
}
function coordinates(data) {
    const latitude = Number(data.latitude);
    const longitude = Number(data.longitude);
    if (!Number.isFinite(latitude) ||
        latitude < -90 ||
        latitude > 90 ||
        !Number.isFinite(longitude) ||
        longitude < -180 ||
        longitude > 180) {
        throw new https_1.HttpsError('invalid-argument', 'Valid latitude and longitude are required.');
    }
    return { latitude, longitude };
}
function placeType(value) {
    if (value !== 'hospital' && value !== 'pharmacy') {
        throw new https_1.HttpsError('invalid-argument', 'Unsupported place type.');
    }
    return value;
}
async function placesRequest(path, body, fieldMask) {
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
        throw new https_1.HttpsError('internal', `Places request failed with status ${response.status}.`);
    }
    return (await response.json());
}
exports.placesAutocomplete = (0, https_1.onCall)({ region: 'us-central1', enforceAppCheck: true, secrets: [googlePlacesApiKey] }, async (request) => {
    const data = requireRequest(request);
    const input = typeof data.input === 'string' ? data.input.trim() : '';
    if (input.length < 2 || input.length > 120) {
        throw new https_1.HttpsError('invalid-argument', 'Search text must be 2 to 120 characters.');
    }
    const center = coordinates(data);
    const result = await placesRequest('places:autocomplete', {
        input,
        includedRegionCodes: ['bd'],
        locationBias: { circle: { center, radius: maxRadiusMeters } },
    }, 'suggestions.placePrediction.placeId,suggestions.placePrediction.text.text');
    return result;
});
exports.placeDetails = (0, https_1.onCall)({ region: 'us-central1', enforceAppCheck: true, secrets: [googlePlacesApiKey] }, async (request) => {
    const data = requireRequest(request);
    const placeId = typeof data.placeId === 'string' ? data.placeId.trim() : '';
    if (!placeId || placeId.length > 200) {
        throw new https_1.HttpsError('invalid-argument', 'A valid place ID is required.');
    }
    const response = await fetch(`${placesBaseUrl}/places/${encodeURIComponent(placeId)}`, {
        headers: {
            'X-Goog-Api-Key': googlePlacesApiKey.value(),
            'X-Goog-FieldMask': 'id,displayName,formattedAddress,location,currentOpeningHours,types',
        },
    });
    if (!response.ok) {
        throw new https_1.HttpsError('internal', `Place details request failed with status ${response.status}.`);
    }
    return (await response.json());
});
exports.nearbyPlaces = (0, https_1.onCall)({ region: 'us-central1', enforceAppCheck: true, secrets: [googlePlacesApiKey] }, async (request) => {
    const data = requireRequest(request);
    const center = coordinates(data);
    const type = placeType(data.type);
    const result = await placesRequest('places:searchNearby', {
        includedTypes: [type],
        maxResultCount: 20,
        rankPreference: 'DISTANCE',
        locationRestriction: { circle: { center, radius: maxRadiusMeters } },
    }, 'places.id,places.displayName,places.formattedAddress,places.location,places.currentOpeningHours,places.types');
    return result;
});
function tokenMapKeys(value) {
    if (!value || typeof value !== 'object')
        return [];
    return Object.keys(value);
}
exports.notifyEmergencyEscape = (0, firestore_2.onDocumentCreated)({
    document: 'emergency_alerts/{alertId}',
    region: 'us-central1',
    secrets: [supabaseServiceRoleKey],
}, async (event) => {
    const alert = (event.data?.data() ?? {});
    if (alert.type !== 'EMERGENCY_ESCAPE')
        return;
    const intersectionId = typeof alert.intersectionId === 'string' ? alert.intersectionId : '';
    const intersectionName = typeof alert.intersectionName === 'string'
        ? alert.intersectionName
        : typeof alert.intersection === 'string'
            ? alert.intersection
            : '';
    // Only primary record (officerId '') triggers pushes.
    if (typeof alert.officerId === 'string' && alert.officerId !== '')
        return;
    if (!intersectionId && !intersectionName)
        return;
    const supabaseUrl = (supabaseUrlParam.value() || process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
    const serviceKey = (supabaseServiceRoleKey.value() || process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
    if (!supabaseUrl || !serviceKey) {
        console.warn('Supabase credentials not configured for notifyEmergencyEscape; skipping officer lookup.');
        return;
    }
    let officers = [];
    try {
        const res = await fetch(`${supabaseUrl}/rest/v1/users?select=assigned_intersection_id,assigned_intersection,fcm_tokens&role=eq.traffic_police&is_verified=eq.true`, {
            headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
        });
        if (res.ok) {
            officers = await res.json();
        }
        else {
            console.error(`Supabase officer lookup returned HTTP ${res.status}`);
        }
    }
    catch (error) {
        console.error('Supabase officer lookup failed:', error);
    }
    const tokens = [];
    for (const data of officers) {
        const assignedId = typeof data.assigned_intersection_id === 'string'
            ? data.assigned_intersection_id
            : '';
        const assignedName = typeof data.assigned_intersection === 'string'
            ? data.assigned_intersection.trim().toLowerCase()
            : '';
        const matches = (intersectionId !== '' && assignedId === intersectionId) ||
            (intersectionName !== '' &&
                assignedName !== '' &&
                assignedName === intersectionName.toLowerCase());
        if (!matches)
            continue;
        tokens.push(...tokenMapKeys(data.fcm_tokens));
    }
    if (tokens.length === 0)
        return;
    const driverName = typeof alert.driverName === 'string' && alert.driverName.length > 0
        ? alert.driverName
        : 'An ambulance driver';
    const distance = typeof alert.distanceMeters === 'number'
        ? Math.round(alert.distanceMeters)
        : null;
    const eta = typeof alert.estimatedArrivalMinutes === 'number'
        ? Math.round(alert.estimatedArrivalMinutes)
        : null;
    const etaText = eta !== null ? ` ~${eta} min away` : distance !== null ? ` ${distance} m away` : '';
    const direction = typeof alert.approachDirection === 'string' && alert.approachDirection
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
        const response = await (0, messaging_1.getMessaging)().sendEachForMulticast(message);
        if (response.failureCount > 0) {
            response.responses.forEach((result, index) => {
                if (!result.success) {
                    console.error(`FCM push failed for token ${index}: ${result.error?.code ?? ''} ${result.error?.message ?? ''}`);
                }
            });
        }
    }
    catch (error) {
        console.error('FCM push failed:', error);
    }
    // Stamp primary record so dashboards see pushes were attempted.
    await (0, firestore_1.getFirestore)().collection('emergency_alerts').doc(event.params.alertId).update({
        pushSentAt: firestore_1.FieldValue.serverTimestamp(),
        pushRecipientCount: tokens.length,
    });
});
