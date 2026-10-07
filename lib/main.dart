import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models/market_models.dart';
import 'providers/app_state.dart';
import 'services/ad_service.dart';

/// One distinct icon per item, shown inside each card.
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

const Color kBrand = Color(0xff075e54);

/// Human-readable unit shown under each item name.
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
      // Open safely with the India fallback. GPS/permission is user-triggered
      // from the location button, so a broken provider cannot kill startup.
      state.load(target: const PlaceResult(name: 'India', latitude: 20.5937, longitude: 78.9629));
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

  // Wait for the first load to finish (plus a short minimum splash) instead of
  // a fixed timer, so the home screen never flashes an empty state.
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
  final Map<String, double> temporaryRates = {};

  @override
  void dispose() {
    search.dispose();
    for (final controller in amountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final data = s.data;
    final keys = tab == 1 ? ['gold', 'silver'] : ['petrol', 'diesel', 'lpg', 'cng'];
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 900),
        decoration: BoxDecoration(gradient: LinearGradient(colors: widget.colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 700;
              final horizontal = isTablet ? 32.0 : 16.0;
              return Column(
                children: [
                  _header(s, isTablet),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    child: _searchField(s),
                  ),
                  const SizedBox(height: 14),
                  _weather(data?.weather, s),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(color: Color(0xfff4faf7), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
                      child: Column(children: [
                        _tabBar(s),
                        Padding(
                          padding: EdgeInsets.fromLTRB(horizontal, 6, horizontal, 0),
                          child: Row(children: [
                            Icon(Icons.verified_user_outlined, size: 15, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Expanded(child: Text(
                              s.language == 'hi' ? 'हर रेट GoodReturns page से खुद check करें, फिर calculation होगा' : 'Verify each rate on its GoodReturns page before calculating',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                            )),
                          ]),
                        ),
                        Expanded(
                          child: s.loading
                              ? const Center(child: CircularProgressIndicator())
                              : ListView(
                                  padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 24),
                                  children: [
                                    _responsiveGrid(keys, s),
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(AppState s, bool isTablet) => Padding(
        padding: EdgeInsets.fromLTRB(isTablet ? 32 : 20, 18, isTablet ? 32 : 14, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(s.language == 'hi' ? 'लाइव रेट' : 'Live Price', style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800))),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.place, color: Colors.white70, size: 14),
                const SizedBox(width: 4),
                Flexible(child: Text(s.place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13))),
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
          if (mounted) search.text = s.place.name;
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

  Widget _weather(WeatherData? weather, AppState s) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
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
            decoration: BoxDecoration(color: tab == index ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(14), boxShadow: tab == index ? const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))] : null),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: tab == index ? kBrand : Colors.black54),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: tab == index ? kBrand : Colors.black54)),
            ]),
          ),
        ),
      );

  Widget _responsiveGrid(List<String> keys, AppState s) {
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
    final rate = temporaryRates[key];
    final verified = rate != null && rate > 0;
    final color = kItemColors[key] ?? kBrand;
    final icon = kItemIcons[key] ?? Icons.category;
    final premium = key == 'gold' || key == 'silver';
    final quantity = (verified && amount > 0) ? amount / rate : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: verified ? color.withAlpha(90) : const Color(0xffe6efe9), width: verified ? 1.4 : 1),
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
          if (verified)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${rate.toStringAsFixed(2)}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
              Row(children: [
                Icon(Icons.verified, size: 12, color: color),
                const SizedBox(width: 3),
                Text(s.language == 'hi' ? 'जाँचा गया' : 'checked', style: TextStyle(fontSize: 10, color: color)),
              ]),
            ])
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xfff1f5f3), borderRadius: BorderRadius.circular(10)),
              child: Text(s.language == 'hi' ? 'अभी नहीं' : 'Not yet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            ),
        ]),
        const SizedBox(height: 14),
        if (verified) ...[
          TextField(
            controller: controller,
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
              amount > 0
                  ? (premium ? '${quantity.toStringAsFixed(3)} g' : '${quantity.toStringAsFixed(2)} ${s.language == 'hi' ? 'यूनिट' : 'units'}')
                  : (s.language == 'hi' ? 'राशि लिखें तो गणना दिखेगी' : 'Enter an amount to see the quantity'),
              style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14),
            ),
          ),
        ] else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xfff6f8f7), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(child: Text(s.language == 'hi' ? 'पहले GoodReturns page पर rate check करें' : 'Check the rate on GoodReturns first', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700))),
            ]),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: verified
              ? OutlinedButton.icon(
                  onPressed: () => _showSourceViewer(key, s),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('GoodReturns source'),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: () => _showSourceViewer(key, s),
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: Text(s.language == 'hi' ? 'GoodReturns पर check करें' : 'Check on GoodReturns'),
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

  void _showSourceViewer(String key, AppState s) {
    final selectedCity = widget.state.data?.city ?? widget.state.place.name;
    final url = _sourceUrl(key, widget.state.data, selectedCity);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (request) => _allowedSource(request.url) ? NavigationDecision.navigate : NavigationDecision.prevent))
      ..loadRequest(Uri.parse(url));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.white,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .94,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
            child: Row(children: [
              Icon(kItemIcons[key] ?? Icons.category, color: kItemColors[key] ?? kBrand, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('${_name(key, s.language)} • $selectedCity', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(s.language == 'hi' ? 'Page को scroll करें और नीचे rate text ढूंढें' : 'Scroll the page and find the rate text below', style: const TextStyle(fontSize: 12, color: Colors.orange))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _captureOfficialRate(controller, key, s),
                icon: const Icon(Icons.download_done, size: 17),
                label: Text(s.language == 'hi' ? 'इसी page का rate इस्तेमाल करें' : 'Use rate from this page'),
              ),
            ),
          ),
          const Divider(height: 12),
          Expanded(
            child: WebViewWidget(
              controller: controller,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
              },
            ),
          ),
        ]),
      ),
    );
  }

  /// Prefer the URL the backend already returned; only build one as a fallback.
  String _sourceUrl(String key, MarketData? data, String city) {
    final urls = data?.sourceUrls;
    final fromServer = urls == null ? null : urls[key];
    if (fromServer != null && fromServer.isNotEmpty) {
      return fromServer;
    }
    final slug = city.toLowerCase().trim().split(',').first.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    const aliases = {'bengaluru': 'bangalore', 'bengalore': 'bangalore', 'new delhi': 'new-delhi', 'thiruvananthapuram': 'trivandrum'};
    final normalized = aliases[city.toLowerCase().trim()] ?? slug;
    if (key == 'gold' || key == 'silver') {
      final section = key == 'gold' ? 'gold-rates' : 'silver-rates';
      return normalized.isEmpty || normalized == 'india' ? 'https://www.goodreturns.in/$section/' : 'https://www.goodreturns.in/$section/$normalized.html';
    }
    return normalized.isEmpty || normalized == 'india' ? 'https://www.goodreturns.in/$key-price.html' : 'https://www.goodreturns.in/$key-price-in-$normalized.html';
  }

  bool _allowedSource(String rawUrl) {
    final host = Uri.tryParse(rawUrl)?.host ?? '';
    return host == 'goodreturns.in' || host.endsWith('.goodreturns.in');
  }

  Future<void> _captureOfficialRate(WebViewController controller, String key, AppState s) async {
    try {
      final result = await controller.runJavaScriptReturningResult('document.body ? document.body.innerText : ""');
      final text = _javaScriptText(result.toString());
      final rate = _extractRate(key, text);
      if (rate == null) {
        throw const FormatException('No visible rate found');
      }
      setState(() => temporaryRates[key] = rate);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.language == 'hi' ? '₹${rate.toStringAsFixed(2)} set हो गया — अब राशि लिखें' : '₹${rate.toStringAsFixed(2)} saved — now enter an amount')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.language == 'hi' ? 'इस page पर rate text नहीं मिला; scroll करके फिर कोशिश करें' : 'No readable rate found on this page; scroll and try again')));
      }
    }
  }

  /// Find the rate next to the item's label, not just the first number on the
  /// page (which is often a date, another city or an ad figure).
  double? _extractRate(String key, String text) {
    final keywords = <String, List<String>>{
      'petrol': ['petrol'],
      'diesel': ['diesel'],
      'lpg': ['lpg', 'cylinder'],
      'cng': ['cng'],
      'gold': ['24k', 'gold'],
      'silver': ['silver'],
    }[key]!;
    final numberRe = RegExp(r'([0-9]{1,3}(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?)');
    for (final line in text.split(RegExp(r'[\n\r]+'))) {
      final lower = line.toLowerCase();
      if (!keywords.any(lower.contains)) continue;
      for (final match in numberRe.allMatches(line)) {
        final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
        if (value != null && isPlausiblePrice(key, value)) {
          return value;
        }
      }
    }
    // Last resort: any plausible value on the page.
    for (final match in numberRe.allMatches(text)) {
      final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (value != null && isPlausiblePrice(key, value)) {
        return value;
      }
    }
    return null;
  }

  String _javaScriptText(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is String ? decoded : raw;
    } catch (_) {
      return raw;
    }
  }
}
