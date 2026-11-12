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

  Future<void> seedKhulnaIntersection() async {
    final uid = await _requireAdmin();
    final ref = _firestore
        .collection('intersections')
        .doc(IntersectionPoint.khulna.id);
    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(ref)).exists) return;
      transaction.set(ref, {
        ...IntersectionPoint.khulna.toMap(),
        'fullPlusCode': '7MJFVGX3+G39',
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
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
        'isActive': true,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.update(data);
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
