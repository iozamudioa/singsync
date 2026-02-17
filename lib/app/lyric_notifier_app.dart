import 'package:flutter/material.dart';

import '../features/lyrics/data/local_song_cache_repository.dart';
import '../features/lyrics/data/platform_lyrics_gateway.dart';
import '../features/lyrics/data/platform_music_metadata_search_adapter.dart';
import '../features/lyrics/presentation/lyrics_controller.dart';
import '../features/lyrics/presentation/lyrics_home_screen.dart';
import 'theme_controller.dart';

class LyricNotifierApp extends StatefulWidget {
  const LyricNotifierApp({super.key});

  @override
  State<LyricNotifierApp> createState() => _LyricNotifierAppState();
}

class _LyricNotifierAppState extends State<LyricNotifierApp> {
  late final ThemeController _themeController;
  late final LyricsController _lyricsController;
  late final LocalSongCacheRepository _songCacheRepository;

  @override
  void initState() {
    super.initState();
    _themeController = ThemeController();
    _songCacheRepository = LocalSongCacheRepository();
    _lyricsController = LyricsController(
      gateway: PlatformLyricsGateway(),
      metadataSearchPort: PlatformMusicMetadataSearchAdapter(),
      songCache: _songCacheRepository,
    )..start();
  }

  @override
  void dispose() {
    _lyricsController.dispose();
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Lyric Notifier',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: _themeController.themeMode,
          home: LyricsHomeScreen(
            themeController: _themeController,
            controller: _lyricsController,
          ),
        );
      },
    );
  }
}
