// 探针 10：改名候选模块实测 + 删除歌单验证（作用于测试歌单 dirId=8）
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final cookie = File('tool/test_cookie.txt').readAsStringSync().trim();
  String extract(String key) {
    for (final part in cookie.split(';')) {
      final t = part.trim();
      final eq = t.indexOf('=');
      if (eq > 0 && t.substring(0, eq) == key) return t.substring(eq + 1);
    }
    return '';
  }

  final uin = extract('uin');
  final keyst = extract('qm_keyst');

  final headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
    'Cookie': cookie,
    'Content-Type': 'application/json',
  };
  final c = http.Client();

  Future<Map<String, dynamic>> musicu(
      String module, String method, Map<String, dynamic> param) async {
    final resp = await c
        .post(
          Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
          headers: headers,
          body: jsonEncode({
            'comm': {
              'ct': 24,
              'cv': 4747474,
              'uin': uin,
              'authst': keyst,
            },
            'req_1': {'module': module, 'method': method, 'param': param},
          }),
        )
        .timeout(const Duration(seconds: 15));
    String body;
    try {
      body = utf8.decode(resp.bodyBytes);
    } catch (_) {
      body = latin1.decode(resp.bodyBytes, allowInvalid: true);
    }
    return jsonDecode(body)['req_1'] as Map<String, dynamic>? ?? {};
  }

  const dirId = 8;

  // ---------- 1. 改名候选 ----------
  stdout.writeln('===== rename candidates on dirId=$dirId =====');
  final renameCandidates = [
    ('UpdatePlaylist', {
      'dirId': dirId,
      'dirName': '改名测试_OK',
    }),
    ('ModifyPlaylist', {
      'dirId': dirId,
      'dirName': '改名测试_OK',
    }),
    ('RenamePlaylist', {
      'dirId': dirId,
      'dirName': '改名测试_OK',
    }),
    ('UpdatePlaylistBase', {
      'dirId': dirId,
      'dirName': '改名测试_OK',
    }),
    ('SetPlaylistInfo', {
      'dirId': dirId,
      'dirName': '改名测试_OK',
    }),
  ];
  String? workingRename;
  for (final (method, param) in renameCandidates) {
    final req = await musicu(
        'music.musicasset.PlaylistBaseWrite', method, param);
    stdout.writeln(
        '$method -> code=${req['code']} retCode=${req['data']?['retCode']} '
        'msg=${req['data']?['msg'] ?? req['data']?['result']?['msg'] ?? ''}');
    if (req['code'] == 0 && req['data']?['retCode'] == 0) {
      workingRename = method;
      stdout.writeln('  >>> WORKS');
      break;
    }
  }
  stdout.writeln('working rename: $workingRename');

  // ---------- 2. 删除歌单 ----------
  stdout.writeln('\n===== DelPlaylist dirId=$dirId =====');
  final del = await musicu('music.musicasset.PlaylistBaseWrite',
      'DelPlaylist', {'dirId': dirId});
  stdout.writeln(
      'code=${del['code']} retCode=${del['data']?['retCode']} data=${jsonEncode(del['data'] ?? {}).length > 200 ? '' : jsonEncode(del['data'] ?? {})}');

  // ---------- 3. 验证已删除（创建列表里应无 dirid=8） ----------
  stdout.writeln('\n===== verify via created list =====');
  final resp = await c.get(
    Uri.parse(
      'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss'
      '?hostUin=0&hostuin=$uin&sin=0&size=200&g_tk=5381&loginUin=$uin'
      '&format=json&inCharset=utf8&outCharset=utf-8&notice=0'
      '&platform=yqq.json&needNewCode=0',
    ),
    headers: {
      'User-Agent': headers['User-Agent']!,
      'Referer': 'https://y.qq.com/portal/profile.html',
      'Cookie': cookie,
    },
  ).timeout(const Duration(seconds: 15));
  final data = jsonDecode(utf8.decode(resp.bodyBytes));
  final list = data['data']?['disslist'] as List?;
  if (list != null) {
    for (final d in list) {
      stdout.writeln(
          '  - dirid=${d['dirid']} tid=${d['tid']} name=${d['diss_name']}');
    }
  }

  c.close();
}
