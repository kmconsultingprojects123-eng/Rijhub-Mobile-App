// Simple CLI to submit KYC to the RijHub API using multipart/form-data.
// Usage examples (zsh / macOS):
//
// dart run scripts/submit_kyc.dart \
//   --token="<JWT>" \
//   --profile="/absolute/path/to/profile.jpg" \
//   --idFront="/absolute/path/to/id-front.jpg" \
//   --idBack="/absolute/path/to/id-back.jpg" \
//   --businessName="Alice Services" \
//   --country="Nigeria" \
//   --state="Lagos" \
//   --lga="Ikeja" \
//   --idType="national_id" \
//   --serviceCategory="plumbing" \
//   --yearsExperience="5" \
//   --baseUrl="https://rijhub.com"  // optional, defaults to https://rijhub.com

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

Map<String, String> _parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (final a in argv) {
    if (!a.startsWith('--')) continue;
    final idx = a.indexOf('=');
    if (idx == -1) continue;
    final key = a.substring(2, idx);
    final val = a.substring(idx + 1);
    out[key] = val;
  }
  return out;
}

void _printUsage() {
  print('''submit_kyc.dart - submit KYC to RijHub

Required flags:
  --token=<JWT>
  --profile=/absolute/path/to/profile.jpg
  --idFront=/absolute/path/to/id-front.jpg
  --idBack=/absolute/path/to/id-back.jpg
  --businessName="Name"
  --country="Country"
  --state="State"
  --lga="LGA"
  --idType="national_id|driver_license|passport"
  --serviceCategory="plumbing"
  --yearsExperience="5"

Optional:
  --baseUrl=https://rijhub.com   (defaults to https://rijhub.com)

Example:
  dart run scripts/submit_kyc.dart --token="<JWT>" --profile="/Users/me/p.jpg" --idFront="/Users/me/f.jpg" --idBack="/Users/me/b.jpg" --businessName="Alice Service" --country="Nigeria" --state="Lagos" --lga="Ikeja" --idType="national_id" --serviceCategory="plumbing" --yearsExperience=5
''');
}

Future<int> main(List<String> args) async {
  final flags = _parseArgs(args);
  final required = ['token','profile','idFront','idBack','businessName','country','state','lga','idType','serviceCategory','yearsExperience'];
  for (final r in required) {
    if (!flags.containsKey(r) || flags[r]!.trim().isEmpty) {
      print('Missing required flag: --$r');
      _printUsage();
      return 2;
    }
  }

  final token = flags['token']!;
  final profilePath = flags['profile']!;
  final idFrontPath = flags['idFront']!;
  final idBackPath = flags['idBack']!;
  final businessName = flags['businessName']!;
  final country = flags['country']!;
  final state = flags['state']!;
  final lga = flags['lga']!;
  final idType = flags['idType']!;
  final serviceCategory = flags['serviceCategory']!;
  final yearsExperience = flags['yearsExperience']!;
  final baseUrl = flags['baseUrl'] ?? 'https://rijhub.com';

  // Validate files
  final pProfile = File(profilePath);
  final pFront = File(idFrontPath);
  final pBack = File(idBackPath);
  if (!pProfile.existsSync()) { print('Profile image not found: $profilePath'); return 3; }
  if (!pFront.existsSync()) { print('ID front image not found: $idFrontPath'); return 3; }
  if (!pBack.existsSync()) { print('ID back image not found: $idBackPath'); return 3; }

  final uri = Uri.parse(baseUrl.replaceAll(RegExp(r'/$'), '') + '/api/kyc/submit');
  print('Submitting KYC to: $uri');

  final req = http.MultipartRequest('POST', uri);
  req.headers['Authorization'] = 'Bearer $token';

  req.fields['businessName'] = businessName;
  req.fields['country'] = country;
  req.fields['state'] = state;
  req.fields['lga'] = lga;
  req.fields['IdType'] = idType;
  req.fields['serviceCategory'] = serviceCategory;
  req.fields['yearsExperience'] = yearsExperience;

  try {
    req.files.add(await http.MultipartFile.fromPath('profileImage', pProfile.path));
    req.files.add(await http.MultipartFile.fromPath('IdUploadFront', pFront.path));
    req.files.add(await http.MultipartFile.fromPath('IdUploadBack', pBack.path));
  } catch (e) {
    print('Failed to read one of the files: $e');
    return 4;
  }

  try {
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final resp = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 10));
    print('Response status: ${resp.statusCode}');
    final body = resp.body;
    if (body.trim().isEmpty) {
      print('Empty body returned');
      return resp.statusCode >=200 && resp.statusCode < 300 ? 0 : 5;
    }
    try {
      final jsonBody = jsonDecode(body);
      final pretty = const JsonEncoder.withIndent('  ').convert(jsonBody);
      print('Response body:\n$pretty');
    } catch (e) {
      print('Non-JSON response body:\n$body');
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      print('KYC submit appears successful.');
      return 0;
    }
    // If server returned HTML (e.g., nginx error), show first 1000 chars safely
    final low = body.toLowerCase();
    if (low.contains('<html') || low.contains('<!doctype')) {
      print('Server returned HTML (likely an error page). First 1000 characters:');
      print(body.substring(0, body.length > 1000 ? 1000 : body.length));
    }
    return 6;
  } catch (e) {
    print('Network error during KYC submit: $e');
    return 7;
  }
}

