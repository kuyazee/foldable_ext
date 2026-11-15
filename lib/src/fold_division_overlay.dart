import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import 'emulated_device.dart';
import 'emulated_window.dart';
import 'fold_division_api.dart';
import 'fold_division_config.dart';

/// Paints the fold division and its keep-clear margins over [child].
///
/// A debug aid: a button under the tinted band sits where iPhone Duo asks
/// interactive content to stay away.
///
/// - Reads the fold from `DuoMediaQuery`, so it needs a `FoldableProvider`
///   (or a `FoldDivisionScope`) above it. With none it paints nothing.
/// - Paints a division while it is in force: active, with the posture
///   `partiallyOpen`. Set [showInactive] to outline one that is not in force.
/// - Under a `FoldDivisionScope` that emulates a device it also paints the
///   occlusions of the device and a line along each inner edge of its safe
///   area.
/// - Never takes part in hit testing. Every pointer goes to [child].
/// - Region bounds are in window coordinates: the Flutter view, or the
///   emulated window under a scope that matches the window size of a device.
///   The overlay keeps the bands on the fold wherever it sits: inside a
///   scrolling list, under a scale or a rotation, behind a repaint boundary.
///   It is clipped to its own box.
class FoldDivisionOverlay extends StatelessWidget {
  /// Creates an overlay.
  const FoldDivisionOverlay({
    super.key,
    required this.child,
    this.visible = kDebugMode,
    this.showInactive = false,
    this.divisionColor = const Color(0x66E5484D),
    this.marginColor = const Color(0x33F5A524),
    this.inactiveColor = const Color(0x99889096),
    this.occlusionColor = const Color(0x663E63DD),
    this.safeAreaColor = const Color(0xCC30A46C),
  });

  /// The widget below the overlay.
  final Widget child;

  /// Whether anything is painted. Defaults to [kDebugMode].
  final bool visible;

  /// Whether a division that is not in force is outlined.
  final bool showInactive;

  /// The fill of the division rect.
  final Color divisionColor;

  /// The fill of the margin band on each side of the division.
  final Color marginColor;

  /// The outline of a division that is not in force.
  final Color inactiveColor;

  /// The fill of an occlusion of the emulated device.
  final Color occlusionColor;

  /// The line along each inner edge of the emulated safe area.
  final Color safeAreaColor;

  /// The inner edges of [safeArea] in a window of [windowSize], one line per
  /// side that has an inset. Each rect has no thickness: it runs from its
  /// top left corner to its bottom right one.
  static List<Rect> safeAreaEdges(Size windowSize, EdgeInsets safeArea) {
    final Rect inner = safeArea.deflateRect(Offset.zero & windowSize);
    return <Rect>[
      if (safeArea.left > 0)
        Rect.fromLTRB(inner.left, 0, inner.left, windowSize.height),
      if (safeArea.top > 0)
        Rect.fromLTRB(0, inner.top, windowSize.width, inner.top),
      if (safeArea.right > 0)
        Rect.fromLTRB(inner.right, 0, inner.right, windowSize.height),
      if (safeArea.bottom > 0)
        Rect.fromLTRB(0, inner.bottom, windowSize.width, inner.bottom),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final FoldableData data = DuoMediaQuery.of(context);
    final FoldDivisionConfig config = FoldDivision.configOf(context);
    final DeviceEmulation? emulation = FoldDivision.emulationOf(context);
    final bool inForce = data.status == HingeStatus.partiallyOpen;

    final List<FoldDivisionOverlayBand> bands = <FoldDivisionOverlayBand>[
      if (visible)
        for (final ReservedRegion region in data.regions)
          if (region.kind == ReservedRegionKind.division &&
              (showInactive || (inForce && region.isActive)))
            FoldDivisionOverlayBand(
              division: region.bounds,
              keepClear: config.keepClearRect(region.bounds),
              inForce: inForce && region.isActive,
            ),
    ];

    // The occlusions of the device are in the coordinates of its window, so
    // they are drawn only while that window is the one on screen.
    final List<Rect> occlusions =
        visible && emulation != null && emulation.matchesWindowSize
            ? emulation.state.occlusions
            : const <Rect>[];
    final List<Rect> edges = visible && emulation != null
        ? safeAreaEdges(emulation.windowSize, emulation.safeArea)
        : const <Rect>[];

    return _OverlayRenderWidget(
      bands: bands,
      occlusions: occlusions,
      safeAreaEdges: edges,
      occlusionColor: occlusionColor,
      safeAreaColor: safeAreaColor,
      divisionColor: divisionColor,
      marginColor: marginColor,
      inactiveColor: inactiveColor,
      child: child,
    );
  }
}

/// One division as [FoldDivisionOverlay] paints it, in window coordinates.
@immutable
class FoldDivisionOverlayBand {
  /// Creates a band.
  const FoldDivisionOverlayBand({
    required this.division,
    required this.keepClear,
    required this.inForce,
  });

  /// The division rect.
  final Rect division;

  /// The division rect grown by its margins.
  final Rect keepClear;

  /// Whether the division is active with the posture `partiallyOpen`.
  final bool inForce;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldDivisionOverlayBand &&
          other.division == division &&
          other.keepClear == keepClear &&
          other.inForce == inForce;

  @override
  int get hashCode => Object.hash(division, keepClear, inForce);

  @override
  String toString() =>
      'FoldDivisionOverlayBand($division, keepClear: $keepClear, '
      'inForce: $inForce)';
}

class _OverlayRenderWidget extends SingleChildRenderObjectWidget {
  const _OverlayRenderWidget({
    required this.bands,
    required this.occlusions,
    required this.safeAreaEdges,
    required this.divisionColor,
    required this.marginColor,
    required this.inactiveColor,
    required this.occlusionColor,
    required this.safeAreaColor,
    required super.child,
  });

  final List<FoldDivisionOverlayBand> bands;
  final List<Rect> occlusions;
  final List<Rect> safeAreaEdges;
  final Color occlusionColor;
  final Color safeAreaColor;
  final Color divisionColor;
  final Color marginColor;
  final Color inactiveColor;

  @override
  RenderFoldDivisionOverlay createRenderObject(BuildContext context) =>
      RenderFoldDivisionOverlay(
        bands: bands,
        occlusions: occlusions,
        safeAreaEdges: safeAreaEdges,
        divisionColor: divisionColor,
        marginColor: marginColor,
        inactiveColor: inactiveColor,
        occlusionColor: occlusionColor,
        safeAreaColor: safeAreaColor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFoldDivisionOverlay renderObject,
  ) {
    renderObject
      ..bands = bands
      ..occlusions = occlusions
      ..safeAreaEdges = safeAreaEdges
      ..occlusionColor = occlusionColor
      ..safeAreaColor = safeAreaColor
      ..divisionColor = divisionColor
      ..marginColor = marginColor
      ..inactiveColor = inactiveColor;
  }
}

/// The render object behind [FoldDivisionOverlay].
///
/// A proxy box: layout and hit testing are the child's own. It paints the
/// bands, the occlusions and the safe area edges after the child, into a
/// [ViewSpaceLayer].
///
/// A position read during paint goes stale when an ancestor scrolls or
/// transforms without repainting this box. The layer works out its place
/// each time the scene is built, so the bands stay on the fold with no
/// repaint. The layer exists only while there is something to paint.
class RenderFoldDivisionOverlay extends RenderProxyBox {
  /// Creates the render object.
  RenderFoldDivisionOverlay({
    required List<FoldDivisionOverlayBand> bands,
    required Color divisionColor,
    required Color marginColor,
    required Color inactiveColor,
    List<Rect> occlusions = const <Rect>[],
    List<Rect> safeAreaEdges = const <Rect>[],
    Color occlusionColor = const Color(0x663E63DD),
    Color safeAreaColor = const Color(0xCC30A46C),
  })  : _bands = bands,
        _occlusions = occlusions,
        _safeAreaEdges = safeAreaEdges,
        _divisionColor = divisionColor,
        _marginColor = marginColor,
        _inactiveColor = inactiveColor,
        _occlusionColor = occlusionColor,
        _safeAreaColor = safeAreaColor;

  /// The divisions to paint, in window coordinates.
  List<FoldDivisionOverlayBand> get bands => _bands;
  List<FoldDivisionOverlayBand> _bands;
  set bands(List<FoldDivisionOverlayBand> value) {
    if (listEquals(value, _bands)) return;
    final bool painted = _paintsSomething;
    _bands = value;
    _contentChanged(painted);
  }

  /// The occlusions of the emulated device, in window coordinates.
  List<Rect> get occlusions => _occlusions;
  List<Rect> _occlusions;
  set occlusions(List<Rect> value) {
    if (listEquals(value, _occlusions)) return;
    final bool painted = _paintsSomething;
    _occlusions = value;
    _contentChanged(painted);
  }

  /// The inner edges of the emulated safe area, in window coordinates. Each
  /// rect is a line from its top left corner to its bottom right one.
  List<Rect> get safeAreaEdges => _safeAreaEdges;
  List<Rect> _safeAreaEdges;
  set safeAreaEdges(List<Rect> value) {
    if (listEquals(value, _safeAreaEdges)) return;
    final bool painted = _paintsSomething;
    _safeAreaEdges = value;
    _contentChanged(painted);
  }

  bool get _paintsSomething =>
      _bands.isNotEmpty || _occlusions.isNotEmpty || _safeAreaEdges.isNotEmpty;

  void _contentChanged(bool paintedBefore) {
    if (paintedBefore != _paintsSomething) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  /// The fill of an occlusion.
  Color get occlusionColor => _occlusionColor;
  Color _occlusionColor;
  set occlusionColor(Color value) {
    if (value == _occlusionColor) return;
    _occlusionColor = value;
    markNeedsPaint();
  }

  /// The colour of the safe area edges.
  Color get safeAreaColor => _safeAreaColor;
  Color _safeAreaColor;
  set safeAreaColor(Color value) {
    if (value == _safeAreaColor) return;
    _safeAreaColor = value;
    markNeedsPaint();
  }

  /// The fill of the division rect.
  Color get divisionColor => _divisionColor;
  Color _divisionColor;
  set divisionColor(Color value) {
    if (value == _divisionColor) return;
    _divisionColor = value;
    markNeedsPaint();
  }

  /// The fill of the margin band.
  Color get marginColor => _marginColor;
  Color _marginColor;
  set marginColor(Color value) {
    if (value == _marginColor) return;
    _marginColor = value;
    markNeedsPaint();
  }

  /// The outline of a division that is not in force.
  Color get inactiveColor => _inactiveColor;
  Color _inactiveColor;
  set inactiveColor(Color value) {
    if (value == _inactiveColor) return;
    _inactiveColor = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();
  final LayerHandle<ViewSpaceLayer> _viewSpaceLayer =
      LayerHandle<ViewSpaceLayer>();

  @override
  bool get alwaysNeedsCompositing => _paintsSomething;

  /// [bands] as they land in this box's own coordinates, cut to its size.
  ///
  /// Mapped through the inverse of the full transform to the window. Under
  /// a rotation each rect is the bounding box of the turned band. For tests
  /// and diagnostics: painting does not go through here.
  @visibleForTesting
  List<FoldDivisionOverlayBand> debugLocalBands() {
    if (!attached || !hasSize) return const <FoldDivisionOverlayBand>[];
    final Matrix4 toLocal = RenderEmulatedWindow.transformToWindow(this);
    if (toLocal.invert() == 0) return const <FoldDivisionOverlayBand>[];
    final Rect box = Offset.zero & size;
    return <FoldDivisionOverlayBand>[
      for (final FoldDivisionOverlayBand band in _bands)
        FoldDivisionOverlayBand(
          division:
              MatrixUtils.transformRect(toLocal, band.division).intersect(box),
          keepClear:
              MatrixUtils.transformRect(toLocal, band.keepClear).intersect(box),
          inForce: band.inForce,
        ),
    ];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_paintsSomething) {
      _clipLayer.layer = null;
      _viewSpaceLayer.layer = null;
      return;
    }

    // Clip to this box in its own space, then step out to window space.
    _clipLayer.layer = context.pushClipRect(
      true,
      offset,
      Offset.zero & size,
      (PaintingContext context, Offset offset) {
        final ViewSpaceLayer layer = _viewSpaceLayer.layer ??= ViewSpaceLayer();
        context.pushLayer(layer, _paintBands, Offset.zero);
      },
      oldLayer: _clipLayer.layer,
    );
  }

  /// Paints onto a canvas that is in window coordinates.
  void _paintBands(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    for (final Rect occlusion in _occlusions) {
      if (occlusion.width > 0 && occlusion.height > 0) {
        canvas.drawRect(occlusion, Paint()..color = _occlusionColor);
      }
    }
    final Paint edge = Paint()
      ..color = _safeAreaColor
      ..strokeWidth = 2;
    for (final Rect line in _safeAreaEdges) {
      canvas.drawLine(line.topLeft, line.bottomRight, edge);
    }
    for (final FoldDivisionOverlayBand band in _bands) {
      final Rect keepClear = band.keepClear;
      final Rect division = band.division;
      if (band.inForce) {
        if (keepClear.width > 0 && keepClear.height > 0) {
          canvas.drawRect(keepClear, Paint()..color = _marginColor);
        }
        if (division.width > 0 && division.height > 0) {
          canvas.drawRect(division, Paint()..color = _divisionColor);
        }
      } else {
        final Paint outline = Paint()
          ..color = _inactiveColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        if (keepClear.width > 0 && keepClear.height > 0) {
          canvas.drawRect(keepClear.deflate(0.5), outline);
        }
        if (division.width > 0 && division.height > 0) {
          canvas.drawRect(division.deflate(0.5), outline);
        }
      }
    }
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _viewSpaceLayer.layer = null;
    super.dispose();
  }
}

/// A layer whose children are drawn in the coordinates of their window: the
/// nearest emulated window above the layer, or the Flutter view.
///
/// Each time the scene is built it multiplies the transforms of every layer
/// above it, up to an [EmulatedSpaceLayer] or the view's own root layer, and
/// pushes the inverse. What is drawn inside lands at the same logical
/// position in the window wherever the layer sits. With a transform that
/// cannot be inverted (a scale of zero) it draws nothing.
class ViewSpaceLayer extends ContainerLayer {
  /// The transform from window coordinates into this layer, as last built, or
  /// null before the first build and when the chain cannot be inverted.
  @visibleForTesting
  Matrix4? get debugViewToLayer => _viewToLayer;
  Matrix4? _viewToLayer;

  // An ancestor can move without this layer changing, so it is added to the
  // scene again on every build. `FollowerLayer` does the same.
  @override
  bool get alwaysNeedsAddToScene => true;

  Matrix4? _inverseOfAncestors() {
    // From the parent up to the layer that owns the window coordinates,
    // which is left out. An emulated window holds its scale and the root
    // layer holds the device pixel ratio. Neither is part of the coordinates
    // inside the window.
    final List<ContainerLayer> chain = <ContainerLayer>[];
    for (ContainerLayer? layer = parent; layer != null; layer = layer.parent) {
      if (layer is EmulatedSpaceLayer || layer.parent == null) break;
      chain.add(layer);
    }
    final Matrix4 toWindow = Matrix4.identity();
    for (int i = chain.length - 1; i >= 0; i--) {
      chain[i].applyTransform(i == 0 ? this : chain[i - 1], toWindow);
    }
    return toWindow.invert() == 0 ? null : toWindow;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final Matrix4? inverse = _inverseOfAncestors();
    _viewToLayer = inverse;
    if (inverse == null) {
      engineLayer = null;
      return;
    }
    engineLayer = builder.pushTransform(
      inverse.storage,
      oldLayer: engineLayer as ui.TransformEngineLayer?,
    );
    addChildrenToScene(builder);
    builder.pop();
  }

  @override
  void applyTransform(Layer? child, Matrix4 transform) {
    final Matrix4? inverse = _viewToLayer;
    if (inverse != null) transform.multiply(inverse);
  }
}
