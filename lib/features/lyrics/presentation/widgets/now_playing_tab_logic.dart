part of 'now_playing_tab.dart';

extension _NowPlayingTabLogic on _NowPlayingTabState {
  Future<void> _openInSpotify() async {
    widget.controller.setPreferredMediaAppPackage(_NowPlayingTabState._spotifyPackage);
    final query = _defaultMusicQuery();
    final uri = query.isEmpty
        ? Uri.https('open.spotify.com', '/')
        : Uri.https('open.spotify.com', '/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openArtistInSpotify() async {
    widget.controller.setPreferredMediaAppPackage(_NowPlayingTabState._spotifyPackage);
    final query = _artistOnlyQuery();
    final uri = query.isEmpty
        ? Uri.https('open.spotify.com', '/')
        : Uri.https('open.spotify.com', '/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInYouTubeMusic() async {
    widget.controller.setPreferredMediaAppPackage(_NowPlayingTabState._youtubeMusicPackage);
    final query = _defaultMusicQuery();
    final uri = query.isEmpty
        ? Uri.https('music.youtube.com', '/')
        : Uri.https('music.youtube.com', '/search', {'q': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openArtistInYouTubeMusic() async {
    widget.controller.setPreferredMediaAppPackage(_NowPlayingTabState._youtubeMusicPackage);
    final query = _artistOnlyQuery();
    final uri = query.isEmpty
        ? Uri.https('music.youtube.com', '/')
        : Uri.https('music.youtube.com', '/search', {'q': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInAmazonMusic() async {
    widget.controller.setPreferredMediaAppPackage(_NowPlayingTabState._amazonMusicPackage);
    final query = _defaultMusicQuery();
    final uri = query.isEmpty
        ? Uri.https('music.amazon.com', '/')
        : Uri.https('music.amazon.com', '/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openArtistInAmazonMusic() async {
    widget.controller.setPreferredMediaAppPackage(_NowPlayingTabState._amazonMusicPackage);
    final query = _artistOnlyQuery();
    final uri = query.isEmpty
        ? Uri.https('music.amazon.com', '/')
        : Uri.https('music.amazon.com', '/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInAppleMusic() async {
    widget.controller.setPreferredMediaAppPackage(_NowPlayingTabState._appleMusicPackage);
    final query = _defaultMusicQuery();
    final uri = query.isEmpty
        ? Uri.https('music.apple.com', '/')
        : Uri.https('music.apple.com', '/us/search', {'term': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openArtistInAppleMusic() async {
    widget.controller.setPreferredMediaAppPackage(_NowPlayingTabState._appleMusicPackage);
    final query = _artistOnlyQuery();
    final uri = query.isEmpty
        ? Uri.https('music.apple.com', '/')
        : Uri.https('music.apple.com', '/us/search', {'term': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _defaultMusicQuery() {
    final l10n = AppLocalizations.of(context);
    final hasDetectedSong = widget.controller.hasActiveNowPlaying &&
        widget.controller.songTitle.trim().isNotEmpty &&
        widget.controller.songTitle.trim() != l10n.nowPlayingDefaultTitle;
    if (!hasDetectedSong) {
      return '';
    }

    final typedQuery = widget.controller.searchQuery.trim();
    return typedQuery.isNotEmpty
        ? typedQuery
        : '${widget.controller.songTitle} ${widget.controller.artistName}'.trim();
  }

  String _artistOnlyQuery() {
    final l10n = AppLocalizations.of(context);
    if (!widget.controller.hasActiveNowPlaying) {
      return '';
    }

    final artist = widget.controller.artistName.trim();
    if (artist.isNotEmpty && artist != l10n.unknownArtist) {
      return artist;
    }

    return _defaultMusicQuery();
  }
}
