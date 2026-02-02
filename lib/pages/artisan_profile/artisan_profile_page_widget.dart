import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';

class ArtisanProfilePageWidget extends StatelessWidget {
  final Map<String, dynamic> artisan;
  const ArtisanProfilePageWidget({super.key, required this.artisan});

  String? _extractAvatar(dynamic a) {
    try {
      if (a == null) return null;
      if (a is String) return a;
      if (a is Map) {
        final p = a['profileImage'] ?? a['avatar'] ?? a['image'];
        if (p is String) return p;
        if (p is Map) return (p['url'] ?? p['path'])?.toString();
      }
    } catch (_) {}
    return null;
  }

  List<String> _extractImages(dynamic a) {
    try {
      if (a == null) return [];
      final candidates = [a['portfolio'], a['works'], a['images'], a['gallery'], a['projects']];
      final urls = <String>[];
      for (final c in candidates) {
        if (c == null) continue;
        if (c is List) {
          for (final e in c) {
            if (e is String && e.isNotEmpty) urls.add(e);
            if (e is Map) {
              final p = e['url'] ?? e['path'] ?? e['thumbnail'];
              if (p != null) urls.add(p.toString());
            }
          }
        } else if (c is String) {
          urls.addAll(c.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
        }
      }
      return urls.toSet().toList();
    } catch (_) {
      return [];
    }
  }

  // Extract a readable location string from artisan map
  String? _extractLocation(Map<String, dynamic> a) {
    try {
      // Check common fields in order of preference
      final sa = a['serviceArea'];
      if (sa is Map) {
        final addr = sa['address'] ?? sa['name'] ?? sa['location'];
        if (addr != null && addr.toString().trim().isNotEmpty) return addr.toString();
      }
      final address = a['address'] ?? a['location'] ?? a['city'] ?? a['town'] ?? a['lga'];
      if (address != null && address.toString().trim().isNotEmpty) return address.toString();
      // Some APIs put location inside profile sub-object
      if (a['profile'] is Map) {
        final p = a['profile'] as Map;
        final ap = p['address'] ?? p['location'] ?? p['city'] ?? p['serviceArea'] is Map ? (p['serviceArea']['address'] ?? null) : null;
        if (ap != null && ap.toString().trim().isNotEmpty) return ap.toString();
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = (artisan['name'] ?? artisan['fullName'] ?? 'Unknown').toString();
    final email = (artisan['email'] ?? '').toString();
    final location = _extractLocation(artisan);
    final bio = (artisan['bio'] ?? artisan['about'] ?? '').toString();
    final rating = artisan['rating'] ?? artisan['ratings'] ?? artisan['avgRating'];
    final kyc = artisan['kycVerified'] ?? artisan['kyc'] ?? false;
    final avatar = _extractAvatar(artisan);
    final images = _extractImages(artisan);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: Text('Back', style: FlutterFlowTheme.of(context).bodyMedium),
                style: TextButton.styleFrom(foregroundColor: FlutterFlowTheme.of(context).primary),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              CircleAvatar(radius: 36, backgroundImage: avatar != null ? NetworkImage(avatar) : null, backgroundColor: FlutterFlowTheme.of(context).primary.withAlpha(30), child: avatar == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?') : null),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: FlutterFlowTheme.of(context).titleLarge.copyWith(fontWeight: FontWeight.w700)),
                if (email.isNotEmpty) Text(email, style: FlutterFlowTheme.of(context).bodySmall.copyWith(color: FlutterFlowTheme.of(context).secondaryText)),
                if (location != null && location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 14, color: FlutterFlowTheme.of(context).secondaryText),
                    const SizedBox(width: 6),
                    Expanded(child: Text(location, style: FlutterFlowTheme.of(context).bodySmall.copyWith(color: FlutterFlowTheme.of(context).secondaryText))),
                  ]),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.star, color: Colors.amber, size: 18),
                  const SizedBox(width: 6),
                  Text(rating != null ? rating.toString() : 'No ratings', style: FlutterFlowTheme.of(context).bodyMedium),
                  const SizedBox(width: 12),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: kyc == true ? Colors.green.withAlpha(30) : Colors.grey.withAlpha(30), borderRadius: BorderRadius.circular(12)), child: Text(kyc == true ? 'KYC verified' : 'KYC not verified', style: FlutterFlowTheme.of(context).bodySmall)),
                ])
              ]))
            ]),
            const SizedBox(height: 12),
            if (bio.trim().isNotEmpty) ...[
              Text('About', style: FlutterFlowTheme.of(context).titleSmall.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(bio, style: FlutterFlowTheme.of(context).bodyMedium.copyWith(color: FlutterFlowTheme.of(context).secondaryText)),
              const SizedBox(height: 12),
            ],
            Text('Proof of work', style: FlutterFlowTheme.of(context).titleSmall.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (images.isEmpty)
              Text('No work images available', style: FlutterFlowTheme.of(context).bodySmall.copyWith(color: FlutterFlowTheme.of(context).secondaryText))
            else
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final url = images[i];
                    return ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(url, width: 240, height: 160, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 240, height: 160, color: FlutterFlowTheme.of(context).alternate)));
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

