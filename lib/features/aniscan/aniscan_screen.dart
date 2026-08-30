import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class AniScanScreen extends StatefulWidget {
  const AniScanScreen({super.key});

  @override
  State<AniScanScreen> createState() => _AniScanScreenState();
}

class _AniScanScreenState extends State<AniScanScreen> {
  File? _image;
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String? _error;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
      _result = null;
      _error = null;
    });

    await _analyzeImage(_image!);
  }

  Future<void> _analyzeImage(File imageFile) async {
    setState(() => _isLoading = true);

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          // DO NOT fill this in. An API key placed here ships inside the app
          // binary and is extractable from any installed build — putting a
          // real key on this line leaks it to every user.
          //
          // This whole call is to be replaced by a Cloud Function proxy that
          // holds the key server-side; the client should call that, not
          // api.anthropic.com. Until then AniScan 401s by design, and its
          // drawer entry is hidden behind kAniScanEnabled in app_drawer.dart.
          'x-api-key': 'YOUR_API_KEY_HERE',
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-opus-4-5',
          'max_tokens': 1024,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': 'image/jpeg',
                    'data': base64Image,
                  },
                },
                {
                  'type': 'text',
                  'text': '''You are an anime expert. Look at this image and identify the anime character or anime series shown.

Respond ONLY with a JSON object in this exact format, no markdown, no extra text:
{
  "found": true,
  "character_name": "Character Name or Unknown",
  "anime_title": "Anime Title",
  "anime_genre": "Genre1, Genre2",
  "anime_status": "Ongoing or Completed",
  "description": "2-3 sentences about the character and anime",
  "confidence": "high/medium/low"
}

If no anime character is found, respond with:
{
  "found": false,
  "message": "No anime character detected"
}'''
                }
              ]
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['content'][0]['text'] as String;
        final cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
        final result = jsonDecode(cleaned);
        setState(() {
          _result = result;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'API error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        title: const Text(
          '🔍 AniScan',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text(
              '∞ scans',
              style: TextStyle(color: Color(0xFFFFB800)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Viewfinder area
            GestureDetector(
              onTap: () => _showSourcePicker(),
              child: Container(
                margin: const EdgeInsets.all(16),
                height: 380,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4B3FE4), Color(0xFF6B5BF5), Color(0xFF2196F3)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    // Corner brackets
                    Positioned(top: 20, left: 20,
                      child: _corner(true, true)),
                    Positioned(top: 20, right: 20,
                      child: _corner(true, false)),
                    Positioned(bottom: 20, left: 20,
                      child: _corner(false, true)),
                    Positioned(bottom: 20, right: 20,
                      child: _corner(false, false)),

                    // Content
                    Center(
                      child: _image == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.camera_alt,
                                    color: Colors.white70, size: 64),
                                const SizedBox(height: 16),
                                Text(
                                  'Tap to scan an anime character',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            )
                          : _isLoading
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(_image!,
                                          height: 200, fit: BoxFit.cover),
                                    ),
                                    const SizedBox(height: 20),
                                    const CircularProgressIndicator(
                                        color: Colors.white),
                                    const SizedBox(height: 12),
                                    const Text('Identifying character...',
                                        style: TextStyle(color: Colors.white)),
                                  ],
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(_image!,
                                      height: 320, fit: BoxFit.cover),
                                ),
                    ),
                  ],
                ),
              ),
            ),

            // Result card
            if (_result != null) ...[
              if (_result!['found'] == true)
                _buildResultCard()
              else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _result!['message'] ?? 'No character found',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      icon: Icons.camera_alt,
                      label: 'Camera',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.photo_library,
                      label: 'Gallery',
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4B3FE4).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF4B3FE4), size: 20),
              const SizedBox(width: 8),
              Text(
                _result!['character_name'] ?? 'Unknown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _result!['anime_title'] ?? '',
            style: const TextStyle(
              color: Color(0xFF4B3FE4),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _result!['description'] ?? '',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (_result!['anime_genre'] != null)
                _tag(_result!['anime_genre'], const Color(0xFF4B3FE4)),
              if (_result!['anime_status'] != null)
                _tag(_result!['anime_status'],
                    _result!['anime_status'] == 'Ongoing'
                        ? Colors.green
                        : Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4B3FE4), Color(0xFF7B5BF5)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _corner(bool top, bool left) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _CornerPainter(top: top, left: left),
      ),
    );
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Take Photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Choose from Gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool top;
  final bool left;
  const _CornerPainter({required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    final dx = left ? size.width : -size.width;
    final dy = top ? size.height : -size.height;

    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
