import 'package:flutter/material.dart';

/// Envuelve cualquier contenido del canvas generativo para que se pueda
/// acercar/alejar (pellizcar), arrastrar y rotar (con dos dedos) - como un
/// canvas real, no una lista fija. Doble toque restaura la posicion/escala
/// original.
class ManipulableCanvas extends StatefulWidget {
  final Widget child;

  const ManipulableCanvas({super.key, required this.child});

  @override
  State<ManipulableCanvas> createState() => _ManipulableCanvasState();
}

class _ManipulableCanvasState extends State<ManipulableCanvas> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0;

  Offset _startOffset = Offset.zero;
  double _startScale = 1.0;
  double _startRotation = 0.0;
  Offset _startFocalPoint = Offset.zero;

  void _onScaleStart(ScaleStartDetails details) {
    _startOffset = _offset;
    _startScale = _scale;
    _startRotation = _rotation;
    _startFocalPoint = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_startScale * details.scale).clamp(0.5, 3.5);
      _rotation = _startRotation + details.rotation;
      _offset = _startOffset + (details.focalPoint - _startFocalPoint);
    });
  }

  void _reset() {
    setState(() {
      _offset = Offset.zero;
      _scale = 1.0;
      _rotation = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onDoubleTap: _reset,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
            ..rotateZ(_rotation)
            ..scaleByDouble(_scale, _scale, 1, 1),
          child: widget.child,
        ),
      ),
    );
  }
}
