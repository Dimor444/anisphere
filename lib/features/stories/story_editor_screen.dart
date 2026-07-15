import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/post_image_compressor.dart';
import '../../services/story_service.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/user_avatar.dart';
import '../feed/create_post_screen.dart' show showAnimePickerSheet;
import 'mention_picker_sheet.dart';

// ─── Filters ────────────────────────────────────────────────────────────────

/// A named color-matrix preset (4x5, offsets in 0..255) applied to the BASE
/// image layer only — overlays (text, strokes, stickers) render above it,
/// unfiltered, exactly like Instagram. Selection is in-memory editor state:
/// the look is baked into the upload by the existing flatten (the
/// ColorFiltered sits inside the RepaintBoundary), so nothing is persisted
/// and no doc field or rule exists for it.
class StoryFilter {
  final String name;
  final List<double> matrix;
  const StoryFilter(this.name, this.matrix);

  /// Curated starter presets. First entry is the identity ("Original").
  static const List<StoryFilter> presets = [
    StoryFilter('Original', [
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
    // Classic Rec.601 luminance grayscale.
    StoryFilter('Mono', [
      0.299, 0.587, 0.114, 0, 0, //
      0.299, 0.587, 0.114, 0, 0, //
      0.299, 0.587, 0.114, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
    // High-contrast grayscale (luminance x1.3, lifted blacks pulled down).
    StoryFilter('Noir', [
      0.389, 0.763, 0.148, 0, -30, //
      0.389, 0.763, 0.148, 0, -30, //
      0.389, 0.763, 0.148, 0, -30, //
      0, 0, 0, 1, 0,
    ]),
    // The classic sepia matrix.
    StoryFilter('Sepia', [
      0.393, 0.769, 0.189, 0, 0, //
      0.349, 0.686, 0.168, 0, 0, //
      0.272, 0.534, 0.131, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
    // Faded, slightly warm, lifted blacks.
    StoryFilter('Vintage', [
      0.90, 0, 0, 0, 24, //
      0, 0.85, 0, 0, 22, //
      0, 0, 0.75, 0, 16, //
      0, 0, 0, 1, 0,
    ]),
    StoryFilter('Warm', [
      1.08, 0, 0, 0, 8, //
      0, 1.02, 0, 0, 4, //
      0, 0, 0.92, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
    StoryFilter('Cool', [
      0.92, 0, 0, 0, 0, //
      0, 1.00, 0, 0, 2, //
      0, 0, 1.08, 0, 8, //
      0, 0, 0, 1, 0,
    ]),
    // Saturation 1.4 around Rec.709 luma.
    StoryFilter('Vivid', [
      1.3150, -0.2861, -0.0289, 0, 0, //
      -0.0850, 1.1139, -0.0289, 0, 0, //
      -0.0850, -0.2861, 1.3711, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
  ];
}

// ─── Overlay model ──────────────────────────────────────────────────────────
// The editor is a layer stack: base image + overlays, flattened into one
// bitmap on export. Later phases (drawing, stickers, filters) add overlay
// types here and a render case in _OverlayView — the flatten step captures
// whatever the stack paints, so export needs no per-type code. Overlays are
// in-memory only; nothing but the flattened image ever leaves the editor.

/// One item on the editor canvas. [position] is the item's CENTER in canvas
/// logical pixels (the canvas is exactly the fitted image rect).
abstract class StoryOverlay {
  StoryOverlay({required this.id, required this.position});
  final String id;
  Offset position;
}

class TextOverlay extends StoryOverlay {
  TextOverlay({
    required super.id,
    required super.position,
    required this.text,
    this.color = Colors.white,
    this.fontSize = 28,
  });

  String text;
  Color color;
  double fontSize;
}

/// An anime-tag sticker (poster + title chip). Dual-natured: its VISUAL is
/// baked into the flattened image like any other overlay, while its LINK
/// (anilistId + normalized rect, measured via [chipKey] at share time) is
/// stored on the doc as [StoryAnimeTag] so the viewer can lay a tap hotspot
/// over the baked pixels. Never carries more AniList data than the id needs
/// for display — the viewer re-fetches by id.
class AnimeTagOverlay extends StoryOverlay {
  AnimeTagOverlay({
    required super.id,
    required super.position,
    required this.anilistId,
    required this.title,
    required this.posterUrl,
  });

  final int anilistId;
  final String title;
  final String posterUrl;

  /// On the chip while mounted; read at share time to measure the rect.
  final GlobalKey chipKey = GlobalKey();
}

/// A person-mention sticker (avatar + @handle chip) — the [AnimeTagOverlay]
/// mirror for app users, and MULTIPLE are allowed per story. Visual bakes
/// via the flatten; the persisted link is uid + normalized rect only
/// ([StoryMention]); handle/avatar here are ephemeral display data from the
/// search result, resolved live again by the viewer via identityProvider.
class MentionOverlay extends StoryOverlay {
  MentionOverlay({
    required super.id,
    required super.position,
    required this.uid,
    required this.handle,
    required this.avatarUrl,
  });

  final String uid;
  final String handle;
  final String avatarUrl;

  /// On the chip while mounted; read at share time to measure the rect.
  final GlobalKey chipKey = GlobalKey();
}

/// One completed freehand stroke on the drawing layer, in canvas logical
/// pixels. Strokes are not positioned/selectable items like [StoryOverlay]s;
/// they live in a single drawing layer that renders ABOVE the base image and
/// BELOW every positioned overlay (text always reads over drawings), painted
/// in completion order so later strokes cover earlier ones. Undo pops the
/// last one.
class BrushStroke {
  BrushStroke({required this.color, required this.width});
  final List<Offset> points = [];
  final Color color;
  final double width;
}

/// The stroke currently under the user's finger. A [ChangeNotifier] instead
/// of editor setState so each pointer move repaints only the strokes
/// CustomPaint (via its `repaint:` hook), not the whole editor tree.
class _ActiveStrokeNotifier extends ChangeNotifier {
  BrushStroke? stroke;

  void start(BrushStroke s) {
    stroke = s;
    notifyListeners();
  }

  void append(Offset point) {
    stroke?.points.add(point);
    notifyListeners();
  }

  void clear() {
    stroke = null;
    notifyListeners();
  }
}

// ─── Editor screen ──────────────────────────────────────────────────────────

/// Full-screen story editor (composer phase 2). Shows the picked image on a
/// canvas with draggable text overlays; Share flattens canvas + overlays via
/// RepaintBoundary.toImage into a PNG temp file and hands it to the existing
/// [PostImageCompressor] → [StoryService.createStory] pipeline. With no
/// overlays the ORIGINAL picked file goes straight to the compressor, so a
/// plain photo story is byte-for-byte the pre-editor flow.
class StoryEditorScreen extends StatefulWidget {
  final File imageFile;
  const StoryEditorScreen({super.key, required this.imageFile});

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  /// Longest edge of the flattened export, in pixels. Comfortably above the
  /// compressor's 1080 cap (sharper text after its downscale), far below
  /// anything that bloats memory.
  static const double _exportLongestEdge = 1440;

  static const List<Color> _palette = [
    Colors.white,
    Colors.black,
    AppColors.error, // red
    AppColors.warning, // orange
    AppColors.glowGold, // yellow
    AppColors.success, // green
    AppColors.glowBlue, // blue
    AppColors.glowPurple, // purple
    Color(0xFFEC4899), // pink
  ];

  final _canvasKey = GlobalKey();
  final _caption = TextEditingController();

  final List<StoryOverlay> _overlays = [];
  String? _selectedId;
  int _nextId = 0;

  // Drawing layer state (phase 3).
  final List<BrushStroke> _strokes = [];
  final _activeStroke = _ActiveStrokeNotifier();
  bool _drawing = false;
  Color _brushColor = Colors.white;
  double _brushWidth = 6;

  // Filter state (phase 5). Index into [StoryFilter.presets]; 0 = Original.
  int _filterIndex = 0;
  bool _filtersOpen = false;

  // A non-Original filter is an edit: without it a filter-only story would
  // take the compress-the-original fast path and upload unfiltered.
  bool get _hasEdits => _overlays.isNotEmpty || _strokes.isNotEmpty || _filterIndex != 0;

  /// Canvas aspect ratio (image width / height); null while decoding.
  double? _aspect;

  /// Canvas logical size, stashed by the canvas LayoutBuilder each layout —
  /// used for spawning new overlays centered and clamping drags.
  Size _canvasSize = Size.zero;

  bool _posting = false;

  TextOverlay? get _selectedText {
    final id = _selectedId;
    if (id == null) return null;
    for (final o in _overlays) {
      if (o.id == id && o is TextOverlay) return o;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _decodeAspect();
  }

  @override
  void dispose() {
    _caption.dispose();
    _activeStroke.dispose();
    super.dispose();
  }

  Future<void> _decodeAspect() async {
    // No inherited-widget lookups before the first await — this runs from
    // initState, where ScaffoldMessenger.of/Navigator.of would throw.
    try {
      final image = await decodeImageFromList(await widget.imageFile.readAsBytes());
      final aspect = image.width / image.height;
      image.dispose();
      if (!mounted) return;
      setState(() => _aspect = aspect);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't process that image — try another one.")));
      Navigator.of(context).pop();
    }
  }

  // ── Overlay actions ──

  Future<void> _addText() async {
    Haptics.light();
    final text = await _promptText();
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() {
      _drawing = false; // adding text implies leaving draw mode
      final overlay = TextOverlay(
        id: 't${_nextId++}',
        position: _canvasSize.center(Offset.zero),
        text: text.trim(),
      );
      _overlays.add(overlay);
      _selectedId = overlay.id;
    });
  }

  /// Phase 4a: search AniList (shared picker sheet) and place the sticker.
  /// One tag per story for now — picking again replaces the existing one.
  Future<void> _addAnimeTag() async {
    Haptics.light();
    final picked = await showAnimePickerSheet(context);
    if (picked == null || !mounted) return;
    if (picked.anilistId <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't tag that anime — try another.")));
      return;
    }
    // Warm the poster into the image cache so a quick Share still bakes it.
    if (picked.coverImage.isNotEmpty) {
      // ignore: discarded_futures — best-effort warm-up, failure just means placeholder pixels.
      precacheImage(CachedNetworkImageProvider(picked.coverImage), context).ignore();
    }
    setState(() {
      _drawing = false;
      _overlays.removeWhere((o) => o is AnimeTagOverlay);
      final overlay = AnimeTagOverlay(
        id: 'a${_nextId++}',
        position: _canvasSize.center(Offset.zero),
        anilistId: picked.anilistId,
        title: picked.title,
        posterUrl: picked.coverImage,
      );
      _overlays.add(overlay);
      _selectedId = overlay.id;
    });
  }

  /// A sticker chip's rendered rect in canvas coordinates, measured from the
  /// live widget and clipped to the canvas (== the image) — the shared
  /// geometry step behind every structured sticker link.
  Rect? _chipCanvasRect(GlobalKey chipKey, Offset center) {
    final box = chipKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _canvasSize.isEmpty) return null;
    // Visible part only: the canvas clips, so the hotspot must too.
    final rect = Rect.fromCenter(center: center, width: box.size.width, height: box.size.height)
        .intersect(Offset.zero & _canvasSize);
    return rect.isEmpty ? null : rect;
  }

  /// The structured half of the anime sticker: its rect normalized to the
  /// canvas, so the viewer's hotspot lands exactly on the baked pixels.
  StoryAnimeTag? _animeTagData() {
    final overlay = _overlays.whereType<AnimeTagOverlay>().firstOrNull;
    if (overlay == null) return null;
    final rect = _chipCanvasRect(overlay.chipKey, overlay.position);
    if (rect == null) return null;
    return StoryAnimeTag(
      anilistId: overlay.anilistId,
      x: rect.left / _canvasSize.width,
      y: rect.top / _canvasSize.height,
      w: rect.width / _canvasSize.width,
      h: rect.height / _canvasSize.height,
    );
  }

  /// Phase 4b: search app users (shared FollowService prefix search) and
  /// place a mention sticker. Several allowed, capped at
  /// [StoryService.maxMentions]; one sticker per person.
  Future<void> _addMention() async {
    Haptics.light();
    final mentionCount = _overlays.whereType<MentionOverlay>().length;
    if (mentionCount >= StoryService.maxMentions) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can mention up to ${StoryService.maxMentions} people.')));
      return;
    }
    final picked = await showMentionPickerSheet(context);
    if (picked == null || !mounted) return;
    if (_overlays.whereType<MentionOverlay>().any((m) => m.uid == picked.id)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('@${picked.userName} is already mentioned.')));
      return;
    }
    setState(() {
      _drawing = false;
      // Stagger spawns downward so stacked chips stay individually grabbable.
      final center = _canvasSize.center(Offset.zero);
      final overlay = MentionOverlay(
        id: 'm${_nextId++}',
        position: Offset(
          center.dx,
          (center.dy + mentionCount * 40).clamp(0.0, _canvasSize.height),
        ),
        uid: picked.id,
        handle: picked.userName,
        avatarUrl: picked.userAvatar,
      );
      _overlays.add(overlay);
      _selectedId = overlay.id;
    });
  }

  /// The structured halves of every mention sticker, same normalization as
  /// the anime tag.
  List<StoryMention> _mentionsData() {
    final out = <StoryMention>[];
    for (final overlay in _overlays.whereType<MentionOverlay>()) {
      final rect = _chipCanvasRect(overlay.chipKey, overlay.position);
      if (rect == null) continue;
      out.add(StoryMention(
        uid: overlay.uid,
        x: rect.left / _canvasSize.width,
        y: rect.top / _canvasSize.height,
        w: rect.width / _canvasSize.width,
        h: rect.height / _canvasSize.height,
      ));
    }
    return out;
  }

  void _toggleDrawing() {
    Haptics.light();
    setState(() {
      _drawing = !_drawing;
      _selectedId = null; // draw mode has no item selection
      _filtersOpen = false;
    });
  }

  void _toggleFilters() {
    Haptics.light();
    setState(() {
      _filtersOpen = !_filtersOpen;
      _drawing = false;
      _selectedId = null;
    });
  }

  void _undoStroke() {
    if (_strokes.isEmpty) return;
    Haptics.light();
    setState(() => _strokes.removeLast());
  }

  void _clearStrokes() {
    if (_strokes.isEmpty) return;
    Haptics.light();
    setState(_strokes.clear);
  }

  Future<void> _editText(TextOverlay overlay) async {
    final text = await _promptText(initial: overlay.text);
    if (text == null || !mounted) return; // dismissed — keep as-is
    setState(() {
      if (text.trim().isEmpty) {
        // Cleared the text — that's a delete.
        _overlays.removeWhere((o) => o.id == overlay.id);
        _selectedId = null;
      } else {
        overlay.text = text.trim();
      }
    });
  }

  void _delete(StoryOverlay overlay) {
    Haptics.light();
    setState(() {
      _overlays.removeWhere((o) => o.id == overlay.id);
      if (_selectedId == overlay.id) _selectedId = null;
    });
  }

  void _drag(StoryOverlay overlay, Offset delta) {
    setState(() {
      overlay.position = Offset(
        (overlay.position.dx + delta.dx).clamp(0.0, _canvasSize.width),
        (overlay.position.dy + delta.dy).clamp(0.0, _canvasSize.height),
      );
    });
  }

  Future<String?> _promptText({String? initial}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TextPromptSheet(initial: initial),
    );
  }

  // ── Export: flatten the canvas stack into the existing upload pipeline ──

  Future<void> _share() async {
    if (_posting || _aspect == null) return;
    Haptics.medium();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Measure the sticker rects while their widgets are laid out — the
    // structured halves stored alongside the pixels the flatten bakes.
    final animeTag = _animeTagData();
    final mentions = _mentionsData();

    // Selection chrome (border, delete badge) lives inside the canvas, so
    // deselect and let that frame paint before capturing.
    setState(() {
      _selectedId = null;
      _posting = true;
    });
    await WidgetsBinding.instance.endOfFrame;

    try {
      final jpeg = !_hasEdits
          ? await PostImageCompressor.compress(widget.imageFile.path)
          : await PostImageCompressor.compress((await _flattenToTempPng()).path);
      await StoryService.instance
          .createStory(jpeg, caption: _caption.text, animeTag: animeTag, mentions: mentions);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Story shared — it disappears in 24h.')));
    } on ImageCompressException {
      if (!mounted) return;
      setState(() => _posting = false);
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't process that image — try another one.")));
    } catch (_) {
      if (!mounted) return;
      setState(() => _posting = false);
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't share your story. Try again.")));
    }
  }

  /// Rasterizes the RepaintBoundary (base image + every overlay, whatever
  /// their type) to a PNG temp file for the compressor. This is THE flatten
  /// step later phases reuse untouched: anything painted inside the canvas
  /// stack ends up baked into these pixels.
  Future<File> _flattenToTempPng() async {
    final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw const ImageCompressException('editor canvas not ready');
    final pixelRatio = (_exportLongestEdge / boundary.size.longestSide).clamp(1.0, 3.0);
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? bytes;
    try {
      bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    if (bytes == null) throw const ImageCompressException('could not encode the edited image');
    final file = File('${Directory.systemTemp.path}/story_flat_${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file;
  }

  Future<void> _close() async {
    if (_posting) return;
    final dirty = _hasEdits || _caption.text.trim().isNotEmpty;
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Discard story?', style: AppTextStyles.subheading),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final selected = _selectedText;
    return Scaffold(
      backgroundColor: Colors.black,
      // The canvas must never resize (overlay offsets are canvas-relative);
      // the bottom bar rides above the keyboard on its own padding.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              // Keep the canvas clear of the top toolbar and bottom bar.
              child: Padding(
                padding: const EdgeInsets.only(top: 56, bottom: 118),
                child: _aspect == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                    : Center(child: _buildCanvas()),
              ),
            ),
            _buildTopBar(),
            // Shared color/size controls: bound to the brush in draw mode,
            // to the selected text item otherwise.
            if ((_drawing || selected != null) && !_posting) ...[
              _buildSizeSlider(selected),
              _buildColorRow(selected),
            ],
            // Filter strip occupies the same band; the toggles keep the
            // modes mutually exclusive (selection also hides it).
            if (_filtersOpen && !_drawing && _selectedId == null && !_posting && _aspect != null)
              _buildFilterStrip(),
            _buildBottomBar(),
            if (_posting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The flattenable layer stack: everything inside this RepaintBoundary —
  /// and ONLY this — becomes the story's pixels. Z-order, bottom to top:
  /// base image (color-filtered) → drawing layer (strokes in completion
  /// order) → positioned overlays (text, stickers). Text always renders over
  /// drawings, and overlays are never filtered, on screen and in the
  /// flattened export alike, because both come from this one Stack.
  Widget _buildCanvas() {
    return AspectRatio(
      aspectRatio: _aspect!,
      child: LayoutBuilder(builder: (context, constraints) {
        _canvasSize = constraints.biggest;
        return RepaintBoundary(
          key: _canvasKey,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Base layer. Aspect ratio matches the decoded image, so
                // cover == contain: no cropping, no letterbox baked in. The
                // selected filter wraps ONLY this layer — everything above
                // stays unfiltered — and bakes for free because it is inside
                // the RepaintBoundary.
                ColorFiltered(
                  colorFilter: ColorFilter.matrix(StoryFilter.presets[_filterIndex].matrix),
                  child: Image.file(widget.imageFile, fit: BoxFit.cover),
                ),
                // Tap empty canvas → drop selection.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selectedId = null),
                ),
                // Drawing layer. Its own RepaintBoundary so live stroke
                // repaints (driven by _activeStroke, not setState) stay off
                // the rest of the tree.
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _StrokesPainter(strokes: _strokes, active: _activeStroke),
                    ),
                  ),
                ),
                for (final o in _overlays)
                  _OverlayView(
                    key: ValueKey(o.id),
                    overlay: o,
                    selected: o.id == _selectedId,
                    onTap: () {
                      Haptics.light();
                      if (_selectedId == o.id && o is TextOverlay) {
                        _editText(o);
                      } else {
                        setState(() => _selectedId = o.id);
                      }
                    },
                    onDragStart: () => setState(() => _selectedId = o.id),
                    onDrag: (delta) => _drag(o, delta),
                    onDelete: () => _delete(o),
                  ),
                // Draw mode: capture every pan as a stroke, above the text
                // items so their drag handlers are suspended while drawing.
                if (_drawing)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _activeStroke.start(
                          BrushStroke(color: _brushColor, width: _brushWidth)..points.add(d.localPosition)),
                      onPanUpdate: (d) => _activeStroke.append(d.localPosition),
                      onPanEnd: (_) => _endStroke(),
                      onPanCancel: _endStroke,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _endStroke() {
    final stroke = _activeStroke.stroke;
    _activeStroke.clear();
    if (stroke == null || stroke.points.isEmpty) return;
    setState(() => _strokes.add(stroke));
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 4,
      right: 4,
      child: Row(
        children: [
          IconButton(
            onPressed: _close,
            icon: const Icon(LucideIcons.x, color: Colors.white),
          ),
          const Spacer(),
          if (_drawing) ...[
            IconButton(
              onPressed: _strokes.isEmpty || _posting ? null : _undoStroke,
              icon: Icon(LucideIcons.undo2, color: _strokes.isEmpty ? Colors.white38 : Colors.white),
              tooltip: 'Undo stroke',
            ),
            IconButton(
              onPressed: _strokes.isEmpty || _posting ? null : _clearStrokes,
              icon: Icon(LucideIcons.trash2, color: _strokes.isEmpty ? Colors.white38 : Colors.white),
              tooltip: 'Clear drawing',
            ),
          ],
          IconButton(
            onPressed: _aspect == null || _posting ? null : _toggleFilters,
            icon: Icon(LucideIcons.sparkles, color: _filtersOpen ? AppColors.primaryLight : Colors.white),
            tooltip: 'Filters',
          ),
          IconButton(
            onPressed: _aspect == null || _posting ? null : _addMention,
            icon: const Icon(LucideIcons.atSign, color: Colors.white),
            tooltip: 'Mention someone',
          ),
          IconButton(
            onPressed: _aspect == null || _posting ? null : _addAnimeTag,
            icon: const Icon(LucideIcons.tag, color: Colors.white),
            tooltip: 'Tag an anime',
          ),
          IconButton(
            onPressed: _aspect == null || _posting ? null : _toggleDrawing,
            icon: Icon(LucideIcons.brush, color: _drawing ? AppColors.primaryLight : Colors.white),
            tooltip: 'Draw',
          ),
          IconButton(
            onPressed: _aspect == null || _posting ? null : _addText,
            icon: const Icon(LucideIcons.type, color: Colors.white),
            tooltip: 'Add text',
          ),
        ],
      ),
    );
  }

  Widget _buildSizeSlider(TextOverlay? selected) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 118,
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: SizedBox(
            width: 220,
            child: _drawing
                ? Slider(
                    value: _brushWidth,
                    min: 2,
                    max: 24,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: (v) => setState(() => _brushWidth = v),
                  )
                : Slider(
                    value: selected!.fontSize,
                    min: 14,
                    max: 72,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: (v) => setState(() => selected.fontSize = v),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorRow(TextOverlay? selected) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 124,
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _palette.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final color = _palette[i];
            final active = _drawing ? _brushColor == color : selected!.color == color;
            return GestureDetector(
              onTap: () => setState(() {
                if (_drawing) {
                  _brushColor = color;
                } else {
                  selected!.color = color;
                }
              }),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: active ? AppColors.primaryLight : Colors.white70, width: active ? 3 : 1.5),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Horizontal preset previews: the user's own image, downscaled once
  /// (shared ResizeImage cache entry across all thumbnails) with each
  /// preset's ColorFiltered on top — GPU-side, so the strip stays cheap.
  Widget _buildFilterStrip() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 124,
      child: SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: StoryFilter.presets.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final filter = StoryFilter.presets[i];
            final active = i == _filterIndex;
            return GestureDetector(
              onTap: () {
                Haptics.light();
                setState(() => _filterIndex = i);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: active ? AppColors.primaryLight : Colors.white24, width: active ? 2 : 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(filter.matrix),
                        child: Image.file(widget.imageFile,
                            width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 112),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(filter.name,
                      style: AppTextStyles.captionMuted
                          .copyWith(color: active ? AppColors.primaryLight : AppColors.textSecondary)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _caption,
                enabled: !_posting,
                maxLength: StoryService.maxCaptionChars,
                maxLines: 1,
                style: AppTextStyles.body,
                decoration: const InputDecoration(hintText: 'Add a caption (optional)…', counterText: ''),
              ),
              const SizedBox(height: 8),
              GradientButton(
                label: 'Share to Story',
                onPressed: _aspect == null || _posting ? null : _share,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Overlay rendering ──────────────────────────────────────────────────────

/// Renders one [StoryOverlay] on the canvas, centered on its position, with
/// drag/tap plumbing and selection chrome (border + delete badge — hidden
/// while flattening because the editor deselects first). New overlay types
/// add a case to [_content].
class _OverlayView extends StatelessWidget {
  final StoryOverlay overlay;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDelete;

  const _OverlayView({
    super.key,
    required this.overlay,
    required this.selected,
    required this.onTap,
    required this.onDragStart,
    required this.onDrag,
    required this.onDelete,
  });

  Widget _content() {
    final o = overlay;
    if (o is TextOverlay) {
      return Text(
        o.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: o.color,
          fontSize: o.fontSize,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 8)],
        ),
      );
    }
    if (o is AnimeTagOverlay) {
      // The chipKey wraps exactly what gets baked, so the measured rect and
      // the flattened pixels agree.
      return Container(
        key: o.chipKey,
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (o.posterUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(imageUrl: o.posterUrl, width: 30, height: 40, fit: BoxFit.cover),
              ),
              const SizedBox(width: 8),
            ] else ...[
              const Icon(LucideIcons.tag, color: AppColors.primaryLight, size: 18),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                o.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }
    if (o is MentionOverlay) {
      return Container(
        key: o.chipKey,
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(name: o.handle, imageUrl: o.avatarUrl, radius: 11),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '@${o.handle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.primaryLight, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }
    throw UnsupportedError('unknown overlay type: ${o.runtimeType}');
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: overlay.position.dx,
      top: overlay.position.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: onTap,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (d) => onDrag(d.delta),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                // Constant padding whether selected or not, so selection
                // never shifts the text's center.
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: selected ? Colors.white54 : Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _content(),
              ),
              if (selected)
                Positioned(
                  top: -10,
                  right: -10,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.x, size: 14, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Drawing layer painter ──────────────────────────────────────────────────

/// Paints every completed stroke plus the in-progress one. Constructed with
/// `repaint: active`, so pointer moves repaint just this layer — the editor
/// tree only rebuilds when a stroke completes or is undone.
class _StrokesPainter extends CustomPainter {
  final List<BrushStroke> strokes;
  final _ActiveStrokeNotifier active;

  _StrokesPainter({required this.strokes, required this.active}) : super(repaint: active);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintStroke(canvas, s);
    }
    final live = active.stroke;
    if (live != null) _paintStroke(canvas, live);
  }

  void _paintStroke(Canvas canvas, BrushStroke s) {
    if (s.points.isEmpty) return;
    if (s.points.length == 1) {
      // A tap-like stroke: a round dot of the brush width.
      canvas.drawCircle(s.points.first, s.width / 2, Paint()..color = s.color);
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (final p in s.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StrokesPainter old) => old.strokes.length != strokes.length || old.active != active;
}

// ─── Text entry sheet ───────────────────────────────────────────────────────

class _TextPromptSheet extends StatefulWidget {
  final String? initial;
  const _TextPromptSheet({this.initial});

  @override
  State<_TextPromptSheet> createState() => _TextPromptSheetState();
}

class _TextPromptSheetState extends State<_TextPromptSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.initial == null ? 'Add text' : 'Edit text', style: AppTextStyles.heading),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 100,
                minLines: 1,
                maxLines: 3,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Type something…',
                  helperText: widget.initial == null ? null : 'Clear the text to remove it',
                ),
              ),
              const SizedBox(height: 8),
              GradientButton(label: 'Done', onPressed: () => Navigator.pop(context, _controller.text)),
            ],
          ),
        ),
      ),
    );
  }
}
