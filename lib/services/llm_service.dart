import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/playlist.dart';
import 'settings_service.dart';

/// LLM 调用服务（OpenAI 兼容协议，直连无后端）
class LlmService {
  static const _systemPrompt = '''
你是一位专业的音乐策展人。请根据用户描述的场景、情绪、曲风、语言、年代等需求，生成一份精选歌单。

必须严格只返回一个 JSON 对象，不要包含任何 JSON 之外的文字、解释、markdown 代码块标记（不要用 ``` 包裹）。JSON 结构如下：
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

  /// 根据用户输入生成歌单
  Future<Playlist> generatePlaylist(
    LlmConfig config,
    String userInput,
  ) async {
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
              {'role': 'system', 'content': _systemPrompt},
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
