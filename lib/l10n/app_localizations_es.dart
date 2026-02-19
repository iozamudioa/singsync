// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Lyric Notifier';

  @override
  String get nowPlayingDefaultTitle => 'Now Playing';

  @override
  String get unknownArtist => 'Artista desconocido';

  @override
  String get artistLabel => 'Artista';

  @override
  String get motivationStartPlayback =>
      'Pon tu canción favorita y empezamos 🎵';

  @override
  String get permissionNeededTitle => 'Permiso necesario';

  @override
  String get permissionDialogMessage =>
      'SingSync necesita acceso a notificaciones para detectar la canción actual y buscar su letra automáticamente.';

  @override
  String get notNow => 'Ahora no';

  @override
  String get goToPermissions => 'Ir a permisos';

  @override
  String get enableNotificationsCard =>
      'Activa acceso a notificaciones para detectar canciones.';

  @override
  String get allow => 'Permitir';

  @override
  String get close => 'Cerrar';

  @override
  String get developerBy => 'Developer by: iozamudioa';

  @override
  String get githubLabel => 'Github:';

  @override
  String versionLabel(Object version) {
    return 'Version: $version';
  }

  @override
  String get poweredByLrclib => 'Powered by: LRCLIB';

  @override
  String get useArtworkBackground => 'Usar carátula como fondo';

  @override
  String get useSolidBackgroundDescription =>
      'Si se desactiva, se usa fondo sólido según el tema.';

  @override
  String get infoTooltip => 'Información';

  @override
  String get switchToLightMode => 'Cambiar a modo claro';

  @override
  String get switchToDarkMode => 'Cambiar a modo oscuro';

  @override
  String get openActivePlayer => 'Abrir reproductor activo';

  @override
  String get previous => 'Anterior';

  @override
  String get playPause => 'Play/Pause';

  @override
  String get next => 'Siguiente';

  @override
  String get searchManually => 'Buscar manualmente';

  @override
  String get noArtistDataYet => 'No hay más datos del artista por ahora.';

  @override
  String genreLabel(Object genre) {
    return 'Género: $genre';
  }

  @override
  String countryLabel(Object country) {
    return 'País: $country';
  }

  @override
  String detectedPeriod(Object firstYear, Object latestYear) {
    return 'Periodo detectado: $firstYear - $latestYear';
  }

  @override
  String get shortBioTitle => 'Historia breve';

  @override
  String get popularReleases => 'Lanzamientos populares';

  @override
  String get back => 'Regresar';

  @override
  String get editSearch => 'Editar búsqueda';

  @override
  String get backToMatches => 'Regresar a coincidencias';

  @override
  String get manualSearchTitle => 'Búsqueda manual';

  @override
  String get manualSearchDescription =>
      'Escribe una consulta para buscar coincidencias en lrclib.';

  @override
  String get searchQueryLabel => 'Buscar (query)';

  @override
  String get searchQueryHint => 'Ej. clandestino shakira';

  @override
  String get searchLyrics => 'Buscar letra';

  @override
  String get noMatchesToChoose =>
      'No se encontraron coincidencias para elegir.';

  @override
  String get copy => 'Copiar';

  @override
  String get share => 'Compartir';

  @override
  String get saveToGallery => 'Guardar en galería';

  @override
  String get associateToSong => 'Asociar a canción';

  @override
  String get shareSnapshot => 'Capturar y compartir';

  @override
  String get snapshotReady => 'Imagen lista para compartir';

  @override
  String get snapshotSaved => 'Imagen guardada';

  @override
  String get snapshotError => 'No se pudo generar la imagen';

  @override
  String get snapshotActiveLine => 'Línea activa';

  @override
  String get snapshotVisibleVerse => 'Verso visible';

  @override
  String get snapshotNoLyrics => 'Sin letra disponible';

  @override
  String get snapshotGeneratedWithBrand => 'Generado con SingSync';

  @override
  String get lyricsCopied => 'Letra copiada';

  @override
  String get lyricsAssociated => 'Letra asociada a la canción';

  @override
  String get lyricsNotAssociated => 'No se pudo asociar la letra';

  @override
  String get favoriteAdded => 'Añadida a tus favoritos';

  @override
  String get favoriteRemoved => 'Se quitó de tus favoritos';

  @override
  String get favoriteDeleted => 'Se elimino de favoritos';

  @override
  String get addToFavorites => 'Agregar a favoritos';

  @override
  String get removeFromFavorites => 'Quitar de favoritos';

  @override
  String get favoritesLibrary => 'Biblioteca';

  @override
  String get noFavoritesYet => 'No hay favoritos aún';

  @override
  String get savedSnapshotsTitle => 'Portadas para el recuerdo';

  @override
  String get noSavedSnapshotsYet => 'Aún no hay imágenes guardadas';

  @override
  String get delete => 'Borrar';

  @override
  String get snapshotDeleted => 'Imagen eliminada';

  @override
  String get spotifyLabel => 'Spotify';

  @override
  String get youtubeMusicLabel => 'YouTube Music';

  @override
  String get amazonMusicLabel => 'Amazon Music';

  @override
  String get appleMusicLabel => 'Apple Music';

  @override
  String get permissionMissingMessage =>
      'Activa el acceso a notificaciones para esta app y reproduce una canción para cargar su letra.';

  @override
  String get waitingPlaybackMessage =>
      'Permiso activo. Comienza a reproducir una canción para detectar el now playing y cargar la letra.';

  @override
  String get adDetectedMessage =>
      'Anuncio detectado. Esperando el siguiente cambio de canción...';

  @override
  String get tuningLyricsMessage => 'Sintonizando letra ...';

  @override
  String get notFoundMessage =>
      'No se encontró letra para esta canción en lrclib.';

  @override
  String get searchLyricsDefaultPrompt =>
      'Escribe lo que quieras buscar para encontrar una letra.';

  @override
  String get listeningErrorArtist => 'Error escuchando notificaciones';

  @override
  String get updatingLyrics => 'Actualizando letra en lrclib...';

  @override
  String get selectMatchToShowLyrics =>
      'Selecciona una coincidencia para mostrar la letra.';

  @override
  String get noMatchesApiSearch =>
      'No se encontraron coincidencias en /api/search.';

  @override
  String get manualSearchPrompt =>
      'Escribe una búsqueda manual para ver coincidencias.';

  @override
  String get completeSearchField =>
      'Completa el campo de búsqueda para continuar.';

  @override
  String get searchingMatches => 'Buscando coincidencias en lrclib...';

  @override
  String get apiSearchUnavailable =>
      'No fue posible consultar /api/search en este momento.';

  @override
  String get retryingMatches => 'Reintentando coincidencias en lrclib...';

  @override
  String get lrclibUnavailable =>
      'No fue posible consultar lrclib en este momento.';
}
