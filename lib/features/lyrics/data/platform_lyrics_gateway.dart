import 'package:flutter/services.dart';

import '../domain/lyrics_candidate.dart';
import '../domain/lyrics_lookup_result.dart';

class PlatformLyricsGateway {
  static const EventChannel _nowPlayingChannel = EventChannel(
    'net.iozamudioa.singsync/now_playing',
  );
  static const MethodChannel _nowPlayingMethodsChannel = MethodChannel(
    'net.iozamudioa.singsync/now_playing_methods',
  );
  static const MethodChannel _lyricsMethodsChannel = MethodChannel(
    'net.iozamudioa.singsync/lyrics',
  );

  Stream<dynamic> nowPlayingStream() {
    return _nowPlayingChannel.receiveBroadcastStream();
  }

  Future<Map<dynamic, dynamic>?> getCurrentNowPlaying() async {
    final payload = await _nowPlayingMethodsChannel.invokeMethod<dynamic>('getCurrentNowPlaying');
    if (payload is Map) {
      return payload;
    }
    return null;
  }

  Future<bool> isNotificationListenerEnabled() async {
    final enabled = await _nowPlayingMethodsChannel.invokeMethod<dynamic>('isNotificationListenerEnabled');
    return enabled == true;
  }

  Future<void> openNotificationListenerSettings() async {
    await _nowPlayingMethodsChannel.invokeMethod<dynamic>('openNotificationListenerSettings');
  }

  Future<bool> openActivePlayer({
    String? sourcePackage,
    String? selectedPackage,
    String? searchQuery,
  }) async {
    final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
      'openActivePlayer',
      {
        'sourcePackage': sourcePackage,
        'selectedPackage': selectedPackage,
        'searchQuery': searchQuery,
      },
    );
    return response == true;
  }

  Future<bool> mediaPrevious({String? sourcePackage}) async {
    final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
      'mediaPrevious',
      {
        'sourcePackage': sourcePackage,
      },
    );
    return response == true;
  }

  Future<bool> mediaPlayPause({String? sourcePackage}) async {
    final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
      'mediaPlayPause',
      {
        'sourcePackage': sourcePackage,
      },
    );
    return response == true;
  }

  Future<bool> mediaNext({String? sourcePackage}) async {
    final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
      'mediaNext',
      {
        'sourcePackage': sourcePackage,
      },
    );
    return response == true;
  }

  Future<bool> mediaSeekTo({
    required int positionMs,
    String? sourcePackage,
  }) async {
    final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
      'mediaSeekTo',
      {
        'sourcePackage': sourcePackage,
        'positionMs': positionMs,
      },
    );
    return response == true;
  }

  Future<Map<String, dynamic>?> getMediaPlaybackState({String? sourcePackage}) async {
    final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
      'getMediaPlaybackState',
      {
        'sourcePackage': sourcePackage,
      },
    );

    if (response is! Map) {
      return null;
    }

    return response.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<Map<String, dynamic>?> getActiveSessionSnapshot({String? sourcePackage}) async {
    final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
      'getActiveSessionSnapshot',
      {
        'sourcePackage': sourcePackage,
      },
    );

    if (response is! Map) {
      return null;
    }

    return response.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<Set<String>> getInstalledMediaApps({required List<String> packages}) async {
    final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
      'getInstalledMediaApps',
      {
        'packages': packages,
      },
    );

    if (response is! List) {
      return <String>{};
    }

    return response
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  Future<LyricsLookupResult> fetchLyrics({
    required String title,
    required String artist,
    required bool preferSynced,
  }) async {
    final response = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'fetchLyrics',
      {
        'title': title,
        'artist': artist,
        'preferSynced': preferSynced,
      },
    );

    if (response is! Map) {
      return const LyricsLookupResult(lyrics: '', debugSteps: []);
    }

    final dynamic debug = response['debug'];
    final debugSteps = <String>[];
    if (debug is List) {
      for (final step in debug) {
        debugSteps.add(step.toString());
      }
    }

    final lyrics = (response['lyrics'] ?? '').toString();
    final metadataRaw = response['metadata'];
    Map<String, dynamic>? metadata;
    if (metadataRaw is Map) {
      metadata = metadataRaw.map((key, value) => MapEntry(key.toString(), value));
    }

    return LyricsLookupResult(
      lyrics: lyrics,
      debugSteps: debugSteps,
      metadata: metadata,
    );
  }

  Future<List<LyricsCandidate>> searchLyricsCandidates({
    required String query,
  }) async {
    final response = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'searchLyricsCandidates',
      {
        'query': query,
      },
    );

    if (response is! List) {
      return const [];
    }

    final candidates = <LyricsCandidate>[];
    for (final item in response) {
      if (item is Map) {
        final candidate = LyricsCandidate.fromMap(item);
        if (candidate.trackName.isNotEmpty &&
            candidate.artistName.isNotEmpty &&
            candidate.lyrics.isNotEmpty) {
          candidates.add(candidate);
        }
      }
    }
    return candidates;
  }
}
