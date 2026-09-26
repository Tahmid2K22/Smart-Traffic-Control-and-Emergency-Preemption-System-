package com.ambulance.bd.ambulance_dashboard

import android.os.Bundle
import com.google.android.gms.maps.model.LatLng
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.CircularBounds
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.net.FetchPlaceRequest
import com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest
import com.google.android.libraries.places.api.net.SearchNearbyRequest
import com.google.android.libraries.places.api.net.PlacesClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private lateinit var placesClient: PlacesClient

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		val appInfo = packageManager.getApplicationInfo(packageName, android.content.pm.PackageManager.GET_META_DATA)
		val apiKey = appInfo.metaData?.getString("com.google.android.geo.API_KEY")
			?: error("Google Maps API key is missing from AndroidManifest.xml")
		if (!Places.isInitialized()) Places.initializeWithNewPlacesApiEnabled(applicationContext, apiKey)
		placesClient = Places.createClient(this)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "e_ambulance/places")
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"autocomplete" -> autocomplete(call.argument<String>("query") ?: "", call.argument<Double>("latitude") ?: 0.0, call.argument<Double>("longitude") ?: 0.0, result)
					"details" -> details(call.argument<String>("placeId") ?: "", result)
					"nearby" -> nearby(call.argument<String>("type") ?: "", call.argument<Double>("latitude") ?: 0.0, call.argument<Double>("longitude") ?: 0.0, result)
					else -> result.notImplemented()
				}
			}
	}

	private fun autocomplete(query: String, latitude: Double, longitude: Double, result: MethodChannel.Result) {
		val bounds = CircularBounds.newInstance(LatLng(latitude, longitude), 30000.0)
		val request = FindAutocompletePredictionsRequest.builder()
			.setQuery(query)
			.setCountries(listOf("BD"))
			.setLocationBias(bounds)
			.setOrigin(LatLng(latitude, longitude))
			.build()
		placesClient.findAutocompletePredictions(request)
			.addOnSuccessListener { response ->
				result.success(response.autocompletePredictions.map { prediction -> mapOf("placeId" to prediction.placeId, "description" to prediction.getFullText(null).toString()) })
			}
			.addOnFailureListener { error -> result.error("AUTOCOMPLETE_FAILED", error.message, null) }
	}

	private fun details(placeId: String, result: MethodChannel.Result) {
		val fields = listOf(Place.Field.ID, Place.Field.NAME, Place.Field.ADDRESS, Place.Field.LAT_LNG, Place.Field.TYPES, Place.Field.OPENING_HOURS)
		placesClient.fetchPlace(FetchPlaceRequest.newInstance(placeId, fields))
			.addOnSuccessListener { response -> result.success(placeMap(response.place)) }
			.addOnFailureListener { error -> result.error("DETAILS_FAILED", error.message, null) }
	}

	private fun nearby(type: String, latitude: Double, longitude: Double, result: MethodChannel.Result) {
		val fields = listOf(Place.Field.ID, Place.Field.NAME, Place.Field.ADDRESS, Place.Field.LAT_LNG, Place.Field.TYPES, Place.Field.OPENING_HOURS)
		val request = SearchNearbyRequest.builder(CircularBounds.newInstance(LatLng(latitude, longitude), 30000.0), fields)
			.setIncludedTypes(listOf(type))
			.setRankPreference(SearchNearbyRequest.RankPreference.DISTANCE)
			.setMaxResultCount(20)
			.build()
		placesClient.searchNearby(request)
			.addOnSuccessListener { response -> result.success(mapOf("places" to response.places.map(::placeMap))) }
			.addOnFailureListener { error -> result.error("NEARBY_FAILED", error.message, null) }
	}

	private fun placeMap(place: Place): Map<String, Any?> = mapOf(
		"id" to place.id,
		"name" to place.name,
		"address" to place.address,
		"latitude" to place.latLng?.latitude,
		"longitude" to place.latLng?.longitude,
		"types" to place.placeTypes,
	)
}
