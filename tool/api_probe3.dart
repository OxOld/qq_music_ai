// 探测「我的歌单列表」「歌单详情」接口（匿名调用，看模块存在性/返回结构）
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
  const uin = '0';

  // ---- A. musicu 模块候选：我的歌单列表 ----
  stdout.writeln('===== A. my playlist modules =====');
  final modules = [
    {
      'req_1': {
        'module': 'music.splaylist.GetMySPlaylist',
        'method': 'GetMySPlaylist',
        'param': {'uin': uin},
      }
    },
    {
      'req_1': {
        'module': 'music.playlist.PlaylistCollection',
        'method': 'GetPlaylistCollection',
        'param': {'uin': uin},
      }
    },
    {
      'req_1': {
        'module': 'music.userInfo.GetUserPlaylist',
        'method': 'GetUserPlaylist',
        'param': {'uin': uin},
      }
    },
  ];
  for (final m in modules) {
    try {
      final resp = await c.post(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'comm': {'ct': 19, 'cv': 0, 'uin': uin},
          ...m,
        }),
      ).timeout(const Duration(seconds: 15));
      final body = utf8.decode(resp.bodyBytes);
      stdout.writeln(
          '${(m['req_1'] as Map)['module']} -> ${body.length > 150 ? body.substring(0, 150) : body}');
    } catch (e) {
      stdout.writeln('${(m['req_1'] as Map)['module']} -> FAILED: $e');
    }
  }

  // ---- B. 老 CGI：我创建的歌单 ----
  stdout.writeln('===== B. fcg_user_createdlist (anonymous) =====');
  try {
    final resp = await c.get(
      Uri.parse(
          'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_createdlist?ct=24&cv=0&format=json&needNewCode=1&uin=$uin&hostuin=$uin'),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    stdout.writeln('HTTP ${resp.statusCode}: ${body.length > 300 ? body.substring(0, 300) : body}');
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---- C. 歌单详情（老 CGI，用公开歌单测试结构） ----
  stdout.writeln('===== C. getcdinfo (anonymous, public playlist) =====');
  try {
    final resp = await c.get(
      Uri.parse(
          'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_iids_formate.cgi?type=1&json=1&utf8=1&onlysong=0&disstid=9035034294&format=json&uin=$uin'),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    stdout.writeln('HTTP ${resp.statusCode}: ${body.length > 400 ? body.substring(0, 400) : body}');
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---- D. musicu 歌单详情模块 ----
  stdout.writeln('===== D. musicu playlist detail modules =====');
  final detailModules = [
    {
      'req_1': {
        'module': 'music.splaylist.GetPlaylistByDirid',
        'method': 'GetPlaylistByDirid',
        'param': {'dirid': 9035034294, 'uin': uin},
      }
    },
    {
      'req_1': {
        'module': 'music.playlist.PlaylistDetail',
        'method': 'GetPlaylistDetail',
        'param': {'dirid': 9035034294, 'uin': uin},
      }
    },
  ];
  for (final m in detailModules) {
    try {
      final resp = await c.post(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'comm': {'ct': 19, 'cv': 0, 'uin': uin},
          ...m,
        }),
      ).timeout(const Duration(seconds: 15));
      final body = utf8.decode(resp.bodyBytes);
      stdout.writeln(
          '${(m['req_1'] as Map)['module']} -> ${body.length > 200 ? body.substring(0, 200) : body}');
    } catch (e) {
      stdout.writeln('${(m['req_1'] as Map)['module']} -> FAILED: $e');
    }
  }

  c.close();
}
