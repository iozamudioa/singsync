import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @appTitle.
  ///
  /// In es, this message translates to:
  /// **'Lyric Notifier'**
  String get appTitle;

  /// No description provided for @nowPlayingDefaultTitle.
  ///
  /// In es, this message translates to:
  /// **'Now Playing'**
  String get nowPlayingDefaultTitle;

  /// No description provided for @unknownArtist.
  ///
  /// In es, this message translates to:
  /// **'Artista desconocido'**
  String get unknownArtist;

  /// No description provided for @artistLabel.
  ///
  /// In es, this message translates to:
  /// **'Artista'**
  String get artistLabel;

  /// No description provided for @favoritesLabel.
  ///
  /// In es, this message translates to:
  /// **'Favoritos'**
  String get favoritesLabel;

  /// No description provided for @motivationStartPlayback.
  ///
  /// In es, this message translates to:
  /// **'Pon tu canción favorita y empezamos 🎵'**
  String get motivationStartPlayback;

  /// No description provided for @permissionNeededTitle.
  ///
  /// In es, this message translates to:
  /// **'Permiso necesario'**
  String get permissionNeededTitle;

  /// No description provided for @permissionDialogMessage.
  ///
  /// In es, this message translates to:
  /// **'SingSync necesita acceso a notificaciones para detectar la canción actual y buscar su letra automáticamente.'**
  String get permissionDialogMessage;

  /// No description provided for @notNow.
  ///
  /// In es, this message translates to:
  /// **'Ahora no'**
  String get notNow;

  /// No description provided for @goToPermissions.
  ///
  /// In es, this message translates to:
  /// **'Ir a permisos'**
  String get goToPermissions;

  /// No description provided for @enableNotificationsCard.
  ///
  /// In es, this message translates to:
  /// **'Activa acceso a notificaciones para detectar canciones.'**
  String get enableNotificationsCard;

  /// No description provided for @allow.
  ///
  /// In es, this message translates to:
  /// **'Permitir'**
  String get allow;

  /// No description provided for @accept.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get accept;

  /// No description provided for @cancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get close;

  /// No description provided for @search.
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get search;

  /// No description provided for @configure.
  ///
  /// In es, this message translates to:
  /// **'Configurar'**
  String get configure;

  /// No description provided for @developerBy.
  ///
  /// In es, this message translates to:
  /// **'Developer by: iozamudioa'**
  String get developerBy;

  /// No description provided for @githubLabel.
  ///
  /// In es, this message translates to:
  /// **'Github:'**
  String get githubLabel;

  /// No description provided for @privacyPolicyLabel.
  ///
  /// In es, this message translates to:
  /// **'Política de privacidad:'**
  String get privacyPolicyLabel;

  /// No description provided for @versionLabel.
  ///
  /// In es, this message translates to:
  /// **'Version: {version}'**
  String versionLabel(Object version);

  /// No description provided for @poweredByLrclib.
  ///
  /// In es, this message translates to:
  /// **'Powered by: LRCLIB'**
  String get poweredByLrclib;

  /// No description provided for @useArtworkBackground.
  ///
  /// In es, this message translates to:
  /// **'Usar carátula como fondo'**
  String get useArtworkBackground;

  /// No description provided for @useSolidBackgroundDescription.
  ///
  /// In es, this message translates to:
  /// **'Si se desactiva, se usa fondo sólido según el tema.'**
  String get useSolidBackgroundDescription;

  /// No description provided for @infoTooltip.
  ///
  /// In es, this message translates to:
  /// **'Información'**
  String get infoTooltip;

  /// No description provided for @switchToLightMode.
  ///
  /// In es, this message translates to:
  /// **'Cambiar a modo claro'**
  String get switchToLightMode;

  /// No description provided for @switchToDarkMode.
  ///
  /// In es, this message translates to:
  /// **'Cambiar a modo oscuro'**
  String get switchToDarkMode;

  /// No description provided for @openActivePlayer.
  ///
  /// In es, this message translates to:
  /// **'Abrir reproductor activo'**
  String get openActivePlayer;

  /// No description provided for @previous.
  ///
  /// In es, this message translates to:
  /// **'Anterior'**
  String get previous;

  /// No description provided for @playPause.
  ///
  /// In es, this message translates to:
  /// **'Play/Pause'**
  String get playPause;

  /// No description provided for @next.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get next;

  /// No description provided for @searchManually.
  ///
  /// In es, this message translates to:
  /// **'Buscar manualmente'**
  String get searchManually;

  /// No description provided for @noArtistDataYet.
  ///
  /// In es, this message translates to:
  /// **'No hay más datos del artista por ahora.'**
  String get noArtistDataYet;

  /// No description provided for @genreLabel.
  ///
  /// In es, this message translates to:
  /// **'Género: {genre}'**
  String genreLabel(Object genre);

  /// No description provided for @countryLabel.
  ///
  /// In es, this message translates to:
  /// **'País: {country}'**
  String countryLabel(Object country);

  /// No description provided for @detectedPeriod.
  ///
  /// In es, this message translates to:
  /// **'Periodo detectado: {firstYear} - {latestYear}'**
  String detectedPeriod(Object firstYear, Object latestYear);

  /// No description provided for @shortBioTitle.
  ///
  /// In es, this message translates to:
  /// **'Historia breve'**
  String get shortBioTitle;

  /// No description provided for @popularReleases.
  ///
  /// In es, this message translates to:
  /// **'Lanzamientos populares'**
  String get popularReleases;

  /// No description provided for @back.
  ///
  /// In es, this message translates to:
  /// **'Regresar'**
  String get back;

  /// No description provided for @editSearch.
  ///
  /// In es, this message translates to:
  /// **'Editar búsqueda'**
  String get editSearch;

  /// No description provided for @backToMatches.
  ///
  /// In es, this message translates to:
  /// **'Regresar a coincidencias'**
  String get backToMatches;

  /// No description provided for @manualSearchTitle.
  ///
  /// In es, this message translates to:
  /// **'Búsqueda manual'**
  String get manualSearchTitle;

  /// No description provided for @manualSearchDescription.
  ///
  /// In es, this message translates to:
  /// **'Escribe una consulta para buscar coincidencias en lrclib.'**
  String get manualSearchDescription;

  /// No description provided for @searchQueryLabel.
  ///
  /// In es, this message translates to:
  /// **'Buscar (query)'**
  String get searchQueryLabel;

  /// No description provided for @searchQueryHint.
  ///
  /// In es, this message translates to:
  /// **'Ej. clandestino shakira'**
  String get searchQueryHint;

  /// No description provided for @searchLyrics.
  ///
  /// In es, this message translates to:
  /// **'Buscar letra'**
  String get searchLyrics;

  /// No description provided for @noMatchesToChoose.
  ///
  /// In es, this message translates to:
  /// **'No se encontraron coincidencias para elegir.'**
  String get noMatchesToChoose;

  /// No description provided for @copy.
  ///
  /// In es, this message translates to:
  /// **'Copiar'**
  String get copy;

  /// No description provided for @share.
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get share;

  /// No description provided for @saveToGallery.
  ///
  /// In es, this message translates to:
  /// **'Guardar en galería'**
  String get saveToGallery;

  /// No description provided for @associateToSong.
  ///
  /// In es, this message translates to:
  /// **'Asociar a canción'**
  String get associateToSong;

  /// No description provided for @shareSnapshot.
  ///
  /// In es, this message translates to:
  /// **'Capturar y compartir'**
  String get shareSnapshot;

  /// No description provided for @snapshotReady.
  ///
  /// In es, this message translates to:
  /// **'Imagen lista para compartir'**
  String get snapshotReady;

  /// No description provided for @snapshotSaved.
  ///
  /// In es, this message translates to:
  /// **'Imagen guardada'**
  String get snapshotSaved;

  /// No description provided for @snapshotError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo generar la imagen'**
  String get snapshotError;

  /// No description provided for @snapshotActiveLine.
  ///
  /// In es, this message translates to:
  /// **'Línea activa'**
  String get snapshotActiveLine;

  /// No description provided for @snapshotVisibleVerse.
  ///
  /// In es, this message translates to:
  /// **'Verso visible'**
  String get snapshotVisibleVerse;

  /// No description provided for @snapshotNoLyrics.
  ///
  /// In es, this message translates to:
  /// **'Sin letra disponible'**
  String get snapshotNoLyrics;

  /// No description provided for @snapshotGeneratedWithBrand.
  ///
  /// In es, this message translates to:
  /// **'Generado con SingSync'**
  String get snapshotGeneratedWithBrand;

  /// No description provided for @snapshotLineSelectionTitle.
  ///
  /// In es, this message translates to:
  /// **'Tu frase para el recuerdo'**
  String get snapshotLineSelectionTitle;

  /// No description provided for @lyricsCopied.
  ///
  /// In es, this message translates to:
  /// **'Letra copiada'**
  String get lyricsCopied;

  /// No description provided for @lyricsAssociated.
  ///
  /// In es, this message translates to:
  /// **'Letra asociada a la canción'**
  String get lyricsAssociated;

  /// No description provided for @lyricsNotAssociated.
  ///
  /// In es, this message translates to:
  /// **'No se pudo asociar la letra'**
  String get lyricsNotAssociated;

  /// No description provided for @favoriteAdded.
  ///
  /// In es, this message translates to:
  /// **'Añadida a tus favoritos'**
  String get favoriteAdded;

  /// No description provided for @favoriteRemoved.
  ///
  /// In es, this message translates to:
  /// **'Se quitó de tus favoritos'**
  String get favoriteRemoved;

  /// No description provided for @favoriteDeleted.
  ///
  /// In es, this message translates to:
  /// **'Se elimino de favoritos'**
  String get favoriteDeleted;

  /// No description provided for @addToFavorites.
  ///
  /// In es, this message translates to:
  /// **'Agregar a favoritos'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In es, this message translates to:
  /// **'Quitar de favoritos'**
  String get removeFromFavorites;

  /// No description provided for @favoritesLibrary.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get favoritesLibrary;

  /// No description provided for @mySongsTitle.
  ///
  /// In es, this message translates to:
  /// **'Mis canciones'**
  String get mySongsTitle;

  /// No description provided for @catchemTitle.
  ///
  /// In es, this message translates to:
  /// **'Bitácora musical'**
  String get catchemTitle;

  /// No description provided for @searchBySongOrArtist.
  ///
  /// In es, this message translates to:
  /// **'Buscar por canción o artista'**
  String get searchBySongOrArtist;

  /// No description provided for @noResults.
  ///
  /// In es, this message translates to:
  /// **'Sin resultados'**
  String get noResults;

  /// No description provided for @noFavoritesYet.
  ///
  /// In es, this message translates to:
  /// **'No hay favoritos aún'**
  String get noFavoritesYet;

  /// No description provided for @noCatchemYet.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay canciones en tu bitácora musical'**
  String get noCatchemYet;

  /// No description provided for @catchemDeleted.
  ///
  /// In es, this message translates to:
  /// **'Canción eliminada de la bitácora musical'**
  String get catchemDeleted;

  /// No description provided for @catchemDetectionCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{# escucha} other{# escuchas}}'**
  String catchemDetectionCount(num count);

  /// No description provided for @catchemCaptureMode.
  ///
  /// In es, this message translates to:
  /// **'Captura: {mode}'**
  String catchemCaptureMode(Object mode);

  /// No description provided for @catchemCaptureManual.
  ///
  /// In es, this message translates to:
  /// **'Manual'**
  String get catchemCaptureManual;

  /// No description provided for @catchemCaptureAutomatic.
  ///
  /// In es, this message translates to:
  /// **'Automática'**
  String get catchemCaptureAutomatic;

  /// No description provided for @catchemCaptureHistoryTitle.
  ///
  /// In es, this message translates to:
  /// **'Capturas de {song}'**
  String catchemCaptureHistoryTitle(Object song);

  /// No description provided for @catchemLastHeard.
  ///
  /// In es, this message translates to:
  /// **'Última vez escuchada fecha: {date} hora: {time}'**
  String catchemLastHeard(Object date, Object time);

  /// No description provided for @catchemTimestamp.
  ///
  /// In es, this message translates to:
  /// **'Fecha: {date} Hora: {time}'**
  String catchemTimestamp(Object date, Object time);

  /// No description provided for @catchemTimestampUnknown.
  ///
  /// In es, this message translates to:
  /// **'Fecha: --/--/---- Hora: --:--'**
  String get catchemTimestampUnknown;

  /// No description provided for @catchemOpenMap.
  ///
  /// In es, this message translates to:
  /// **'Ver mapa de capturas'**
  String get catchemOpenMap;

  /// No description provided for @catchemMapTitle.
  ///
  /// In es, this message translates to:
  /// **'Mapa de canciones capturadas'**
  String get catchemMapTitle;

  /// No description provided for @catchemMapNoPoints.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay capturas con ubicación'**
  String get catchemMapNoPoints;

  /// No description provided for @catchemLyricsSource.
  ///
  /// In es, this message translates to:
  /// **'Fuente: {source}'**
  String catchemLyricsSource(Object source);

  /// No description provided for @catchemSourceCache.
  ///
  /// In es, this message translates to:
  /// **'caché local'**
  String get catchemSourceCache;

  /// No description provided for @catchemSourceGetCached.
  ///
  /// In es, this message translates to:
  /// **'LRCLIB GET-CACHED'**
  String get catchemSourceGetCached;

  /// No description provided for @catchemSourceGet.
  ///
  /// In es, this message translates to:
  /// **'LRCLIB GET'**
  String get catchemSourceGet;

  /// No description provided for @catchemSourceSearchTrackArtist.
  ///
  /// In es, this message translates to:
  /// **'LRCLIB SEARCH track/artist'**
  String get catchemSourceSearchTrackArtist;

  /// No description provided for @catchemSourceSearchQuery.
  ///
  /// In es, this message translates to:
  /// **'LRCLIB SEARCH q'**
  String get catchemSourceSearchQuery;

  /// No description provided for @catchemSourceLrclib.
  ///
  /// In es, this message translates to:
  /// **'LRCLIB'**
  String get catchemSourceLrclib;

  /// No description provided for @catchemSourceUnknown.
  ///
  /// In es, this message translates to:
  /// **'desconocida'**
  String get catchemSourceUnknown;

  /// No description provided for @savedSnapshotsTitle.
  ///
  /// In es, this message translates to:
  /// **'Portadas para el recuerdo'**
  String get savedSnapshotsTitle;

  /// No description provided for @noSavedSnapshotsYet.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay imágenes guardadas'**
  String get noSavedSnapshotsYet;

  /// No description provided for @delete.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get delete;

  /// No description provided for @snapshotDeleted.
  ///
  /// In es, this message translates to:
  /// **'Imagen eliminada'**
  String get snapshotDeleted;

  /// No description provided for @spotifyLabel.
  ///
  /// In es, this message translates to:
  /// **'Spotify'**
  String get spotifyLabel;

  /// No description provided for @youtubeMusicLabel.
  ///
  /// In es, this message translates to:
  /// **'YouTube Music'**
  String get youtubeMusicLabel;

  /// No description provided for @amazonMusicLabel.
  ///
  /// In es, this message translates to:
  /// **'Amazon Music'**
  String get amazonMusicLabel;

  /// No description provided for @appleMusicLabel.
  ///
  /// In es, this message translates to:
  /// **'Apple Music'**
  String get appleMusicLabel;

  /// No description provided for @permissionMissingMessage.
  ///
  /// In es, this message translates to:
  /// **'Activa el acceso a notificaciones para esta app y reproduce una canción para cargar su letra.'**
  String get permissionMissingMessage;

  /// No description provided for @waitingPlaybackMessage.
  ///
  /// In es, this message translates to:
  /// **'Permiso activo. Comienza a reproducir una canción para detectar el now playing y cargar la letra.'**
  String get waitingPlaybackMessage;

  /// No description provided for @adDetectedMessage.
  ///
  /// In es, this message translates to:
  /// **'Anuncio detectado. Esperando el siguiente cambio de canción...'**
  String get adDetectedMessage;

  /// No description provided for @tuningLyricsMessage.
  ///
  /// In es, this message translates to:
  /// **'Sintonizando letra ...'**
  String get tuningLyricsMessage;

  /// No description provided for @notFoundMessage.
  ///
  /// In es, this message translates to:
  /// **'No se encontró letra para esta canción en lrclib.'**
  String get notFoundMessage;

  /// No description provided for @searchLyricsDefaultPrompt.
  ///
  /// In es, this message translates to:
  /// **'Escribe lo que quieras buscar para encontrar una letra.'**
  String get searchLyricsDefaultPrompt;

  /// No description provided for @listeningErrorArtist.
  ///
  /// In es, this message translates to:
  /// **'Error escuchando notificaciones'**
  String get listeningErrorArtist;

  /// No description provided for @updatingLyrics.
  ///
  /// In es, this message translates to:
  /// **'Actualizando letra en lrclib...'**
  String get updatingLyrics;

  /// No description provided for @selectMatchToShowLyrics.
  ///
  /// In es, this message translates to:
  /// **'Selecciona una coincidencia para mostrar la letra.'**
  String get selectMatchToShowLyrics;

  /// No description provided for @noMatchesApiSearch.
  ///
  /// In es, this message translates to:
  /// **'No se encontraron coincidencias en /api/search.'**
  String get noMatchesApiSearch;

  /// No description provided for @manualSearchPrompt.
  ///
  /// In es, this message translates to:
  /// **'Escribe una búsqueda manual para ver coincidencias.'**
  String get manualSearchPrompt;

  /// No description provided for @completeSearchField.
  ///
  /// In es, this message translates to:
  /// **'Completa el campo de búsqueda para continuar.'**
  String get completeSearchField;

  /// No description provided for @searchingMatches.
  ///
  /// In es, this message translates to:
  /// **'Buscando coincidencias en lrclib...'**
  String get searchingMatches;

  /// No description provided for @apiSearchUnavailable.
  ///
  /// In es, this message translates to:
  /// **'No fue posible consultar /api/search en este momento.'**
  String get apiSearchUnavailable;

  /// No description provided for @retryingMatches.
  ///
  /// In es, this message translates to:
  /// **'Reintentando coincidencias en lrclib...'**
  String get retryingMatches;

  /// No description provided for @lrclibUnavailable.
  ///
  /// In es, this message translates to:
  /// **'No fue posible consultar lrclib en este momento.'**
  String get lrclibUnavailable;

  /// No description provided for @todayLabel.
  ///
  /// In es, this message translates to:
  /// **'Hoy'**
  String get todayLabel;

  /// No description provided for @yesterdayLabel.
  ///
  /// In es, this message translates to:
  /// **'Ayer'**
  String get yesterdayLabel;

  /// No description provided for @thisMonthLabel.
  ///
  /// In es, this message translates to:
  /// **'Este mes'**
  String get thisMonthLabel;

  /// No description provided for @loadMoreLabel.
  ///
  /// In es, this message translates to:
  /// **'Ver más'**
  String get loadMoreLabel;

  /// No description provided for @catchemPlayedSongsCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{# canción reproducida} other{# canciones reproducidas}}'**
  String catchemPlayedSongsCount(num count);

  /// No description provided for @catchemNoPlaybackHistoryYet.
  ///
  /// In es, this message translates to:
  /// **'Sin reproducciones registradas todavía'**
  String get catchemNoPlaybackHistoryYet;

  /// No description provided for @catchemObsessionCaught.
  ///
  /// In es, this message translates to:
  /// **'Cancion atrapada 🕵️'**
  String get catchemObsessionCaught;

  /// No description provided for @catchemObsessionRadar.
  ///
  /// In es, this message translates to:
  /// **'En el radar 🛰️'**
  String get catchemObsessionRadar;

  /// No description provided for @catchemObsessionLoop.
  ///
  /// In es, this message translates to:
  /// **'En bucle infinito 🔄'**
  String get catchemObsessionLoop;

  /// No description provided for @catchemObsessionToday.
  ///
  /// In es, this message translates to:
  /// **'Obsesión del día 🔥'**
  String get catchemObsessionToday;

  /// No description provided for @catchemChoosePlayerTitle.
  ///
  /// In es, this message translates to:
  /// **'Elegir reproductor'**
  String get catchemChoosePlayerTitle;

  /// No description provided for @catchemNoPlayersAvailable.
  ///
  /// In es, this message translates to:
  /// **'No hay reproductores instalados disponibles'**
  String get catchemNoPlayersAvailable;

  /// No description provided for @thisWeekLabel.
  ///
  /// In es, this message translates to:
  /// **'Esta semana'**
  String get thisWeekLabel;

  /// No description provided for @olderLabel.
  ///
  /// In es, this message translates to:
  /// **'Anteriores'**
  String get olderLabel;

  /// No description provided for @sleepTimerMenuTitle.
  ///
  /// In es, this message translates to:
  /// **'Temporizador de apagado'**
  String get sleepTimerMenuTitle;

  /// No description provided for @appInfoMenuTitle.
  ///
  /// In es, this message translates to:
  /// **'Información de la app'**
  String get appInfoMenuTitle;

  /// No description provided for @sleepTimerCompleted.
  ///
  /// In es, this message translates to:
  /// **'Temporizador completo.'**
  String get sleepTimerCompleted;

  /// No description provided for @sleepTimerCanceled.
  ///
  /// In es, this message translates to:
  /// **'Temporizador cancelado'**
  String get sleepTimerCanceled;

  /// No description provided for @sleepTimerStatusIn.
  ///
  /// In es, this message translates to:
  /// **'Apagado en {time}'**
  String sleepTimerStatusIn(Object time);

  /// No description provided for @sleepTimerStatusAfterSongs.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Apagado después de # canción} other{Apagado después de # canciones}}'**
  String sleepTimerStatusAfterSongs(num count);

  /// No description provided for @sleepTimerStatusNone.
  ///
  /// In es, this message translates to:
  /// **'Sin temporizador'**
  String get sleepTimerStatusNone;

  /// No description provided for @sleepTimerSelectShutdownTime.
  ///
  /// In es, this message translates to:
  /// **'Selecciona tiempo de apagado'**
  String get sleepTimerSelectShutdownTime;

  /// No description provided for @sleepTimerCustomSongCountTitle.
  ///
  /// In es, this message translates to:
  /// **'Número de canciones'**
  String get sleepTimerCustomSongCountTitle;

  /// No description provided for @songsLabel.
  ///
  /// In es, this message translates to:
  /// **'Canciones'**
  String get songsLabel;

  /// No description provided for @sleepTimerSectionByTime.
  ///
  /// In es, this message translates to:
  /// **'Detener después de hh:mm tiempo'**
  String get sleepTimerSectionByTime;

  /// No description provided for @sleepTimerCustomTimeButton.
  ///
  /// In es, this message translates to:
  /// **'h : mm ?'**
  String get sleepTimerCustomTimeButton;

  /// No description provided for @sleepTimerSectionBySongs.
  ///
  /// In es, this message translates to:
  /// **'Detener después de N canciones'**
  String get sleepTimerSectionBySongs;

  /// No description provided for @cancelSleepTimer.
  ///
  /// In es, this message translates to:
  /// **'Cancelar temporizador'**
  String get cancelSleepTimer;

  /// No description provided for @sleepTimerActiveTitle.
  ///
  /// In es, this message translates to:
  /// **'Temporizador activo'**
  String get sleepTimerActiveTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
