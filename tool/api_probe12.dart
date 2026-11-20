// 探针 12：复现「登录态失效后所有歌都播出同一首」
// 假设：musickey 过期后 CgiGetVkey 不返回空 purl，而是对任意 songmid
// 返回同一个兜底音频 URL（每首歌拼上前缀后完全相同），
// 现有代码只在 purl 为空时判登录失效，于是把兜底 URL 当正常链接缓存+播放。
// 用伪造登录态请求两首不同歌曲，对比 purl 是否相同；同时观察
// midurlinfo 里 songmid/filename 是否还回显请求的歌曲。
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final c = http.Client();
  final baseHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
    'Content-Type': 'application/json',
  };

  // 0) 匿名搜索已被收紧（实测 code 2001 返回空列表），改用网页端
  //    歌曲页 URL 中的已知 mid。两个 mid 即便是同一首歌也不影响对比：
  //    关键是观察不同请求 mid 是否返回同一个 purl、songmid 是否还回显。
  const mid1 = '004OmEt53sLWcn'; // 晴天 - 周杰伦（y.qq.com 歌曲页）
  const mid2 = '0039MnYb0qxYhV'; // 常见开源项目引用的另一晴天 mid
  const name1 = '晴天(004OmEt53sLWcn)';
  const name2 = '晴天(0039MnYb0qxYhV)';
  stdout.writeln('song1: $name1 -> $mid1\nsong2: $name2 -> $mid2');

  // 1) 伪造登录态（模拟 musickey 过期）：假 uin + 假 authst
  Future<void> vkey(String label, String mid,
      {required String uin, required String authst, bool withCookie = true}) async {
    final headers = withCookie
        ? {
            ...baseHeaders,
            'Cookie': 'uin=$uin; qm_keyst=$authst; psrf_qqaccess_token=fake',
          }
        : baseHeaders;
    final resp = await c.post(
      Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      headers: headers,
      body: jsonEncode({
        'comm': {'ct': 19, 'cv': 0, 'uin': uin, 'authst': authst},
        'req_1': {
          'module': 'vkey.GetVkeyServer',
          'method': 'CgiGetVkey',
          'param': {
            'guid': '10000',
            'songmid': [mid],
            'songtype': [0],
            'uin': uin,
            'loginflag': 1,
            'platform': '20',
          },
        },
      }),
    );
    String body;
    try {
      body = utf8.decode(resp.bodyBytes);
    } catch (_) {
      body = latin1.decode(resp.bodyBytes, allowInvalid: true);
    }
    final data = jsonDecode(body);
    final req1 = data['req_1'];
    final code = req1?['code'];
    final info = req1?['data']?['midurlinfo']?[0];
    if (info is Map) {
      final purl = info['purl']?.toString() ?? '';
      stdout.writeln(
          '$label: reqCode=$code songmidEcho=${info['songmid']} '
          'filename=${info['filename']} purl.len=${purl.length} '
          'purl.tail=${purl.length > 60 ? purl.substring(purl.length - 60) : purl}');
      final sip = info['sip'];
      stdout.writeln('    sip=$sip');
    } else {
      stdout.writeln('$label: reqCode=$code midurlinfo 空 body=${body.substring(0, 200)}');
    }
    await Future.delayed(const Duration(milliseconds: 800));
  }

  stdout.writeln('\n===== 1. 伪造登录态（模拟 musickey 过期）=====');
  await vkey('song1(晴天) fake-auth', mid1,
      uin: '123456789', authst: 'Q_H_L_FAKEFAKEFAKEFAKE');
  await vkey('song2(泡沫) fake-auth', mid2,
      uin: '123456789', authst: 'Q_H_L_FAKEFAKEFAKEFAKE');

  // 2) 完全无鉴权（未登录）
  stdout.writeln('\n===== 2. 无 Cookie 无 authst（未登录）=====');
  await vkey('song1(晴天) no-auth', mid1, uin: '', authst: '', withCookie: false);
  await vkey('song2(泡沫) no-auth', mid2, uin: '', authst: '', withCookie: false);

  // 3) 歌单详情：假登录态下 CgiGetDiss 对 disstid=0 和乱 tid 返回什么
  stdout.writeln('\n===== 3. CgiGetDiss 伪造登录态 =====');
  Future<void> diss(String label, Map<String, dynamic> param) async {
    final resp = await c.post(
      Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      headers: {
        ...baseHeaders,
        'Cookie': 'uin=123456789; qm_keyst=Q_H_L_FAKEFAKEFAKEFAKE',
      },
      body: jsonEncode({
        'comm': {
          'ct': 24,
          'cv': 4747474,
          'uin': '123456789',
          'authst': 'Q_H_L_FAKEFAKEFAKEFAKE',
        },
        'req_1': {
          'module': 'music.srfDissInfo.DissInfo',
          'method': 'CgiGetDiss',
          'param': param,
        },
      }),
    );
    String body;
    try {
      body = utf8.decode(resp.bodyBytes);
    } catch (_) {
      body = latin1.decode(resp.bodyBytes, allowInvalid: true);
    }
    final data = jsonDecode(body);
    final req1 = data['req_1'];
    final songlist = req1?['data']?['songlist'];
    final n = songlist is List ? songlist.length : null;
    String? firstName;
    if (songlist is List && songlist.isNotEmpty) {
      firstName = songlist[0]['name']?.toString();
    }
    stdout.writeln('$label: reqCode=${req1?['code']} songNum=$n first=$firstName');
    await Future.delayed(const Duration(milliseconds: 800));
  }

  await diss('disstid=0+dirid=201(我喜欢)', {
    'disstid': 0,
    'dirid': 201,
    'song_begin': 0,
    'song_num': 500,
    'userinfo': true,
    'orderlist': true,
  });
  await diss('disstid=乱值999999999', {
    'disstid': 999999999,
    'song_begin': 0,
    'song_num': 500,
    'userinfo': true,
    'orderlist': true,
  });
  c.close();
}
