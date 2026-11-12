import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/intersection_point.dart';

class IntersectionService {
  IntersectionService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Stream<List<IntersectionPoint>> watchIntersections() =>
      _firestore.collection('intersections').snapshots().map((snapshot) {
        final points = snapshot.docs
            .map((doc) => IntersectionPoint.fromMap(doc.id, doc.data()))
            .toList();
        points.sort((a, b) => a.name.compareTo(b.name));
        return points;
      });

  Future<String> _requireAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in as an admin first.');
    final profile = await _firestore.collection('users').doc(uid).get();
    if (profile.data()?['role'] != 'admin') {
      throw StateError('Only admins can manage intersections.');
    }
    return uid;
  }

  Future<void> seedKhulnaIntersection() => seedKhulnaIntersections();

  Future<void> seedKhulnaIntersections() async {
    final uid = await _requireAdmin();
    for (final point in IntersectionPoint.khulnaIntersections) {
      final ref = _firestore.collection('intersections').doc(point.id);
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(ref);
        if (!existing.exists) {
          transaction.set(ref, {
            ...point.toMap(),
            'fullPlusCode': '7MJF${point.plusCode}',
            'location': GeoPoint(point.latitude, point.longitude),
            'createdBy': uid,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        final patch = _layoutPatch(point.id, existing.data()!);
        if (patch.isNotEmpty) {
          transaction.set(ref, {
            ...patch,
            'updatedBy': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });
    }
  }

  Map<String, dynamic> _layoutPatch(String id, Map<String, dynamic> data) {
    final defaults = IntersectionPoint(
      id: id,
      name: '',
      city: '',
      latitude: 0,
      longitude: 0,
    ).lights;
    final existing = data['trafficLights'];
    final missing = {
      for (final direction in IntersectionPoint.directions)
        if (existing is! Map || !existing.containsKey(direction))
          direction: defaults[direction]!.toMap(),
    };
    return {
      if (data['wayCount'] != 4) 'wayCount': 4,
      if (data['trafficLightCount'] != 4) 'trafficLightCount': 4,
      if (missing.isNotEmpty) 'trafficLights': missing,
    };
  }

  Future<void> saveIntersection({
    String? id,
    required String name,
    required String city,
    required double latitude,
    required double longitude,
    String plusCode = '',
  }) async {
    if (name.trim().isEmpty || city.trim().isEmpty) {
      throw ArgumentError('Intersection name and city are required.');
    }
    IntersectionPoint.validateCoordinates(latitude, longitude);
    final uid = await _requireAdmin();
    final collection = _firestore.collection('intersections');
    final ref = id == null ? collection.doc() : collection.doc(id);
    final data = {
      'name': name.trim(),
      'city': city.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'location': GeoPoint(latitude, longitude),
      'plusCode': plusCode.trim().toUpperCase(),
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (id == null) {
      await ref.set({
        ...data,
        ..._layoutPatch(ref.id, const {}),
        'isActive': true,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(ref);
        if (!existing.exists) {
          throw StateError('This intersection no longer exists.');
        }
        transaction.set(ref, {
          ...data,
          ..._layoutPatch(ref.id, existing.data()!),
        }, SetOptions(merge: true));
      });
    }
  }

  Future<void> setActive(String id, bool active) async {
    final uid = await _requireAdmin();
    await _firestore.collection('intersections').doc(id).update({
      'isActive': active,
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
