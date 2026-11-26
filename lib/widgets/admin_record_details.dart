import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminRecordDetails extends StatelessWidget {
  const AdminRecordDetails({
    super.key,
    required this.title,
    required this.data,
  });

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final fields = data.entries
        .where((entry) => !_isSensitive(entry.key))
        .toList();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title),
      children: [
        for (final entry in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    _label(entry.key),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(child: SelectableText(_displayValue(entry.value))),
              ],
            ),
          ),
      ],
    );
  }

  static bool _isSensitive(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('credential');
  }

  static String _label(String key) {
    final words = key
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'));
    return words
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  static String _displayValue(Object? value) {
    if (value == null) return 'Not provided';
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is GeoPoint) {
      return '${value.latitude}, ${value.longitude}';
    }
    if (value is DateTime) return value.toLocal().toString();
    if (value is Map || value is List) return jsonEncode(_jsonSafe(value));
    final text = value.toString().trim();
    return text.isEmpty ? 'Not provided' : text;
  }

  static Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is GeoPoint) {
      return {'latitude': value.latitude, 'longitude': value.longitude};
    }
    if (value is DateTime) return value.toLocal().toString();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (!_isSensitive(entry.key.toString()))
            entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value.toString();
  }
}
