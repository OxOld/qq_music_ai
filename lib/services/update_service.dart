import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub 最新 release 的可更新信息
class AppUpdate {
  final String version; // '1.0.5'（不含 v 前缀）
  final String notes; // release 说明（markdown 原文，按纯文本展示）
  final String assetUrl; // 选中产物下载地址
  final String assetName;
  final int assetSize;

  const AppUpdate({
    required this.version,
    required this.notes,
    required this.assetUrl,
    required this.assetName,
    required this.assetSize,
  });
}

/// 下载取消令牌：abort() 会强制断开底层连接，
/// 无网络/代理未开导致请求卡住时也能立即取消，不必等 TCP 超时
class DownloadCancel {
  bool cancelled = false;
  http.Client? _client;

  void bind(http.Client client) => _client = client;

  void abort() {
    cancelled = true;
    _client?.close();
  }
}

/// 应用自更新：检查 GitHub 最新 release → 匹配本机平台的安装包 → 下载 → 安装/打开
class UpdateService {
  static const _repo = 'OxOld/qq_music_ai';
  static const _apiLatest =
      'https://api.github.com/repos/$_repo/releases/latest';
  static const _channel = MethodChannel('qq_music_ai/update');

  /// 当前应用版本（pubspec 的 build-name，如 '1.0.4'）
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 检查更新；返回 null 表示已是最新或没有匹配平台的产物。
  /// 网络失败抛异常（启动静默检查吞掉，手动检查提示）
  Future<AppUpdate?> check() async {
    final res = await http
        .get(
          Uri.parse(_apiLatest),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw 'GitHub API HTTP ${res.statusCode}';
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String?) ?? '';
    final latest = tag.replaceFirst(RegExp(r'^v'), '').trim();
    if (latest.isEmpty) return null;

    final info = await PackageInfo.fromPlatform();
    if (!_isNewer(latest, info.version)) return null;

    final assets = (data['assets'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final asset = _pickAsset(assets, await _deviceAbi());
    if (asset == null) return null;

    return AppUpdate(
      version: latest,
      notes: (data['body'] as String?) ?? '',
      assetUrl: asset['browser_download_url'] as String,
      assetName: asset['name'] as String,
      assetSize: (asset['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// 下载安装包，返回文件完整路径。onProgress: 0.0 ~ 1.0
  Future<String> download(
    AppUpdate update,
    void Function(double progress) onProgress,
    DownloadCancel cancel,
  ) async {
    final dir = Platform.isWindows
        ? (await getDownloadsDirectory()) ?? (await getTemporaryDirectory())
        : await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}${update.assetName}',
    );

    final client = http.Client();
    cancel.bind(client); // 取消时强制断开连接（卡在 0% 也能立即取消）
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse(update.assetUrl)))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw '下载失败 HTTP ${res.statusCode}';
      }
      final total = res.contentLength ?? update.assetSize;
      var received = 0;
      final sink = file.openWrite();
      try {
        // 看门狗：30 秒没有任何新数据判定超时（代理未开时 GitHub CDN 常见），不无限挂起
        final stream = res.stream.timeout(const Duration(seconds: 30));
        await for (final chunk in stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (cancel.cancelled) throw const DownloadCancelled();
      return file.path;
    } catch (e) {
      // 清理半截文件（取消或失败）
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      if (cancel.cancelled) throw const DownloadCancelled();
      if (e is TimeoutException) {
        throw '网络超时：30 秒没有收到数据\n（需要代理时请先开启代理再重试）';
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Android 拉起系统安装器；Windows 在资源管理器中定位下载的压缩包
  Future<void> installOrReveal(String path) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('installApk', path);
      } on PlatformException catch (e) {
        throw '无法启动安装：${e.message ?? e.code}';
      }
    } else if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', ['/select,$path']);
      } catch (_) {}
    }
  }

  // ---------- 内部 ----------

  /// 按平台 + 设备 ABI 选产物；不匹配返回 null
  Map<String, dynamic>? _pickAsset(
    List<Map<String, dynamic>> assets,
    String? abi,
  ) {
    Map<String, dynamic>? bySuffix(String suffix) {
      for (final a in assets) {
        if ((a['name'] as String).endsWith(suffix)) return a;
      }
      return null;
    }

    if (Platform.isWindows) {
      return bySuffix('-windows-x64.zip');
    }
    if (!Platform.isAndroid) return null; // iOS 走 TestFlight/商店，不在自更新范围

    // 优先设备 ABI 对应包，缺失时按兼容顺序回退
    var order = <String>[
      '-android-arm64.apk',
      '-android-armeabi-v7a.apk',
      '-android-x86_64.apk',
    ];
    switch (abi) {
      case 'armeabi-v7a':
        order = ['-android-armeabi-v7a.apk'];
      case 'arm64-v8a':
        order = ['-android-arm64.apk', '-android-armeabi-v7a.apk'];
      case 'x86_64' || 'x86':
        order = ['-android-x86_64.apk', '-android-arm64.apk'];
    }
    for (final suffix in order) {
      final hit = bySuffix(suffix);
      if (hit != null) return hit;
    }
    return null;
  }

  String? _abiCache;
  bool _abiLoaded = false;

  Future<String?> _deviceAbi() async {
    if (!_abiLoaded) {
      _abiLoaded = true;
      try {
        _abiCache = await _channel.invokeMethod<String>('getAbi');
      } catch (_) {
        _abiCache = null;
      }
    }
    return _abiCache;
  }

  bool _isNewer(String remote, String local) {
    List<int> parse(String v) => v
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .split(RegExp(r'[.\-+]'))
        .take(3)
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final r = parse(remote);
    final l = parse(local);
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }
}

/// 用户主动取消下载（不作为错误提示）
class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => '已取消';
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
