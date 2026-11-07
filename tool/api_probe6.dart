// 探针 6：用户歌单列表模块（带登录态）+ 新建歌单的歌曲列表
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
  };
  final c = http.Client();
  Future<String> dump(http.Response resp) {
    try {
      return Future.value(utf8.decode(resp.bodyBytes));
    } catch (_) {
      return Future.value(latin1.decode(resp.bodyBytes, allowInvalid: true));
    }
  }

  // ---------- 1. 用户歌单列表候选（带登录态） ----------
  final candidates = [
    ('music.splaylist.GetMySPlaylist', 'GetMySPlaylist', {
      'uin': uin,
    }),
    ('music.userInfo.GetUserPlaylist', 'GetUserPlaylist', {
      'uin': uin,
    }),
    ('music.splaylist.GetPlaylistByUin', 'GetPlaylistByUin', {
      'uin': uin,
    }),
    ('music.playlist.PlaylistCollection', 'GetPlaylistCollection', {
      'uin': uin,
    }),
  ];
  for (final (module, method, param) in candidates) {
    stdout.writeln('\n===== $module =====');
    try {
      final resp = await c.post(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
          'req_1': {'module': module, 'method': method, 'param': param},
        }),
      ).timeout(const Duration(seconds: 15));
      final body = await dump(resp);
      stdout.writeln(
          body.length > 350 ? body.substring(0, 350) : body);
    } catch (e) {
      stdout.writeln('FAILED: $e');
    }
  }

  // ---------- 2. 老接口 POST 形式 ----------
  stdout.writeln('\n===== fcg_user_created_diss as POST =====');
  try {
    final resp = await c.post(
      Uri.parse(
          'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss?cv=4747474&ct=24&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0'),
      headers: headers,
      body: {
        'uin': uin,
        'hostuin': uin,
        'pagenum': '0',
        'pagesize': '100',
        'sortType': '1',
      },
    ).timeout(const Duration(seconds: 15));
    final body = await dump(resp);
    stdout.writeln(body.length > 400 ? body.substring(0, 400) : body);
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- 3. 新建歌单 tid=9804064150 的歌曲列表 ----------
  stdout.writeln('\n===== CgiGetDiss disstid=9804064150 =====');
  try {
    final resp = await c.post(
      Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'comm': {'ct': 24, 'cv': 4747474, 'uin': uin, 'authst': keyst},
        'req_1': {
          'module': 'music.srfDissInfo.DissInfo',
          'method': 'CgiGetDiss',
          'param': {
            'disstid': 9804064150,
            'song_begin': 0,
            'song_num': 50,
            'userinfo': true,
            'orderlist': true,
          },
        },
      }),
    ).timeout(const Duration(seconds: 15));
    final body = await dump(resp);
    final data = jsonDecode(body);
    final req = data['req_1'];
    final dirinfo = req?['data']?['dirinfo'];
    final songlist = req?['data']?['songlist'];
    stdout.writeln('code=${req?['code']} title=${dirinfo?['title']} '
        'songs=${songlist is List ? songlist.length : 0}');
    if (songlist is List && songlist.isNotEmpty) {
      stdout.writeln('  first: ${songlist.first['name']} '
          'mid=${songlist.first['mid']} id=${songlist.first['id']}');
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  c.close();
}
