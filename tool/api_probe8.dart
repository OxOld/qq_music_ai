// 探针 8：按参考实现的确切参数调用歌单列表
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
  final profileHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://y.qq.com/portal/profile.html',
    'Cookie': cookie,
  };
  final c = http.Client();

  // ---------- 1. 创建的歌单 ----------
  stdout.writeln('===== 1. fcg_user_created_diss (exact params) =====');
  try {
    final resp = await c.get(
      Uri.parse(
        'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss'
        '?hostUin=0&hostuin=$uin&sin=0&size=200&g_tk=5381&loginUin=$uin'
        '&format=json&inCharset=utf8&outCharset=utf-8&notice=0'
        '&platform=yqq.json&needNewCode=0',
      ),
      headers: profileHeaders,
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final disslist = data['data']?['disslist'];
    stdout.writeln('totoal=${data['data']?['totoal']} '
        'list=${disslist is List ? disslist.length : 'N/A'}');
    if (disslist is List) {
      if (disslist.isNotEmpty) {
        stdout.writeln('ITEM0: ${jsonEncode(disslist.first).length > 800 ? jsonEncode(disslist.first).substring(0, 800) : jsonEncode(disslist.first)}');
      }
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  // ---------- 2. 收藏的歌单 ----------
  stdout.writeln('\n===== 2. fcg_get_profile_order_asset (fav path) =====');
  try {
    final resp = await c.get(
      Uri.parse(
        'https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg'
        '?ct=20&cid=205360956&userid=$uin&reqtype=3&sin=0&ein=80'
        '&format=json&inCharset=utf8&outCharset=utf-8&notice=0'
        '&platform=yqq.json&needNewCode=0&g_tk=5381&loginUin=$uin'
        '&hostUin=0&uin=$uin',
      ),
      headers: profileHeaders,
    ).timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    final data = jsonDecode(body);
    final cdlist = data['data']?['cdlist'];
    stdout.writeln('cdlist=${cdlist is List ? cdlist.length : 'N/A'}');
    if (cdlist is List) {
      if (cdlist.isNotEmpty) {
        stdout.writeln('ITEM0: ${jsonEncode(cdlist.first).length > 800 ? jsonEncode(cdlist.first).substring(0, 800) : jsonEncode(cdlist.first)}');
      }
    }
  } catch (e) {
    stdout.writeln('FAILED: $e');
  }

  c.close();
}
