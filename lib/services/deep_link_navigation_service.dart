import 'package:url_launcher/url_launcher.dart';

class DeepLinkNavigationService {
  const DeepLinkNavigationService._();

  static Future<bool> openGoogleMaps({
    required double destinationLatitude,
    required double destinationLongitude,
    double? originLatitude,
    double? originLongitude,
  }) async {
    final query = <String, String>{
      'api': '1',
      'destination': '$destinationLatitude,$destinationLongitude',
      'travelmode': 'driving',
    };
    if (originLatitude != null && originLongitude != null) {
      query['origin'] = '$originLatitude,$originLongitude';
    }

    return _launch(Uri.https('www.google.com', '/maps/dir/', query));
  }

  static Future<bool> openWaze({
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    final uri = Uri.https('waze.com', '/ul', <String, String>{
      'll': '$destinationLatitude,$destinationLongitude',
      'navigate': 'yes',
    });
    return _launch(uri);
  }

  static Future<bool> _launch(Uri uri) async {
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
