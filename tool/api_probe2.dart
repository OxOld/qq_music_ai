// 探测「添加歌曲到歌单」的正确模块名（匿名调用，看返回码区分模块存在性）
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
  final candidates = [
    {
      'module': 'music.playlist.PlaylistAddSongList',
      'method': 'AddSongList',
      'param': {
        'dirid': '123456',
        'songlist': [
          {'type': 1, 'mid': '0039MnYb0qxYhV'}
        ],
      },
    },
    {
      'module': 'music.playlist.PlaylistAddSong',
      'method': 'AddSong',
      'param': {
        'dirid': '123456',
        'songlist': [
          {'type': 1, 'mid': '0039MnYb0qxYhV'}
        ],
      },
    },
    {
      'module': 'music.splaylist.addSongList',
      'method': 'addSongList',
      'param': {
        'dirid': '123456',
        'songlist': [
          {'type': 1, 'mid': '0039MnYb0qxYhV'}
        ],
      },
    },
    {
      'module': 'music.playlistFolder.MusicPlaylistFolderAddSongs',
      'method': 'addSongs',
      'param': {
        'disdirid': '123456',
        'songlist': [
          {'type': 1, 'mid': '0039MnYb0qxYhV'}
        ],
      },
    },
  ];
  for (final m in candidates) {
    try {
      final resp = await c.post(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'comm': {'ct': 19, 'cv': 0, 'uin': '0'},
          'req_1': Map.of(m),
        }),
      ).timeout(const Duration(seconds: 15));
      final body = utf8.decode(resp.bodyBytes);
      stdout.writeln('${m['module']} -> ${body.length > 160 ? body.substring(0, 160) : body}');
    } catch (e) {
      stdout.writeln('${m['module']} -> FAILED: $e');
    }
  }
  c.close();
}
