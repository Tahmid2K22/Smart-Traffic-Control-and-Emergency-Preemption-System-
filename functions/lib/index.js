"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.nearbyPlaces = exports.placeDetails = exports.placesAutocomplete = void 0;
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
const googlePlacesApiKey = (0, params_1.defineSecret)('GOOGLE_PLACES_API_KEY');
const placesBaseUrl = 'https://places.googleapis.com/v1';
const maxRadiusMeters = 30000;
function requireRequest(request) {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign-in is required.');
    if (!request.app)
        throw new https_1.HttpsError('failed-precondition', 'App verification is required.');
    return request.data ?? {};
}
function coordinates(data) {
    const latitude = Number(data.latitude);
    const longitude = Number(data.longitude);
    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
        throw new https_1.HttpsError('invalid-argument', 'Valid latitude and longitude are required.');
    }
    return { latitude, longitude };
}
function placeType(value) {
    if (value !== 'hospital' && value !== 'pharmacy')
        throw new https_1.HttpsError('invalid-argument', 'Unsupported place type.');
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
    if (!response.ok)
        throw new https_1.HttpsError('internal', `Places request failed with status ${response.status}.`);
    return (await response.json());
}
exports.placesAutocomplete = (0, https_1.onCall)({ region: 'us-central1', enforceAppCheck: true, secrets: [googlePlacesApiKey] }, async (request) => {
    const data = requireRequest(request);
    const input = typeof data.input === 'string' ? data.input.trim() : '';
    if (input.length < 2 || input.length > 120)
        throw new https_1.HttpsError('invalid-argument', 'Search text must be 2 to 120 characters.');
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
    if (!placeId || placeId.length > 200)
        throw new https_1.HttpsError('invalid-argument', 'A valid place ID is required.');
    const response = await fetch(`${placesBaseUrl}/places/${encodeURIComponent(placeId)}`, {
        headers: {
            'X-Goog-Api-Key': googlePlacesApiKey.value(),
            'X-Goog-FieldMask': 'id,displayName,formattedAddress,location,currentOpeningHours,types',
        },
    });
    if (!response.ok)
        throw new https_1.HttpsError('internal', `Place details request failed with status ${response.status}.`);
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
//# sourceMappingURL=index.js.map