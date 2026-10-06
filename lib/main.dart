import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;
import 'package:webview_flutter/webview_flutter.dart';
import 'models/market_models.dart';
import 'providers/app_state.dart';
import 'services/ad_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const LivePriceApp());
}

class LivePriceApp extends StatefulWidget {
  const LivePriceApp({super.key});
  @override State<LivePriceApp> createState() => _LivePriceAppState();
}

class _LivePriceAppState extends State<LivePriceApp> {
  final state = AppState();
  final ads = AdService();

  @override
  void initState() {
    super.initState();
    state.load();
    ads.preload();
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
  bool ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ready) {
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
  @override State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  final search = TextEditingController();
  final amount = TextEditingController(text: '1000');
  final names = const {'petrol': 'Petrol', 'diesel': 'Diesel', 'lpg': 'LPG', 'cng': 'CNG', 'gold': 'Gold', 'silver': 'Silver'};

  @override
  void dispose() {
    search.dispose();
    amount.dispose();
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
                    if (mounted) search.text = s.place.name;
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
                    if (data != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        child: Row(children: [
                          Icon(data.source == 'demo-fallback' || data.source.startsWith('google-') ? Icons.info_outline : Icons.verified, size: 15, color: data.source == 'demo-fallback' || data.source.startsWith('google-') ? Colors.orange.shade800 : const Color(0xff075e54)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_sourceText(data.source, s.language), style: TextStyle(fontSize: 12, color: data.source == 'demo-fallback' || data.source.startsWith('google-search') ? Colors.orange.shade800 : const Color(0xff075e54)))),
                          Text('${s.language == 'hi' ? 'अपडेट' : 'Updated'} ${_time(data.updatedAt)}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ]),
                      ),
                    Expanded(
                      child: s.loading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              padding: EdgeInsets.fromLTRB(horizontal, 4, horizontal, 24),
                              children: [
                                if (isTablet)
                                  _responsiveGrid(keys, data, s)
                                else
                                  ...keys.map((key) => _priceCard(key, data?.prices[key] ?? 0, data, s)),
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
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 2,
      childAspectRatio: 1.18,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ...keys.map((key) => _priceCard(key, data?.prices[key] ?? 0, data, s)),
      ],
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

  Widget _weather(dynamic weather, AppState s) => Padding(
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

  String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Widget _priceCard(String key, double price, MarketData? data, AppState s) {
    final value = double.tryParse(amount.text) ?? 0;
    final available = data != null && (data.source == 'configured-provider' || data.observedKeys.contains(key));
    final quantity = !available || price == 0 ? 0 : value / price;
    final premium = key == 'gold' || key == 'silver';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            CircleAvatar(backgroundColor: const Color(0xffd9fdd3), child: Icon(premium ? Icons.workspace_premium : Icons.local_gas_station, color: const Color(0xff075e54))),
            const SizedBox(width: 12),
            Expanded(child: Text(_name(key, s.language), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            Text(available ? '₹${price.toStringAsFixed(2)}' : '--', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff075e54))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: amount, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: InputDecoration(prefixText: '₹ ', labelText: s.language == 'hi' ? 'राशि' : 'Amount', filled: true, fillColor: const Color(0xfff0f5f2), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
            const SizedBox(width: 12),
            Text(available ? (premium ? '${quantity.toStringAsFixed(3)} g' : '${quantity.toStringAsFixed(2)} units') : (s.language == 'hi' ? 'रेट उपलब्ध नहीं' : 'Rate unavailable'), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff075e54))),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showSourceViewer(key, data, s),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: Text(_sourceButtonLabel(key, s.language)),
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
    final url = _sourceUrl(key, data, s.place.name);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (request) => _allowedSource(request.url) ? NavigationDecision.navigate : NavigationDecision.prevent))
      ..loadRequest(Uri.parse(url));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
            child: Row(children: [
              Expanded(child: Text('${_sourceName(key)} • ${s.place.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(s.language == 'hi' ? 'Selected city source • rate को official page पर verify करें' : 'Selected city source • verify the rate on the official page', style: const TextStyle(fontSize: 12, color: Colors.orange))),
          const Divider(height: 12),
          Expanded(child: WebViewWidget(controller: controller)),
        ]),
      ),
    );
  }

  String _sourceButtonLabel(String key, String language) {
    if (language == 'hi') {
      return key == 'gold' || key == 'silver' ? 'विश्वसनीय source देखें' : 'Official source देखें';
    }
    return key == 'gold' || key == 'silver' ? 'View trusted source' : 'View official source';
  }

  String _sourceName(String key) {
    if (key == 'petrol' || key == 'diesel' || key == 'lpg' || key == 'cng') {
      return 'IndianOil / PPAC';
    }
    return 'IBJA / GoodReturns';
  }

  String _sourceUrl(String key, MarketData? data, String city) {
    if (key == 'petrol' || key == 'diesel') {
      return 'https://iocl.com/petrol-diesel-price';
    }
    if (key == 'lpg') {
      return 'https://cx.indianoil.in/webcenter/portal/Customer/pages_productprice';
    }
    if (key == 'cng') {
      return 'https://iocl.com/prices-of-petroleum-products';
    }
    if (key == 'gold') {
      return 'https://www.goodreturns.in/gold-rates/';
    }
    return 'https://www.goodreturns.in/silver-rates/';
  }

  bool _allowedSource(String rawUrl) {
    final host = Uri.tryParse(rawUrl)?.host ?? '';
    return host == 'iocl.com' || host.endsWith('.iocl.com') || host == 'indianoil.in' || host.endsWith('.indianoil.in') || host == 'goodreturns.in' || host.endsWith('.goodreturns.in') || host == 'ibjarates.com' || host.endsWith('.ibjarates.com');
  }

  String _sourceText(String source, String language) {
    if (language == 'hi') {
      if (source == 'google-scheduled-cache') {
        return 'सुबह 6 बजे का Google cache • जाँचें';
      }
      if (source == 'google-search-partial') {
        return 'Google Search data + fallback • जाँचें';
      }
      if (source == 'google-search-indicative') {
        return 'Google Search अनुमान • जाँचें';
      }
      if (source == 'demo-fallback') {
        return 'रेट उपलब्ध नहीं • provider जोड़ें';
      }
      return 'Live provider rates';
    }
    if (source == 'google-scheduled-cache') {
      return '6am Google cache • verify';
    }
    if (source == 'google-search-partial') {
      return 'Google Search data + fallback • verify';
    }
    if (source == 'google-search-indicative') {
      return 'Google Search estimate • verify';
    }
    if (source == 'demo-fallback') {
      return 'Rates unavailable • add provider';
    }
    return 'Live provider rates';
  }
}
