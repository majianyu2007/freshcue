import 'dart:io';

import 'package:flutter/material.dart';

/// 全屏看图：双指/双击缩放，点击图片区域显隐标题栏。
/// 入口一律是“直接点图片”，不放额外按钮。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.file,
    required this.title,
    required this.heroTag,
  });

  final File file;
  final String title;
  final String heroTag;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _lastDoubleTapDown;
  bool _chromeVisible = true;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final position = _lastDoubleTapDown?.localPosition;
    final dx = position == null ? 0.0 : -position.dx * (scale - 1);
    final dy = position == null ? 0.0 : -position.dy * (scale - 1);
    _transform.value = Matrix4.translationValues(
      dx,
      dy,
      0,
    ).multiplied(Matrix4.diagonal3Values(scale, scale, 1));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    extendBodyBehindAppBar: true,
    appBar: _chromeVisible
        ? AppBar(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black54,
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          )
        : null,
    body: GestureDetector(
      onTap: () => setState(() => _chromeVisible = !_chromeVisible),
      onDoubleTapDown: (details) => _lastDoubleTapDown = details,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 0.8,
        maxScale: 8,
        boundaryMargin: const EdgeInsets.all(80),
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: Image.file(widget.file, fit: BoxFit.contain),
          ),
        ),
      ),
    ),
  );
}

/// 推入全屏看图页。
void openImageViewer(
  BuildContext context, {
  required File file,
  required String title,
  required String heroTag,
}) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          ImageViewerPage(file: file, title: title, heroTag: heroTag),
    ),
  );
}
