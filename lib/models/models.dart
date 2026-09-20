//shared models

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
