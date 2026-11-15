import 'package:flutter/rendering.dart';

import 'emulated_device.dart';

/// Lays its child out as the window of an emulated device.
///
/// With a [windowSize] the box fills its parent, gives the child exactly
/// [windowSize] to lay out in, and shows it scaled to fit the area left by
/// [padding], centred, over [backdropColor]. The child is clipped to its
/// window, as a real window clips an app. Pointers reach the child through
/// the scale, in its own coordinates, and the backdrop around it takes the
/// ones that miss.
///
/// Without a [windowSize] the box is a plain proxy: the child gets the
/// parent's constraints, nothing extra is painted and hit testing is the
/// child's own. The box stays in the tree either way, so switching between
/// the two keeps the state of the subtree.
class RenderEmulatedWindow extends RenderProxyBox {
  /// Creates the render object.
  RenderEmulatedWindow({
    Size? windowSize,
    EdgeInsets padding = EdgeInsets.zero,
    Color backdropColor = const Color(0xFF000000),
  })  : _windowSize = windowSize,
        _padding = padding,
        _backdropColor = backdropColor;

  /// The size the child is laid out at, or null to pass the parent's
  /// constraints through.
  Size? get windowSize => _windowSize;
  Size? _windowSize;
  set windowSize(Size? value) {
    if (value == _windowSize) return;
    _windowSize = value;
    markNeedsLayout();
  }

  /// The room at the edges of this box the emulated window stays out of: the
  /// real system bars.
  EdgeInsets get padding => _padding;
  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  /// The fill around the emulated window.
  Color get backdropColor => _backdropColor;
  Color _backdropColor;
  set backdropColor(Color value) {
    if (value == _backdropColor) return;
    _backdropColor = value;
    markNeedsPaint();
  }

  /// Whether the child is laid out as an emulated window.
  bool get isEmulating => _windowSize != null;

  /// Where the emulated window sits in this box, as last laid out. Null when
  /// not emulating and when there is no room for the window.
  EmulatedWindowPlacement? get placement => _placement;
  EmulatedWindowPlacement? _placement;

  final LayerHandle<EmulatedSpaceLayer> _spaceLayer =
      LayerHandle<EmulatedSpaceLayer>();
  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  /// The transform from the coordinates of the emulated window to this box.
  Matrix4? get _childTransform {
    final EmulatedWindowPlacement? placement = _placement;
    if (placement == null) return null;
    return Matrix4.identity()
      ..setEntry(0, 0, placement.scale)
      ..setEntry(1, 1, placement.scale)
      ..setEntry(0, 3, placement.rect.left)
      ..setEntry(1, 3, placement.rect.top);
  }

  /// The transform from [object] to the window it is rendered in.
  ///
  /// That window is the nearest emulated one above [object], or the Flutter
  /// view when there is none. `MediaQuery`, `DuoMediaQuery` and the
  /// `FoldDivision` helpers under a `FoldDivisionScope` use the same
  /// coordinates. `RenderBox.localToGlobal` does not: it answers in the
  /// coordinates of the real view.
  static Matrix4 transformToWindow(RenderObject object) {
    RenderObject? below;
    for (RenderObject? node = object; node != null; node = node.parent) {
      if (below != null && node is RenderEmulatedWindow && node.isEmulating) {
        return identical(below, object)
            ? Matrix4.identity()
            : object.getTransformTo(below);
      }
      below = node;
    }
    return object.getTransformTo(null);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final Size? window = _windowSize;
    if (window == null) return super.computeDryLayout(constraints);
    return _fill(constraints, window);
  }

  /// Fills the parent. An axis the parent leaves unbounded takes the size of
  /// the emulated window.
  static Size _fill(BoxConstraints constraints, Size window) {
    return constraints.constrain(
      Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : window.width,
        constraints.hasBoundedHeight ? constraints.maxHeight : window.height,
      ),
    );
  }

  @override
  void performLayout() {
    final Size? window = _windowSize;
    if (window == null) {
      _placement = null;
      super.performLayout();
      return;
    }
    size = _fill(constraints, window);
    child?.layout(BoxConstraints.tight(window));
    _placement = placeEmulatedWindow(
      realSize: size,
      realPadding: _padding,
      emulatedSize: window,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final Size? window = _windowSize;
    if (window == null) return super.hitTest(result, position: position);
    if (!size.contains(position)) return false;
    final Matrix4? transform = _childTransform;
    final RenderBox? child = this.child;
    if (transform != null && child != null) {
      result.addWithPaintTransform(
        transform: transform,
        position: position,
        hitTest: (BoxHitTestResult result, Offset position) =>
            (Offset.zero & window).contains(position) &&
            child.hitTest(result, position: position),
      );
    }
    // The backdrop is opaque: a pointer beside the window goes no further.
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    if (_windowSize == null) return;
    final Matrix4? childTransform = _childTransform;
    if (childTransform == null) {
      transform.setZero();
    } else {
      transform.multiply(childTransform);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Size? window = _windowSize;
    if (window == null) {
      _spaceLayer.layer = null;
      _clipLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    context.canvas.drawRect(offset & size, Paint()..color = _backdropColor);

    final Matrix4? transform = _childTransform;
    final RenderBox? child = this.child;
    if (transform == null || child == null) {
      _spaceLayer.layer = null;
      _clipLayer.layer = null;
      return;
    }
    final Rect bounds = Offset.zero & window;

    if (!needsCompositing) {
      _spaceLayer.layer = null;
      _clipLayer.layer = null;
      context.canvas
        ..save()
        ..translate(offset.dx, offset.dy)
        ..transform(transform.storage)
        ..clipRect(bounds);
      context.paintChild(child, Offset.zero);
      context.canvas.restore();
      return;
    }

    final EmulatedSpaceLayer layer = _spaceLayer.layer ??= EmulatedSpaceLayer();
    layer.transform = Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..multiply(transform);
    context.pushLayer(
      layer,
      (PaintingContext context, Offset offset) {
        _clipLayer.layer = context.pushClipRect(
          true,
          offset,
          bounds,
          (PaintingContext context, Offset offset) =>
              context.paintChild(child, offset),
          oldLayer: _clipLayer.layer,
        );
      },
      Offset.zero,
      childPaintBounds: bounds,
    );
  }

  @override
  void dispose() {
    _spaceLayer.layer = null;
    _clipLayer.layer = null;
    super.dispose();
  }
}

/// The layer a [RenderEmulatedWindow] paints its child into.
///
/// Its children are in the coordinates of the emulated window. A layer that
/// draws in window coordinates stops here on its way up the layer tree and
/// lands in the emulated window, where it would otherwise reach the real
/// view.
class EmulatedSpaceLayer extends TransformLayer {}
