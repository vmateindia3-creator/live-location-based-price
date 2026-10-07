import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as gma;

import 'providers/app_state.dart';
import 'services/ad_service.dart';

/// One distinct icon per item.
const Map<String, IconData> kItemIcons = {
  'petrol': Icons.local_gas_station,
  'diesel': Icons.local_shipping,
  'lpg': Icons.local_fire_department,
  'cng': Icons.air,
  'gold': Icons.workspace_premium,
  'silver': Icons.diamond,
};

/// One distinct accent colour per item.
const Map<String, Color> kItemColors = {
  'petrol': Color(0xffe8590c),
  'diesel': Color(0xff1e6f9f),
  'lpg': Color(0xffd6336c),
  'cng': Color(0xff0ca678),
  'gold': Color(0xffb8860b),
  'silver': Color(0xff6b7280),
};

/// Unit label under each item name.
const Map<String, String> kItemUnitLabel = {
  'petrol': 'per litre',
  'diesel': 'per litre',
  'lpg': 'per domestic 14.2 kg',
  'cng': 'per kg',
  'gold': 'per gram',
  'silver': 'per gram',
};
const Map<String, String> kItemUnitLabelHi = {
  'petrol': 'प्रति लीटर',
  'diesel': 'प्रति लीटर',
  'lpg': 'प्रति घरेलू 14.2 किग्रा',
  'cng': 'प्रति किलो',
  'gold': 'प्रति ग्राम',
  'silver': 'प्रति ग्राम',
};

const Color kBrand = Color(0xff075e54);
const Color kTextDark = Color(0xff0f172a);
const Color kTextSoft = Color(0xff64748b);
const Color kHairline = Color(0xffe8eef0);

/// The app-wide look, driven by the temperature of the selected location.
class AppTheme {
  const AppTheme({required this.gradient, required this.accent, required this.surface, required this.tint});
  final List<Color> gradient;
  final Color accent;
  final Color surface; // content background, tinted by temperature
  final Color tint; // very light accent for chips/pills
}

AppTheme themeForTemperature(double temp) {
  final List<Color> g;
  if (temp >= 32) {
    g = [const Color(0xffb45309), const Color(0xfffbbf24)]; // hot
  } else if (temp >= 27) {
    g = [const Color(0xff065f46), const Color(0xff34d399)]; // warm
  } else if (temp >= 21) {
    g = [const Color(0xff0e7490), const Color(0xff22d3ee)]; // mild
  } else {
    g = [const Color(0xff1e3a8a), const Color(0xff60a5fa)]; // cool
  }
  return AppTheme(
    gradient: g,
    accent: g[0],
    surface: Color.lerp(g[0], Colors.white, 0.95)!,
    tint: Color.lerp(g[0], Colors.white, 0.86)!,
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LivePriceApp());
}

class LivePriceApp extends StatefulWidget {
  const LivePriceApp({super.key});
  @override
  State<LivePriceApp> createState() => _LivePriceAppState();
}

class _LivePriceAppState extends State<LivePriceApp> {
  final state = AppState();
  final ads = AdService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      state.load();
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          try {
            ads.preload();
          } catch (_) {
            // Ads are optional and must never block the first screen.
          }
        }
      });
    });
  }

  @override
  void dispose() {
    ads.dispose();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (_, __) {
        final theme = themeForTemperature(state.data?.weather.temperatureC ?? 28);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(state.language),
          supportedLocales: const [Locale('hi'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: theme.accent),
            scaffoldBackgroundColor: theme.surface,
          ),
          home: SplashGate(state: state, ads: ads, theme: theme),
        );
      },
    );
  }
}

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.state, required this.ads, required this.theme});
  final AppState state;
  final AdService ads;
  final AppTheme theme;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _minElapsed = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _minElapsed = true);
    });
    widget.state.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (widget.state.loading) _started = true;
    setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  bool get _ready => _minElapsed && _started && !widget.state.loading;

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return Home(state: widget.state, ads: widget.ads, theme: widget.theme);
    }
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: widget.theme.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(size: 96),
            const SizedBox(height: 22),
            const Text('LocaRate', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: .4)),
            const SizedBox(height: 6),
            const Text('Live rates across India', style: TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 30),
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44, this.onDark = true});
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? Colors.white24 : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(Icons.location_on_rounded, color: onDark ? Colors.white : kBrand, size: size * 0.55),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key, required this.state, required this.ads, required this.theme});
  final AppState state;
  final AdService ads;
  final AppTheme theme;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  final search = TextEditingController();
  final Map<String, TextEditingController> amountControllers = {};

  gma.BannerAd? _banner;
  bool _bannerReady = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  void _loadBanner() {
    final banner = gma.BannerAd(
      adUnitId: AdService.bannerUnit,
      size: gma.AdSize.banner,
      request: const gma.AdRequest(),
      listener: gma.BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _bannerReady = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _banner = null;
        },
      ),
    );
    _banner = banner;
    banner.load();
  }

  @override
  void dispose() {
    search.dispose();
    for (final controller in amountControllers.values) {
      controller.dispose();
    }
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final t = widget.theme;
    final keys = tab == 1 ? ['gold', 'silver'] : ['petrol', 'diesel', 'lpg', 'cng'];
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        decoration: BoxDecoration(gradient: LinearGradient(colors: t.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            _hero(s, t),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: s.hasLocation ? _content(s, t, keys) : _locationPrompt(s, t),
              ),
            ),
            _bannerWidget(),
          ]),
        ),
      ),
    );
  }

  Widget _bannerWidget() {
    final ad = _banner;
    if (!_bannerReady || ad == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.white,
      alignment: Alignment.center,
      height: ad.size.height.toDouble(),
      child: gma.AdWidget(ad: ad),
    );
  }

  // ---------- hero (on the temperature gradient) ----------

  Widget _hero(AppState s, AppTheme t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(children: [
          Row(children: [
            const BrandMark(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LocaRate', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: .2)),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.place, color: Colors.white70, size: 13),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      s.place?.name ?? (s.language == 'hi' ? 'लोकेशन नहीं' : 'No location'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ]),
            ),
            _roundAction(s.language == 'hi' ? 'EN' : 'हि', s.toggleLanguage),
            const SizedBox(width: 8),
            _roundAction(null, () async { await s.load(); if (mounted) search.clear(); }),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: search,
            onSubmitted: (value) async {
              await s.searchCity(value);
              if (mounted) search.text = s.place?.name ?? '';
            },
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: s.language == 'hi' ? 'शहर खोजें…' : 'Search city in India…',
              hintStyle: const TextStyle(color: Colors.white70),
              prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
              filled: true,
              fillColor: Colors.white24,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          if (s.hasLocation) ...[
            const SizedBox(height: 14),
            _weatherCard(s, t),
            const SizedBox(height: 14),
            _updateButton(s, t),
          ],
        ]),
      );

  Widget _roundAction(String? label, VoidCallback onTap) => Material(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: label == null
                  ? const Icon(Icons.my_location, color: Colors.white, size: 20)
                  : Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ),
        ),
      );

  Widget _weatherCard(AppState s, AppTheme t) {
    final weather = s.data?.weather;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.wb_cloudy_outlined, color: Colors.white, size: 34),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${weather?.temperatureC.toStringAsFixed(0) ?? '--'}°C',
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.05),
            ),
            Text(
              weather?.condition ?? (s.language == 'hi' ? 'मौसम लोड हो रहा है' : 'Loading weather'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _chip(Icons.water_drop_outlined, '${weather?.humidity ?? '--'}%'),
          const SizedBox(height: 6),
          _chip(Icons.air, '${weather?.windKph.toStringAsFixed(0) ?? '--'} km/h'),
        ]),
      ]),
    );
  }

  Widget _chip(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]);

  Widget _updateButton(AppState s, AppTheme t) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: t.accent,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          onPressed: s.loading ? null : () => s.updatePrices(),
          icon: s.loading
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: t.accent))
              : const Icon(Icons.refresh, size: 20),
          label: Text(
            s.language == 'hi' ? 'लाइव रेट अपडेट करें' : 'Update live prices',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
          ),
        ),
      );

  // ---------- content sheet ----------

  Widget _content(AppState s, AppTheme t, List<String> keys) => Column(children: [
        _tabBar(s, t),
        Expanded(
          child: s.loading
              ? Center(child: CircularProgressIndicator(color: t.accent))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  children: [
                    _grid(keys, s, t),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        s.language == 'hi' ? 'संकेतात्मक रेट — खरीदने से पहले जाँच लें' : 'Indicative rates — verify before purchase',
                        style: const TextStyle(fontSize: 11, color: kTextSoft),
                      ),
                    ),
                    if (s.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(s.error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                      ),
                  ],
                ),
        ),
      ]);

  Widget _tabBar(AppState s, AppTheme t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kHairline)),
          child: Row(children: [
            _tab(s.language == 'hi' ? 'ईंधन' : 'Fuel', 0, Icons.local_gas_station, t),
            _tab(s.language == 'hi' ? 'धातु' : 'Wealth', 1, Icons.workspace_premium, t),
          ]),
        ),
      );

  Widget _tab(String label, int index, IconData icon, AppTheme t) => Expanded(
        child: GestureDetector(
          onTap: () { setState(() => tab = index); widget.ads.maybeShow(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: tab == index ? t.tint : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: tab == index ? t.accent : kTextSoft),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: tab == index ? t.accent : kTextSoft)),
            ]),
          ),
        ),
      );

  Widget _locationPrompt(AppState s, AppTheme t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: t.tint, borderRadius: BorderRadius.circular(26)),
              child: Icon(Icons.location_off_outlined, color: t.accent, size: 40),
            ),
            const SizedBox(height: 18),
            Text(s.language == 'hi' ? 'पहले location चुनें' : 'Select location first',
                style: const TextStyle(color: kTextDark, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              s.language == 'hi'
                  ? 'लाइव रेट देखने के लिए अपनी location दें या ऊपर शहर खोजें'
                  : 'Allow your location or search a city above to see live rates',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSoft, fontSize: 13.5),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: t.accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => s.load(),
              icon: const Icon(Icons.my_location, size: 18),
              label: Text(s.language == 'hi' ? 'मेरी location इस्तेमाल करें' : 'Use my location', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => s.openLocationSettings(),
              child: Text(s.language == 'hi' ? 'Location settings खोलें' : 'Open location settings', style: const TextStyle(color: kTextSoft)),
            ),
          ]),
        ),
      );

  Widget _grid(List<String> keys, AppState s, AppTheme t) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: keys.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 196,
          ),
          itemBuilder: (context, index) => _priceCard(keys[index], s, t),
        );
      },
    );
  }

  TextEditingController _amountController(String key) {
    return amountControllers.putIfAbsent(key, () => TextEditingController());
  }

  Widget _priceCard(String key, AppState s, AppTheme t) {
    final controller = _amountController(key);
    final amount = double.tryParse(controller.text.trim()) ?? 0;
    final rate = s.pricesRevealed ? s.data?.prices[key] : null;
    final hasRate = rate != null && rate > 0;
    final color = kItemColors[key] ?? kBrand;
    final icon = kItemIcons[key] ?? Icons.category;
    final premium = key == 'gold' || key == 'silver';
    final quantity = (hasRate && amount > 0) ? amount / rate : 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Column(children: [
          Container(height: 4, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_name(key, s.language), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: kTextDark)),
                      const SizedBox(height: 2),
                      Text(s.language == 'hi' ? (kItemUnitLabelHi[key] ?? '') : (kItemUnitLabel[key] ?? ''),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: kTextSoft)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 104),
                    child: hasRate
                        ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            FittedBox(fit: BoxFit.scaleDown, child: Text('₹${rate.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color))),
                            const Text('today', style: TextStyle(fontSize: 10, color: kTextSoft)),
                          ])
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: const Color(0xfff1f5f9), borderRadius: BorderRadius.circular(10)),
                            child: const Text('Update', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextSoft)),
                          ),
                  ),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  enabled: hasRate,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: kTextDark),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    hintText: s.language == 'hi' ? 'राशि लिखें' : 'Enter amount',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xfff4f7f6),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      !hasRate
                          ? (s.language == 'hi' ? 'पहले ऊपर से रेट अपडेट करें' : 'Update prices above first')
                          : amount > 0
                              ? (premium ? '${quantity.toStringAsFixed(3)} g' : '${quantity.toStringAsFixed(2)} ${s.language == 'hi' ? 'यूनिट' : 'units'}')
                              : (s.language == 'hi' ? 'राशि लिखें तो गणना दिखेगी' : 'Enter an amount to see the quantity'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, color: hasRate ? color : kTextSoft, fontSize: 13.5),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _name(String key, String language) {
    if (language == 'hi') {
      return const {'petrol': 'पेट्रोल', 'diesel': 'डीज़ल', 'lpg': 'एलपीजी', 'cng': 'सीएनजी', 'gold': 'सोना', 'silver': 'चाँदी'}[key]!;
    }
    return const {'petrol': 'Petrol', 'diesel': 'Diesel', 'lpg': 'LPG', 'cng': 'CNG', 'gold': 'Gold', 'silver': 'Silver'}[key]!;
  }
}
