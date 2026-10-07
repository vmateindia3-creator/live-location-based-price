import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as gma;

import 'models/market_models.dart';
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
  'lpg': 'per cylinder',
  'cng': 'per kg',
  'gold': 'per gram',
  'silver': 'per gram',
};
const Map<String, String> kItemUnitLabelHi = {
  'petrol': 'प्रति लीटर',
  'diesel': 'प्रति लीटर',
  'lpg': 'प्रति सिलेंडर',
  'cng': 'प्रति किलो',
  'gold': 'प्रति ग्राम',
  'silver': 'प्रति ग्राम',
};

const Color kBrand = Color(0xff075e54);

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
      // Ask for location straight away (live location), or the user can search.
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
        final temperature = state.data?.weather.temperatureC ?? 28;
        final colors = temperature > 34
            ? [const Color(0xff075e54), const Color(0xfff59e0b)]
            : temperature < 18
                ? [const Color(0xff0f4c81), const Color(0xff38bdf8)]
                : [const Color(0xff075e54), const Color(0xff25d366)];
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
            colorScheme: ColorScheme.fromSeed(seedColor: kBrand),
            scaffoldBackgroundColor: const Color(0xfff4faf7),
          ),
          home: SplashGate(state: state, ads: ads, colors: colors),
        );
      },
    );
  }
}

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.state, required this.ads, required this.colors});
  final AppState state;
  final AdService ads;
  final List<Color> colors;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _minElapsed = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _minElapsed = true);
    });
    widget.state.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (widget.state.loading) {
      _started = true;
    }
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
      return Home(state: widget.state, ads: widget.ads, colors: widget.colors);
    }
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: widget.colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 22, offset: Offset(0, 10))]),
              child: const Icon(Icons.location_on_rounded, color: kBrand, size: 56),
            ),
            const SizedBox(height: 22),
            const Text('LocaRate', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: .5)),
            const SizedBox(height: 6),
            const Text('Live rates for India', style: TextStyle(color: Colors.white70, fontSize: 15, letterSpacing: .3)),
            const SizedBox(height: 30),
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key, required this.state, required this.ads, required this.colors});
  final AppState state;
  final AdService ads;
  final List<Color> colors;
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
    final keys = tab == 1 ? ['gold', 'silver'] : ['petrol', 'diesel', 'lpg', 'cng'];
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 900),
        decoration: BoxDecoration(gradient: LinearGradient(colors: widget.colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [
            _header(s),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _searchField(s)),
            const SizedBox(height: 14),
            Expanded(child: s.hasLocation ? _content(s, keys) : _locationPrompt(s)),
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

  Widget _header(AppState s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(s.language == 'hi' ? 'लाइव रेट' : 'Live Price', style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800))),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.place, color: Colors.white70, size: 14),
                const SizedBox(width: 4),
                Flexible(child: Text(s.place?.name ?? (s.language == 'hi' ? 'लोकेशन नहीं' : 'No location'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13))),
              ]),
            ]),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
            child: TextButton(onPressed: s.toggleLanguage, child: Text(s.language == 'hi' ? 'EN' : 'हि', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
            child: IconButton(onPressed: () async { await s.load(); if (mounted) search.clear(); }, icon: const Icon(Icons.my_location, color: Colors.white)),
          ),
        ]),
      );

  Widget _searchField(AppState s) => TextField(
        controller: search,
        onSubmitted: (value) async {
          await s.searchCity(value);
          if (mounted) search.text = s.place?.name ?? '';
        },
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: s.language == 'hi' ? 'शहर खोजें…' : 'Search city in India…',
          hintStyle: const TextStyle(color: Colors.white70),
          prefixIcon: const Icon(Icons.search, color: Colors.white),
          filled: true,
          fillColor: Colors.white24,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        ),
      );

  Widget _locationPrompt(AppState s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(28)),
              child: const Icon(Icons.location_off_outlined, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 18),
            Text(s.language == 'hi' ? 'पहले location चुनें' : 'Select location first', style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              s.language == 'hi' ? 'लाइव रेट देखने के लिए अपनी location दें या ऊपर शहर खोजें' : 'Allow your location or search a city above to see live rates',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kBrand, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
              onPressed: () => s.load(),
              icon: const Icon(Icons.my_location),
              label: Text(s.language == 'hi' ? 'मेरी location इस्तेमाल करें' : 'Use my location', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => s.openLocationSettings(),
              child: Text(s.language == 'hi' ? 'Location settings खोलें' : 'Open location settings', style: const TextStyle(color: Colors.white70)),
            ),
          ]),
        ),
      );

  Widget _content(AppState s, List<String> keys) => Column(children: [
        _weather(s.data?.weather, s),
        _updateButton(s),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(color: Color(0xfff4faf7), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: Column(children: [
              _tabBar(s),
              Expanded(
                child: s.loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _grid(keys, s),
                          const SizedBox(height: 6),
                          Center(child: Text(
                            s.language == 'hi' ? 'संकेतात्मक रेट — खरीदने से पहले जाँच लें' : 'Indicative rates — verify before purchase',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          )),
                          if (s.error != null) Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(s.error!, style: const TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
              ),
            ]),
          ),
        ),
      ]);

  Widget _weather(WeatherData? weather, AppState s) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.wb_cloudy_outlined, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${weather?.temperatureC.toStringAsFixed(0) ?? '--'}°C  ${weather?.condition ?? (s.language == 'hi' ? 'मौसम लोड हो रहा है' : 'Loading weather')}', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
            Text('${s.language == 'hi' ? 'नमी' : 'Humidity'} ${weather?.humidity ?? '--'}%   •   ${s.language == 'hi' ? 'हवा' : 'Wind'} ${weather?.windKph.toStringAsFixed(0) ?? '--'} km/h', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ])),
        ]),
      );

  Widget _updateButton(AppState s) => Center(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: kBrand,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
          ),
          onPressed: s.loading ? null : () => s.updatePrices(),
          icon: s.loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: Text(s.language == 'hi' ? 'लाइव रेट अपडेट करें' : 'Update live prices', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      );

  Widget _tabBar(AppState s) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xffe7f2ec), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            _tab(s.language == 'hi' ? 'ईंधन' : 'Fuel', 0, Icons.local_gas_station),
            _tab(s.language == 'hi' ? 'धातु' : 'Wealth', 1, Icons.workspace_premium),
          ]),
        ),
      );

  Widget _tab(String label, int index, IconData icon) => Expanded(
        child: GestureDetector(
          onTap: () { setState(() => tab = index); widget.ads.maybeShow(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: tab == index ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: tab == index ? const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))] : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: tab == index ? kBrand : Colors.black54),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: tab == index ? kBrand : Colors.black54)),
            ]),
          ),
        ),
      );

  Widget _grid(List<String> keys, AppState s) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 3 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            ...keys.map((key) => SizedBox(width: width, child: _priceCard(key, s))),
          ],
        );
      },
    );
  }

  TextEditingController _amountController(String key) {
    // Empty by default: only the card the user types in shows a result.
    return amountControllers.putIfAbsent(key, () => TextEditingController());
  }

  Widget _priceCard(String key, AppState s) {
    final controller = _amountController(key);
    final amount = double.tryParse(controller.text.trim()) ?? 0;
    final rate = s.pricesRevealed ? s.data?.prices[key] : null;
    final hasRate = rate != null && rate > 0;
    final color = kItemColors[key] ?? kBrand;
    final icon = kItemIcons[key] ?? Icons.category;
    final premium = key == 'gold' || key == 'silver';
    final quantity = (hasRate && amount > 0) ? amount / rate : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hasRate ? color.withAlpha(90) : const Color(0xffe6efe9), width: hasRate ? 1.4 : 1),
        boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name(key, s.language), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(s.language == 'hi' ? (kItemUnitLabelHi[key] ?? '') : (kItemUnitLabel[key] ?? ''), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ]),
          ),
          if (hasRate)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${rate.toStringAsFixed(2)}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
              Text(s.language == 'hi' ? 'आज का रेट' : 'today', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ])
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xfff1f5f3), borderRadius: BorderRadius.circular(10)),
              child: Text(s.language == 'hi' ? 'अपडेट करें' : 'Update', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: controller,
          enabled: hasRate,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: s.language == 'hi' ? 'राशि लिखें' : 'Enter amount',
            isDense: true,
            filled: true,
            fillColor: const Color(0xfff0f5f2),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: color.withAlpha(24), borderRadius: BorderRadius.circular(12)),
          child: Text(
            !hasRate
                ? (s.language == 'hi' ? 'पहले ऊपर से रेट अपडेट करें' : 'Update prices above first')
                : amount > 0
                    ? (premium ? '${quantity.toStringAsFixed(3)} g' : '${quantity.toStringAsFixed(2)} ${s.language == 'hi' ? 'यूनिट' : 'units'}')
                    : (s.language == 'hi' ? 'राशि लिखें तो गणना दिखेगी' : 'Enter an amount to see the quantity'),
            style: TextStyle(fontWeight: FontWeight.w800, color: hasRate ? color : Colors.grey.shade600, fontSize: 14),
          ),
        ),
      ]),
    );
  }

  String _name(String key, String language) {
    if (language == 'hi') {
      return const {'petrol': 'पेट्रोल', 'diesel': 'डीज़ल', 'lpg': 'एलपीजी', 'cng': 'सीएनजी', 'gold': 'सोना', 'silver': 'चाँदी'}[key]!;
    }
    return const {'petrol': 'Petrol', 'diesel': 'Diesel', 'lpg': 'LPG', 'cng': 'CNG', 'gold': 'Gold', 'silver': 'Silver'}[key]!;
  }
}
