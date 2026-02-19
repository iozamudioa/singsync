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

  /// No description provided for @close.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get close;

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

  /// No description provided for @noFavoritesYet.
  ///
  /// In es, this message translates to:
  /// **'No hay favoritos aún'**
  String get noFavoritesYet;

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
