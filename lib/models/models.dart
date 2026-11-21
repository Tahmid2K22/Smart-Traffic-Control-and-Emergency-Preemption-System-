// shared models

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ServiceItem {
  final IconData icon;
  final String label;
  final Color color;
  final String subtitle;

  const ServiceItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.subtitle,
  });
}

// ── Hospital model ────────────────────────────────────────────────────────────

class HospitalModel {
  final String id;
  final String name;
  final String city;
  final String address;
  final String email;
  final String phone;
  final double lat;
  final double lon;
  final int beds;
  final List<String> services;
  final List<String> diagnoses;
  final bool isApproved;
  final String registeredBy;
  final Timestamp? createdAt;

  const HospitalModel({
    required this.id,
    required this.name,
    required this.city,
    this.address = '',
    this.email = '',
    this.phone = '',
    required this.lat,
    required this.lon,
    required this.beds,
    required this.services,
    required this.diagnoses,
    required this.isApproved,
    required this.registeredBy,
    this.createdAt,
  });

  factory HospitalModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final location = data['location'] as GeoPoint?;
    final lat = (data['lat'] as num?)?.toDouble() ?? location?.latitude ?? 0.0;
    final lon = (data['lon'] as num?)?.toDouble() ?? location?.longitude ?? 0.0;
    return HospitalModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      city: data['city'] as String? ?? '',
      address: data['address'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      lat: lat,
      lon: lon,
      beds: (data['beds'] as num?)?.toInt() ?? 0,
      services: List<String>.from(data['services'] as List? ?? []),
      diagnoses: List<String>.from(data['diagnoses'] as List? ?? []),
      isApproved: data['isApproved'] as bool? ?? false,
      registeredBy: data['registeredBy'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'city': city,
    'lat': lat,
    'lon': lon,
    'beds': beds,
    'services': services,
    'diagnoses': diagnoses,
    'isApproved': isApproved,
    'registeredBy': registeredBy,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
  };
}

// ── Admin activity log ────────────────────────────────────────────────────────

class AdminLog {
  final String id;
  final String adminUid;
  final String adminName;
  final String action; // e.g. 'approve_hospital', 'reject_driver'
  final String targetType; // 'hospital' | 'driver' | 'user'
  final String targetId;
  final String targetName;
  final Timestamp? timestamp;

  const AdminLog({
    required this.id,
    required this.adminUid,
    required this.adminName,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.targetName,
    this.timestamp,
  });

  factory AdminLog.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdminLog(
      id: doc.id,
      adminUid: data['adminUid'] as String? ?? '',
      adminName: data['adminName'] as String? ?? 'Admin',
      action: data['action'] as String? ?? '',
      targetType: data['targetType'] as String? ?? '',
      targetId: data['targetId'] as String? ?? '',
      targetName: data['targetName'] as String? ?? '',
      timestamp: data['timestamp'] as Timestamp?,
    );
  }
}
