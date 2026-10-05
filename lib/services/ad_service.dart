import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  InterstitialAd? _ad;
  DateTime? _lastShown;
  static const _testUnit = 'ca-app-pub-3940256099942544/1033173712';

  void preload() => InterstitialAd.load(
    adUnitId: _testUnit,
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: (ad) => _ad = ad, onAdFailedToLoad: (_) {}),
  );

  void maybeShow() {
    final now = DateTime.now();
    if (_lastShown != null && now.difference(_lastShown!) < const Duration(minutes: 3)) {
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
}
