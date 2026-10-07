import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models/market_models.dart';
import 'providers/app_state.dart';
import 'services/ad_service.dart';

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
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff075e54)),
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
              width: 92,
              height: 92,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8))]),
              child: const Icon(Icons.location_on_rounded, color: Color(0xff075e54), size: 54),
            ),
            const SizedBox(height: 22),
            const Text('LocaRate', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: .4)),
            const SizedBox(height: 6),
            const Text('Location based rates', style: TextStyle(color: Colors.white70, fontSize: 15, letterSpacing: .3)),
            const SizedBox(height: 28),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
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
  final names = const {'petrol': 'Petrol', 'diesel': 'Diesel', 'lpg': 'LPG', 'cng': 'CNG', 'gold': 'Gold', 'silver': 'Silver'};

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
                  Padding(
                    padding: EdgeInsets.fromLTRB(isTablet ? 32 : 20, 18, isTablet ? 32 : 20, 12),
                    child: Row(children: [
                      Expanded(child: FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(s.language == 'hi' ? 'लाइव रेट' : 'Live Price', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)))),
                      TextButton(onPressed: s.toggleLanguage, child: Text(s.language == 'hi' ? 'EN' : 'हि', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      IconButton(onPressed: () async { await s.load(); if (mounted) search.clear(); }, icon: const Icon(Icons.my_location, color: Colors.white)),
                    ]),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    child: TextField(
                      controller: search,
                      onSubmitted: (value) async {
                        await s.searchCity(value);
                        if (mounted) {
                          search.text = s.place.name;
                        }
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: s.language == 'hi' ? 'शहर खोजें…' : 'Search city in India…',
                        hintStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.search, color: Colors.white),
                        filled: true,
                        fillColor: Colors.white24,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _weather(data?.weather, s),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(color: Color(0xfff4faf7), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                      child: Column(children: [
                        Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 4), child: Row(children: [_tab(s.language == 'hi' ? 'ईंधन' : 'Fuel', 0), _tab(s.language == 'hi' ? 'धातु' : 'Wealth', 1)])),
                        Expanded(
                          child: s.loading
                              ? const Center(child: CircularProgressIndicator())
                              : ListView(
                                  padding: EdgeInsets.fromLTRB(horizontal, 4, horizontal, 24),
                                  children: [
                                    _responsiveGrid(keys, data, s),
                                    if (s.error != null) Text(s.error!, style: const TextStyle(color: Colors.red)),
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

  Widget _responsiveGrid(List<String> keys, MarketData? data, AppState s) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 3 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 4,
          children: [
            ...keys.map((key) => SizedBox(width: width, child: _priceCard(key, data, s))),
          ],
        );
      },
    );
  }

  Widget _tab(String label, int index) => Expanded(
        child: GestureDetector(
          onTap: () { setState(() => tab = index); widget.ads.maybeShow(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: tab == index ? const Color(0xffd9fdd3) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
            child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: tab == index ? const Color(0xff075e54) : Colors.black54))),
          ),
        ),
      );

  Widget _weather(WeatherData? weather, AppState s) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Row(children: [
          const Icon(Icons.cloud_queue, color: Colors.white, size: 38),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${weather?.temperatureC.toStringAsFixed(0) ?? '--'}°C  ${weather?.condition ?? (s.language == 'hi' ? 'मौसम लोड हो रहा है' : 'Loading weather')}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text('${s.place.name}  •  ${s.language == 'hi' ? 'नमी' : 'Humidity'} ${weather?.humidity ?? '--'}%', style: const TextStyle(color: Colors.white70)),
          ])),
          const Icon(Icons.wifi, color: Colors.white70),
        ]),
      );

  TextEditingController _amountController(String key) {
    return amountControllers.putIfAbsent(key, () => TextEditingController(text: '1000'));
  }

  Widget _priceCard(String key, MarketData? data, AppState s) {
    final amountController = _amountController(key);
    final value = double.tryParse(amountController.text) ?? 0;
    final officialRate = temporaryRates[key];
    final serverPrice = data?.prices[key];
    final displayAvailable = officialRate != null || serverPrice != null;
    final effectivePrice = officialRate ?? serverPrice ?? 0;
    final quantity = !displayAvailable || effectivePrice == 0 ? 0 : value / effectivePrice;
    final premium = key == 'gold' || key == 'silver';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            CircleAvatar(radius: 20, backgroundColor: const Color(0xffd9fdd3), child: Icon(premium ? Icons.workspace_premium : Icons.local_gas_station, color: const Color(0xff075e54), size: 22)),
            const SizedBox(width: 8),
            Expanded(child: Text(_name(key, s.language), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            const SizedBox(width: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(displayAvailable ? '₹${effectivePrice.toStringAsFixed(2)}${_unitSuffix(key)}' : '--', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff075e54)))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: amountController, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: InputDecoration(prefixText: '₹ ', labelText: s.language == 'hi' ? 'राशि' : 'Amount', filled: true, fillColor: const Color(0xfff0f5f2), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(displayAvailable ? (premium ? '${quantity.toStringAsFixed(3)} g' : '${quantity.toStringAsFixed(2)} units') : (s.language == 'hi' ? 'पहले official page check करें' : 'Check official page first'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff075e54))),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showSourceViewer(key, data, s),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: Text(_sourceButtonLabel(key, s.language), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    return names[key]!;
  }

  void _showSourceViewer(String key, MarketData? data, AppState s) {
    final selectedCity = data?.city ?? s.place.name;
    final url = _sourceUrl(key, data, selectedCity);
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
              Expanded(child: Text('${_sourceName(key)} • $selectedCity', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(s.language == 'hi' ? 'Official page को नीचे पूरे area में scroll करें' : 'Scroll the official page in the full area below', style: const TextStyle(fontSize: 12, color: Colors.orange))),
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

  String _sourceButtonLabel(String key, String language) {
    if (language == 'hi') {
      return 'GoodReturns source देखें';
    }
    return 'View GoodReturns source';
  }

  String _unitSuffix(String key) => kPriceUnits[key] ?? '';

  String _sourceName(String key) => 'GoodReturns';

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.language == 'hi' ? 'Official page का ₹${rate.toStringAsFixed(2)} rate अस्थायी रूप से इस्तेमाल हो रहा है' : '₹${rate.toStringAsFixed(2)} from the official page is active temporarily')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.language == 'hi' ? 'इस page पर rate text नहीं मिला; page scroll करके फिर कोशिश करें' : 'No readable rate found on this page; scroll and try again')));
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
