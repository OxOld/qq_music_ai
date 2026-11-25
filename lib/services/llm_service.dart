import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/playlist.dart';
import 'settings_service.dart';

/// LLM 调用服务（OpenAI 兼容协议，直连无后端）
class LlmService {
  /// 歌单生成的固定规则段
  ///
  /// 由代码维护（JSON 结构与字段规范），调用时拼在用户可编辑前缀之后；
  /// 用户在设置页只能改前缀，无法破坏这里的解析格式。
  static const generateFixedTail =
      '''必须严格只返回一个 JSON 对象，不要包含任何 JSON 之外的文字、解释、markdown 代码块标记（不要用 ``` 包裹）。JSON 结构如下：
{
  "title": "歌单标题（简洁、有吸引力）",
  "description": "一句话描述歌单风格",
  "songs": [
    {"name": "歌曲名", "artist": "歌手名"}
  ]
}

要求：
1. 歌曲数量遵循用户要求；若未指定，默认 20 首。
2. 只返回真实存在、广为流传的歌曲，歌手名要准确。
3. name 字段只写歌曲名，artist 字段只写歌手名，不要附带专辑名、年份或其它信息。
4. 避免过于小众或已下架的歌曲。
''';

  /// 补歌推荐的固定规则段（同上，由代码维护）
  static const suggestFixedTail =
      '''必须严格只返回一个 JSON 对象，不要包含任何 JSON 之外的文字、解释、markdown 代码块标记（不要用 ``` 包裹）。JSON 结构如下：
{
  "songs": [
    {"name": "歌曲名", "artist": "歌手名"}
  ]
}

要求：
1. 推荐歌曲绝对不能与"已有歌曲"重复（歌名相同即视为重复）。
2. 数量遵循用户要求，默认 10 首。
3. 只返回真实存在、广为流传的歌曲，歌手名要准确。
4. name 字段只写歌曲名，artist 字段只写歌手名，不要附带专辑名、年份或其它信息。
5. 避免过于小众或已下架的歌曲。
''';

  /// 拼接 system 提示词：可编辑前缀（空则忽略）+ 固定规则段
  static String composeSystemPrompt(String? prefix, String fixedTail) {
    final editable = (prefix ?? '').trim();
    return editable.isEmpty ? fixedTail : '$editable\n\n$fixedTail';
  }

  /// 根据用户输入生成歌单
  ///
  /// [promptPrefix] 为设置页配置的可编辑前缀（角色/风格/额外要求），
  /// 为空时只用固定规则段。
  Future<Playlist> generatePlaylist(
    LlmConfig config,
    String userInput, {
    String? promptPrefix,
  }) async {
    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');

    final resp = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey.trim()}',
          },
          body: jsonEncode({
            'model': config.model.trim(),
            'messages': [
              {
                'role': 'system',
                'content': composeSystemPrompt(promptPrefix, generateFixedTail),
              },
              {'role': 'user', 'content': userInput.trim()},
            ],
            'response_format': {'type': 'json_object'},
            'temperature': 0.7,
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (resp.statusCode != 200) {
      throw LlmException('请求失败 (${resp.statusCode})：${_truncate(resp.body)}');
    }

    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const LlmException('LLM 返回格式异常');
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmException('LLM 返回为空（无 choices）');
    }

    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content']?.toString() : null;
    if (content == null || content.isEmpty) {
      throw const LlmException('LLM 返回内容为空');
    }

    return Playlist.fromJson(_extractJson(content));
  }

  /// 根据现有歌单推荐一批未收录的新歌（风格延续、不与已有歌曲重复）。
  /// [exclude] 为上一批已推荐过的歌名，用于「换一批」时排除；
  /// [promptPrefix] 为设置页配置的可编辑前缀（空则只用固定规则段）
  Future<List<Song>> suggestSongsForPlaylist(
    LlmConfig config, {
    required String playlistName,
    required List<Song> existing,
    int count = 10,
    List<String> exclude = const [],
    String? promptPrefix,
  }) async {
    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');

    final existingLines = existing.isEmpty
        ? '（空歌单，自由发挥）'
        : existing.map((s) => '- ${s.name} - ${s.artist}').join('\n');
    final excludeLines = exclude.isEmpty
        ? ''
        : '\n另外，之前已经推荐过以下歌曲，也请不要再推荐：\n'
              '${exclude.map((n) => '- $n').join('\n')}';
    final userInput =
        '歌单名称：$playlistName\n已有歌曲：\n$existingLines$excludeLines\n\n'
        '请推荐 $count 首适合补充进这份歌单的新歌。';

    final resp = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey.trim()}',
          },
          body: jsonEncode({
            'model': config.model.trim(),
            'messages': [
              {
                'role': 'system',
                'content': composeSystemPrompt(promptPrefix, suggestFixedTail),
              },
              {'role': 'user', 'content': userInput},
            ],
            'response_format': {'type': 'json_object'},
            'temperature': 0.8,
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (resp.statusCode != 200) {
      throw LlmException('请求失败 (${resp.statusCode})：${_truncate(resp.body)}');
    }

    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const LlmException('LLM 返回格式异常');
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmException('LLM 返回为空（无 choices）');
    }

    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content']?.toString() : null;
    if (content == null || content.isEmpty) {
      throw const LlmException('LLM 返回内容为空');
    }

    final jsonMap = _extractJson(content);
    final rawSongs = jsonMap['songs'];
    if (rawSongs is! List) {
      throw const LlmException('LLM 返回缺少 songs 列表');
    }

    // 双保险：LLM 可能仍推荐了已收录/已推荐过的歌，本地按歌名过滤
    final known = {
      ...existing.map((s) => s.name.toLowerCase()),
      ...exclude.map((n) => n.toLowerCase()),
    };
    final out = <Song>[];
    for (final item in rawSongs) {
      if (item is! Map) continue;
      final song = Song.fromJson(Map<String, dynamic>.from(item));
      if (song.name.isEmpty) continue;
      if (known.contains(song.name.toLowerCase())) continue;
      out.add(song);
    }
    return out;
  }

  /// 从 LLM 返回文本中稳健提取 JSON 对象
  Map<String, dynamic> _extractJson(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}

    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(content.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }

    throw const LlmException('无法解析 LLM 返回的 JSON');
  }

  String _truncate(String s) {
    return s.length > 300 ? '${s.substring(0, 300)}…' : s;
  }
}

class LlmException implements Exception {
  final String message;
  const LlmException(this.message);

  @override
  String toString() => message;
}
