// 诊断探针：直接测试 QQ 音乐各接口的真实响应
// 运行: flutter 的 dart run tool/api_probe.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const headers = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Referer': 'https://y.qq.com/',
  'Origin': 'https://y.qq.com',
};

Future<void> main() async {
  final c = http.Client();

  // ---------- 1. 搜索接口（匹配用） ----------
  stdout.writeln('===== 1. search API x3 (连续调用看限流) =====');
  for (var i = 0; i < 3; i++) {
    try {
      final sw = DateTime.now();
      final resp = await c.post(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'comm': {'ct': 19, 'cv': 0, 'uin': '0'},
          'req_1': {
            'module': 'music.search.SearchCgiService',
            'method': 'DoSearchForQQMusicDesktop',
            'param': {
              'query': '晴天 周杰伦',
              'num_per_page': 5,
              'page_num': 1,
              'search_type': 0,
              'grp': 1,
            },
          },
        }),
      ).timeout(const Duration(seconds: 15));
      final ms = DateTime.now().difference(sw).inMilliseconds;
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = data['req_1']?['data']?['body']?['song']?['list'];
      final code = data['req_1']?['code'];
      final first = list is List && list.isNotEmpty
          ? '${list.first['name']} - ${list.first['singer'][0]['name']}'
          : '(empty)';
      stdout.writeln('[$i] HTTP ${resp.statusCode}, code=$code, ${ms}ms, first: $first');
    } catch (e) {
      stdout.writeln('[$i] FAILED: $e');
    }
  }

  // ---------- 2. vkey 播放链接（匿名） ----------
  stdout.writeln('===== 2. vkey play URL (anonymous) =====');
  String? playUrl;
  try {
    final resp = await c.post(
      Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'comm': {'ct': 19, 'cv': 0, 'uin': '0'},
        'req_1': {
          'module': 'vkey.GetVkeyServer',
          'method': 'CgiGetVkey',
          'param': {
            'guid': '10000',
            'songmid': ['0039MnYb0qxYhV'], // 晴天
            'songtype': [0],
            'uin': '0',
            'loginflag': 1,
            'platform': '20',
          },
        },
      }),
    ).timeout(const Duration(seconds: 15));
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final info = data['req_1']?['data']?['midurlinfo']?[0];
    final sip = data['req_1']?['data']?['sip'];
    stdout.writeln('sip: $sip');
    stdout.writeln('purl: ${info?['purl']}');
    if (info?['purl'] != null && info['purl'].toString().isNotEmpty) {
      final prefix = sip is List && sip.isNotEmpty ? sip.first.toString() : '';
      playUrl = '$prefix${info['purl']}';
      stdout.writeln('full: $playUrl');
      // 测试 https 替换是否可行
      if (playUrl.startsWith('http://')) {
        final httpsUrl = playUrl.replaceFirst('http://', 'https://');
        try {
          final head = await c.head(Uri.parse(httpsUrl),
              headers: headers).timeout(const Duration(seconds: 10));
          stdout.writeln('HTTPS HEAD: ${head.statusCode}');
        } catch (e) {
          stdout.writeln('HTTPS HEAD FAILED: $e');
        }
        final httpResp = await c.head(Uri.parse(playUrl), headers: headers)
            .timeout(const Duration(seconds: 10));
        stdout.writeln('HTTP HEAD: ${httpResp.statusCode}');
      }
    }
  } catch (e) {
    stdout.writeln('vkey FAILED: $e');
  }

  // ---------- 3. 创建歌单模块名探测（匿名，预期"需要登录"而非"模块不存在"） ----------
  stdout.writeln('===== 3. create playlist module probe =====');
  final candidates = [
    {'module': 'music.playlist.PlaylistCreate', 'method': 'CreatePlaylist'},
    {'module': 'playlist.PlaylistCreate', 'method': 'CreatePlaylist'},
    {'module': 'music.playlistFolder.PlaylistFolderCreate',
     'method': 'createFolder'},
  ];
  for (final m in candidates) {
    try {
      final resp = await c.post(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'comm': {'ct': 19, 'cv': 0, 'uin': '0'},
          'req_1': {
            ...m,
            'param': {'title': 'probe', 'direction': 1, 'cover': 0,
              'comment': '', 'list': [], 'uncategorized': 0, 'orderlist': []},
          },
        }),
      ).timeout(const Duration(seconds: 15));
      final body = utf8.decode(resp.bodyBytes);
      stdout.writeln('${m['module']} -> HTTP ${resp.statusCode}: '
          '${body.length > 200 ? body.substring(0, 200) : body}');
    } catch (e) {
      stdout.writeln('${m['module']} -> FAILED: $e');
    }
  }

  c.close();
}
