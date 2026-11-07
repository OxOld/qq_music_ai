// 探针 11：改名参数形状 + 老接口
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
  var hash = 5381;
  for (final ch in keyst.codeUnits) {
    hash += (hash << 5) + ch;
  }
  final gtk = hash & 0x7fffffff;

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

  Future<void> show(String label, http.Response resp) async {
    String body;
    try {
      body = utf8.decode(resp.bodyBytes);
    } catch (_) {
      body = latin1.decode(resp.bodyBytes, allowInvalid: true);
    }
    stdout.writeln(
        '$label -> HTTP ${resp.statusCode}: ${body.length > 300 ? body.substring(0, 300) : body}');
  }

  // ---------- A. UpdatePlaylist 全字段 ----------
  stdout.writeln('===== A. UpdatePlaylist full fields =====');
  try {
    final resp = await c
        .post(
          Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
          headers: headers,
          body: jsonEncode({
            'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
            'req_1': {
              'module': 'music.musicasset.PlaylistBaseWrite',
              'method': 'UpdatePlaylist',
              'param': {
                'dirId': 7,
                'dirName': 'AI测试改名_7',
                'dirDesc': '',
                'dirPicUrl': '',
                'taglist': '',
                'dirShow': 2,
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 15));
    await show('A', resp);
  } catch (e) {
    stdout.writeln('A FAILED: $e');
  }

  // ---------- B. UpdatePlaylist 用 tid ----------
  stdout.writeln('\n===== B. UpdatePlaylist with tid =====');
  try {
    final resp = await c
        .post(
          Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
          headers: headers,
          body: jsonEncode({
            'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
            'req_1': {
              'module': 'music.musicasset.PlaylistBaseWrite',
              'method': 'UpdatePlaylist',
              'param': {
                'tid': 9804063993,
                'dirName': 'AI测试改名_7b',
                'dirDesc': '',
                'dirPicUrl': '',
                'taglist': '',
                'dirShow': 2,
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 15));
    await show('B', resp);
  } catch (e) {
    stdout.writeln('B FAILED: $e');
  }

  // ---------- C. 老 qzone 改名接口 ----------
  stdout.writeln('\n===== C. qzone fcg_ucc_renamecd =====');
  try {
    final resp = await c.get(
      Uri.parse(
        'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_renamecd.fcg'
        '?dirid=7&dirname=AI%E6%B5%8B%E8%AF%95%E6%94%B9%E5%90%8D_7c'
        '&uin=$uin&hostuin=$uin&g_tk=$gtk&loginUin=$uin'
        '&format=json&inCharset=utf8&outCharset=utf-8&notice=0'
        '&platform=yqq.json&needNewCode=0',
      ),
      headers: {
        'User-Agent': headers['User-Agent']!,
        'Referer': 'https://y.qq.com/portal/profile.html',
        'Cookie': cookie,
      },
    ).timeout(const Duration(seconds: 15));
    await show('C', resp);
  } catch (e) {
    stdout.writeln('C FAILED: $e');
  }

  // ---------- D. musicu PlaylistDetailWrite / UpdateDirName 候选 ----------
  stdout.writeln('\n===== D. more method candidates =====');
  final candidates = [
    ('music.musicasset.PlaylistBaseWrite', 'ModifyPlaylistBase', {
      'dirId': 7,
      'dirName': 'AI测试改名_7d',
    }),
    ('music.musicasset.PlaylistWrite', 'UpdatePlaylist', {
      'dirId': 7,
      'dirName': 'AI测试改名_7e',
    }),
  ];
  for (final (module, method, param) in candidates) {
    try {
      final resp = await c
          .post(
            Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
            headers: headers,
            body: jsonEncode({
              'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
              'req_1': {'module': module, 'method': method, 'param': param},
            }),
          )
          .timeout(const Duration(seconds: 15));
      await show('$module/$method', resp);
    } catch (e) {
      stdout.writeln('$module/$method FAILED: $e');
    }
  }

  c.close();
}
