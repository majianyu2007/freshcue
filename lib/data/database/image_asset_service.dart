import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_log.dart';
import '../../core/utils/id_gen.dart';
import '../../domain/entities/source_asset.dart';
import '../../domain/enums/enums.dart';

/// 图片资产服务：验证 → 安全复制到沙箱 → 哈希 → 缩略图。
/// 文件写入成功后才允许写数据库；数据库失败时调用 [cleanup] 清理孤立文件。
class ImageAssetService {
  ImageAssetService({required this.sandboxDir, this.maxBytes = 25 * 1024 * 1024});

  /// 应用沙箱内图片目录（如 <files>/assets）。
  final String sandboxDir;
  final int maxBytes;

  static const _magics = <String, List<int>>{
    'image/jpeg': [0xFF, 0xD8, 0xFF],
    'image/png': [0x89, 0x50, 0x4E, 0x47],
    'image/webp': [0x52, 0x49, 0x46, 0x46],
  };

  /// 从字节导入（分享/图库桥接层负责把 URI 读为字节，导入后即不再依赖外部授权）。
  Future<SourceAsset> importBytes(
    Uint8List bytes, {
    required ImportSource source,
    required DateTime now,
    String? displayName,
  }) async {
    if (bytes.length > maxBytes) {
      throw const AppFailure(FailureCode.imageTooLarge);
    }
    final mime = _sniffMime(bytes);
    if (mime == null) {
      throw const AppFailure(FailureCode.imageFormatUnsupported);
    }
    final digest = sha256.convert(bytes).toString();

    // 不可预测文件名（隐私 §19.3）。
    final id = IdGen.newId();
    final ext = mime == 'image/png' ? 'png' : (mime == 'image/webp' ? 'webp' : 'jpg');
    final dir = Directory(sandboxDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = p.join(sandboxDir, '$id.$ext');
    final thumbPath = p.join(sandboxDir, '$id.thumb.png');

    int width = 0, height = 0;
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      final (w, h) = await _writeThumbnail(bytes, thumbPath);
      width = w;
      height = h;
    } on AppFailure {
      _deleteQuietly(path);
      _deleteQuietly(thumbPath);
      rethrow;
    } catch (e) {
      _deleteQuietly(path);
      _deleteQuietly(thumbPath);
      throw AppFailure(FailureCode.imageReadFailed, debugDetail: e.runtimeType.toString());
    }

    return SourceAsset(
      id: id,
      originalDisplayName: displayName,
      sandboxPath: path,
      thumbnailPath: thumbPath,
      mimeType: mime,
      width: width,
      height: height,
      sizeBytes: bytes.length,
      sha256: digest,
      importSource: source,
      importedAt: now,
    );
  }

  /// 数据库写入失败后的回滚：删除刚写入的沙箱文件。
  void cleanup(SourceAsset asset) {
    _deleteQuietly(asset.sandboxPath);
    if (asset.thumbnailPath != null) _deleteQuietly(asset.thumbnailPath!);
  }

  /// 删除资产文件（卡片删除级联）。只删应用沙箱副本，不触碰图库原图。
  void deleteFiles(SourceAsset asset) => cleanup(asset);

  String? _sniffMime(Uint8List bytes) {
    for (final e in _magics.entries) {
      if (bytes.length >= e.value.length) {
        var ok = true;
        for (var i = 0; i < e.value.length; i++) {
          if (bytes[i] != e.value[i]) {
            ok = false;
            break;
          }
        }
        if (ok) return e.key;
      }
    }
    return null;
  }

  /// 生成缩略图（最长边 480px），返回原图尺寸。
  /// 通过 instantiateImageCodec 的 target 尺寸解码，避免整图长驻内存。
  Future<(int, int)> _writeThumbnail(Uint8List bytes, String thumbPath) async {
    final probe = await ui.instantiateImageCodec(bytes);
    final frame = await probe.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    probe.dispose();

    final scale = 480 / (width > height ? width : height);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: scale < 1 ? (width * scale).round() : width,
      targetHeight: scale < 1 ? (height * scale).round() : height,
    );
    final thumbFrame = await codec.getNextFrame();
    final data =
        await thumbFrame.image.toByteData(format: ui.ImageByteFormat.png);
    thumbFrame.image.dispose();
    codec.dispose();
    if (data == null) {
      throw const AppFailure(FailureCode.imageReadFailed, debugDetail: 'thumb encode null');
    }
    await File(thumbPath).writeAsBytes(data.buffer.asUint8List(), flush: true);
    return (width, height);
  }

  void _deleteQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      AppLog.w('asset', '清理文件失败: ${e.runtimeType}');
    }
  }
}

/// 供测试与列表使用的缩略图 Provider（按显示尺寸解码交由 Image.file 的 cacheWidth）。
ImageProvider thumbnailProvider(SourceAsset asset) =>
    FileImage(File(asset.thumbnailPath ?? asset.sandboxPath));
