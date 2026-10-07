import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad placement for the app.
///
/// Both unit IDs below are Google's **test** IDs, so ads can be placed now and
/// swapped for production units later. Before release, replace them and add the
/// AdMob application IDs to AndroidManifest.xml / Info.plist (see
/// CONFIGURATION.md), plus a consent flow.
class AdService {
  // TODO(release): replace with your production unit IDs.
  // Overridable at build time:
  //   --dart-define=ADMOB_BANNER=ca-app-pub-XXXX/YYYY
  //   --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-XXXX/ZZZZ
  static const String interstitialUnit = String.fromEnvironment(
    'ADMOB_INTERSTITIAL',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const String bannerUnit = String.fromEnvironment(
    'ADMOB_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );

  static const Duration _cooldown = Duration(minutes: 3);

  InterstitialAd? _ad;
  DateTime? _lastShown;

  void preload() {
    InterstitialAd.load(
      adUnitId: interstitialUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _ad = ad,
        onAdFailedToLoad: (_) {},
      ),
    );
  }

  /// Interstitial shown on tab switches, with a cooldown so it is not intrusive.
  void maybeShow() {
    final now = DateTime.now();
    if (_lastShown != null && now.difference(_lastShown!) < _cooldown) {
      return;
    }
    final ad = _ad;
    if (ad == null) {
      return;
    }
    _ad = null;
    _lastShown = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(onAdDismissedFullScreenContent: (_) => preload());
    ad.show();
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
