//shared models

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// enums

enum ActivityStatus { active, completed, cancelled }


class StatusConfig {
  final Color color;
  final IconData icon;
  final String label;
  const StatusConfig({
    required this.color,
    required this.icon,
    required this.label,
  });
}

// models

class ActivityItem {
  final String id;
  final String destination;
  final String address;
  final String date;
  final ActivityStatus status;
  final String ambulanceType;
  final String driver;
  final String vehicle;
  final int amount;
  final String? eta;
  final String distance;

  const ActivityItem({
    required this.id,
    required this.destination,
    required this.address,
    required this.date,
    required this.status,
    required this.ambulanceType,
    required this.driver,
    required this.vehicle,
    required this.amount,
    required this.eta,
    required this.distance,
  });
}



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



class HospitalData {
  final String name;
  final String address;
  final String distance;
  final bool isOpen;
  final int beds;
  final List<String> specialties;

  const HospitalData({
    required this.name,
    required this.address,
    required this.distance,
    required this.isOpen,
    required this.beds,
    required this.specialties,
  });
}



class RequestData {
  final String location;
  final String address;
  final String time;
  final String status;

  const RequestData({
    required this.location,
    required this.address,
    required this.time,
    required this.status,
  });
}

// ── Hospital model ────────────────────────────────────────────────────────────

class HospitalModel {
  final String id;
  final String name;
  final String city;
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
    return HospitalModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      city: data['city'] as String? ?? '',
      lat: (data['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (data['lon'] as num?)?.toDouble() ?? 0.0,
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
  final String action;       // e.g. 'approve_hospital', 'reject_driver'
  final String targetType;   // 'hospital' | 'driver' | 'user'
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
