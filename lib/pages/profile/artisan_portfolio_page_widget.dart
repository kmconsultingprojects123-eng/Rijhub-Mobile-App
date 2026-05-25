import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api_config.dart';
import '../../services/artist_service.dart';
import '../../services/token_storage.dart';

class ArtisanPortfolioPageWidget extends StatefulWidget {
  const ArtisanPortfolioPageWidget({super.key});

  static const String routeName = 'artisanPortfolio';
  static const String routePath = '/artisanPortfolio';

  @override
  State<ArtisanPortfolioPageWidget> createState() =>
      _ArtisanPortfolioPageWidgetState();
}

class _ArtisanPortfolioPageWidgetState
    extends State<ArtisanPortfolioPageWidget> {
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;
  Map<String, dynamic>? _artisanProfile;
  final List<_PortfolioImage> _images = [];

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  Future<void> _loadPortfolio() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await ArtistService.getMyProfile();
      if (!mounted) return;
      _artisanProfile =
          profile == null ? null : Map<String, dynamic>.from(profile);
      _images
        ..clear()
        ..addAll(_extractPortfolioImages(_artisanProfile));
    } catch (e) {
      if (!mounted) return;
      _error = 'Unable to load portfolio. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_PortfolioImage> _extractPortfolioImages(Map<String, dynamic>? profile) {
    if (profile == null) return [];
    final found = <_PortfolioImage>[];
    final candidates = [
      profile['portfolio'],
      profile['portfolioImages'],
      profile['images'],
      profile['photos'],
      profile['media'],
    ];

    void addUrl(dynamic value, {String? title, String? publicId}) {
      if (value == null) return;
      final raw = value.toString().trim();
      if (raw.isEmpty) return;
      final url = _normalizeImageUrl(raw);
      if (url == null) return;
      if (found.any((item) => item.url == url)) return;
      found.add(_PortfolioImage(
        url: url,
        title: title ?? '',
        publicId: publicId,
      ));
    }

    for (final candidate in candidates) {
      if (candidate is! List) continue;
      for (final item in candidate) {
        if (item is String) {
          addUrl(item);
        } else if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final title = (map['title'] ?? map['caption'] ?? map['name'])
              ?.toString()
              .trim();
          final publicId =
              (map['public_id'] ?? map['publicId'])?.toString().trim();
          if (map['images'] is List) {
            for (final image in map['images']) {
              addUrl(image, title: title, publicId: publicId);
            }
          }
          addUrl(map['url'] ?? map['src'] ?? map['path'],
              title: title, publicId: publicId);
        }
      }
    }

    return found;
  }

  String? _normalizeImageUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$API_BASE_URL$value';
    return null;
  }

  List<Map<String, dynamic>> _portfolioPayload() {
    return _images
        .map((image) => {
              'title': image.title,
              'images': [image.url],
              if (image.publicId != null && image.publicId!.isNotEmpty)
                'public_id': image.publicId,
            })
        .toList();
  }

  Future<void> _savePortfolio() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = Map<String, dynamic>.from(_artisanProfile ?? {});
      payload['portfolio'] = _portfolioPayload();
      final updated = await ArtistService.updateMyProfile(payload);
      if (!mounted) return;
      if (updated != null) {
        _artisanProfile = Map<String, dynamic>.from(updated);
        _images
          ..clear()
          ..addAll(_extractPortfolioImages(_artisanProfile));
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Portfolio updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Unable to save portfolio. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadImages({int? replaceIndex}) async {
    if (_uploading || _saving) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: replaceIndex == null,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final localPaths = result.files
          .map((file) => file.path)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList();

      if (!kIsWeb && localPaths.isNotEmpty) {
        await _savePortfolioWithNativeFiles(
          localPaths: localPaths,
          replaceIndex: replaceIndex,
        );
        return;
      }

      try {
        await _savePortfolioWithPickedFiles(
          files: result.files,
          replaceIndex: replaceIndex,
        );
        return;
      } catch (multipartError) {
        if (kDebugMode) {
          debugPrint('Portfolio multipart upload failed: $multipartError');
        }
      }

      final uploaded = <_PortfolioImage>[];
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final upload = await _uploadBytesToCloudinary(
          bytes: bytes,
          filename: file.name,
        );
        uploaded.add(upload);
      }

      if (uploaded.isEmpty) {
        throw Exception('No images were selected.');
      }

      setState(() {
        if (replaceIndex != null && replaceIndex < _images.length) {
          _images[replaceIndex] = uploaded.first;
        } else {
          _images.addAll(uploaded);
        }
      });

      await _savePortfolio();
    } catch (e) {
      if (kDebugMode) debugPrint('Portfolio upload failed: $e');
      if (!mounted) return;
      setState(() => _error = _humanizeUploadError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  List<Map<String, dynamic>> _portfolioPayloadFor(
    List<_PortfolioImage> images,
  ) {
    return images
        .map((image) => {
              'title': image.title,
              'images': [image.url],
              if (image.publicId != null && image.publicId!.isNotEmpty)
                'public_id': image.publicId,
            })
        .toList();
  }

  Future<void> _savePortfolioWithNativeFiles({
    required List<String> localPaths,
    int? replaceIndex,
  }) async {
    final retained = List<_PortfolioImage>.from(_images);
    if (replaceIndex != null && replaceIndex < retained.length) {
      retained.removeAt(replaceIndex);
    }

    final payload = Map<String, dynamic>.from(_artisanProfile ?? {});
    payload['portfolio'] = _portfolioPayloadFor(retained);

    final fileMap = <String, List<String>>{};
    for (var i = 0; i < localPaths.length; i++) {
      fileMap['portfolioImage${i + 1}'] = [localPaths[i]];
    }

    final updated = await ArtistService.updateMyProfile(
      payload,
      fileMap: fileMap,
    );
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _artisanProfile = Map<String, dynamic>.from(updated);
        _images
          ..clear()
          ..addAll(_extractPortfolioImages(_artisanProfile));
      });
    } else {
      await _loadPortfolio();
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Portfolio updated')),
    );
  }

  Future<void> _savePortfolioWithPickedFiles({
    required List<PlatformFile> files,
    int? replaceIndex,
  }) async {
    final token = await TokenStorage.getToken();
    final request = http.MultipartRequest(
        'PUT', Uri.parse('$API_BASE_URL/api/artisans/me'));
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final retained = List<_PortfolioImage>.from(_images);
    if (replaceIndex != null && replaceIndex < retained.length) {
      retained.removeAt(replaceIndex);
    }

    final payload = Map<String, dynamic>.from(_artisanProfile ?? {});
    payload['portfolio'] = _portfolioPayloadFor(retained);
    payload.forEach((key, value) {
      if (value == null) return;
      if (value is String || value is num || value is bool) {
        request.fields[key] = value.toString();
      } else {
        request.fields[key] = jsonEncode(value);
      }
    });

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      request.files.add(
        http.MultipartFile.fromBytes(
          'portfolioImage${i + 1}',
          bytes,
          filename: file.name,
        ),
      );
    }

    if (request.files.isEmpty) {
      throw Exception('No readable image bytes found');
    }

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Portfolio multipart save failed: ${response.statusCode} ${response.body}',
      );
    }

    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    Map<String, dynamic>? updated;
    if (body is Map && body['data'] is Map) {
      updated = Map<String, dynamic>.from(body['data']);
    } else if (body is Map) {
      updated = Map<String, dynamic>.from(body);
    }

    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _artisanProfile = updated;
        _images
          ..clear()
          ..addAll(_extractPortfolioImages(_artisanProfile));
      });
    } else {
      await _loadPortfolio();
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Portfolio updated')),
    );
  }

  String _humanizeUploadError(Object error) {
    final message = error.toString();
    if (message.contains('401') || message.contains('Unauthorized')) {
      return 'Upload failed because your session expired. Please log in again.';
    }
    if (message.contains('413') ||
        message.toLowerCase().contains('too large')) {
      return 'Upload failed because the image is too large.';
    }
    if (message.contains('No host specified')) {
      return 'Upload failed because the API base URL is not configured.';
    }
    return 'Upload failed. Please try another image.';
  }

  Future<_PortfolioImage> _uploadBytesToCloudinary({
    required Uint8List bytes,
    required String filename,
  }) async {
    final token = await TokenStorage.getToken();
    final signUri = Uri.parse('$API_BASE_URL/api/uploads/sign');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final signResponse = await http
        .post(
          signUri,
          headers: headers,
          body: jsonEncode({'folder': 'artisans/portfolio'}),
        )
        .timeout(const Duration(seconds: 20));
    if (signResponse.statusCode < 200 || signResponse.statusCode >= 300) {
      throw Exception('Upload signature failed');
    }

    final decodedSignData = jsonDecode(signResponse.body);
    final signData = decodedSignData is Map && decodedSignData['data'] is Map
        ? Map<String, dynamic>.from(decodedSignData['data'])
        : Map<String, dynamic>.from(decodedSignData as Map);
    final uploadUrl = (signData['upload_url'] as String?) ??
        'https://api.cloudinary.com/v1_1/${signData['cloud_name'] ?? ''}/auto/upload';

    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    for (final key in [
      'api_key',
      'timestamp',
      'signature',
      'public_id',
      'folder'
    ]) {
      final value = signData[key];
      if (value != null) request.fields[key] = value.toString();
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudinary upload failed');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = (body['secure_url'] ?? body['url'])?.toString() ?? '';
    if (url.isEmpty) throw Exception('Upload returned no URL');

    return _PortfolioImage(
      url: url,
      title: '',
      publicId: (body['public_id'] ?? signData['public_id'])?.toString(),
    );
  }

  Future<void> _deleteImage(int index) async {
    if (_saving || index >= _images.length) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete image?'),
        content: const Text('This image will be removed from your portfolio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final removed = _images.removeAt(index);
    setState(() {});
    try {
      await _savePortfolio();
    } catch (_) {
      if (!mounted) return;
      setState(() => _images.insert(index, removed));
    }
  }

  void _showImagePreview(_PortfolioImage image) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(220),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Image.network(
                    image.url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton.filled(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        actions: [
          IconButton(
            tooltip: 'Upload images',
            onPressed:
                (_uploading || _saving) ? null : () => _pickAndUploadImages(),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPortfolio,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.error.withAlpha(22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.error.withAlpha(80),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.error),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Proof of Work',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_uploading || _saving)
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_uploading || _saving)
                            ? null
                            : () => _pickAndUploadImages(),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload images'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_images.isEmpty)
                      _EmptyPortfolioState(
                        onUpload: (_uploading || _saving)
                            ? null
                            : () => _pickAndUploadImages(),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final crossAxisCount = width > 700 ? 4 : 2;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.82,
                            ),
                            itemCount: _images.length,
                            itemBuilder: (context, index) {
                              final image = _images[index];
                              return _PortfolioImageTile(
                                image: image,
                                onTap: () => _showImagePreview(image),
                                onEdit: (_uploading || _saving)
                                    ? null
                                    : () => _pickAndUploadImages(
                                          replaceIndex: index,
                                        ),
                                onDelete: (_uploading || _saving)
                                    ? null
                                    : () => _deleteImage(index),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PortfolioImage {
  final String url;
  final String title;
  final String? publicId;

  const _PortfolioImage({
    required this.url,
    required this.title,
    this.publicId,
  });
}

class _EmptyPortfolioState extends StatelessWidget {
  final VoidCallback? onUpload;

  const _EmptyPortfolioState({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.onSurface.withAlpha(24),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 42,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'No portfolio images yet',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload photos of completed jobs so customers can preview your work.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withAlpha(160),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onUpload,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add images'),
          ),
        ],
      ),
    );
  }
}

class _PortfolioImageTile extends StatelessWidget {
  final _PortfolioImage image;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _PortfolioImageTile({
    required this.image,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: colorScheme.surface,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      image.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colorScheme.onSurface.withAlpha(18),
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: colorScheme.onSurface.withAlpha(100),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(130),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.zoom_out_map,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colorScheme.onSurface.withAlpha(20),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: IconButton(
                        tooltip: 'Replace image',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: colorScheme.onSurface.withAlpha(20),
                    ),
                    Expanded(
                      child: IconButton(
                        tooltip: 'Delete image',
                        onPressed: onDelete,
                        color: colorScheme.error,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
