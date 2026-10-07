import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Non-blocking interstitial ads.
///
/// The ad unit below is Google's **test** interstitial. Before release, replace
/// it with your production unit ID and add the AdMob application IDs to
/// AndroidManifest.xml / Info.plist (see CONFIGURATION.md). Never show an ad on
/// every tap; [maybeShow] enforces a cooldown.
class AdService {
  // TODO(release): replace with the production interstitial unit ID.
  static const String _interstitialUnit = 'ca-app-pub-3940256099942544/1033173712';
  static const Duration _cooldown = Duration(minutes: 3);

  InterstitialAd? _ad;
  DateTime? _lastShown;

  void preload() {
    InterstitialAd.load(
      adUnitId: _interstitialUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _ad = ad,
        onAdFailedToLoad: (_) {},
      ),
    );
  }

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
