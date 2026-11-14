name: tissemsilt_edu
description: "خلية الاعلام والاتصال تيسمسيلت"
publish_to: 'none'
version: 1.0.1+2

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^1.2.2
  xml: ^6.5.0
  url_launcher: ^6.3.1
  receive_sharing_intent: ^1.8.0
  shared_preferences: ^2.3.2
  share_plus: ^10.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
3. ملف lib/main.dart (الكود الكامل المتكامل)
افتح ملف lib/main.dart وامسحه بالكامل، ثم الصق هذا الكود المتكامل (يعمل باللغة العربية، يجلب أخبار الوزارة والمديريات من خلاصات RSS ومصادر Google News التربوية الموثوقة دون حظر، ويستقبل أي رابط أو منشور تشاركه من فيسبوك أو يوتيوب ويحفظه في تبويب خاص):

Dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const RasedTarbiyaApp());
}

class RasedTarbiyaApp extends StatelessWidget {
  const RasedTarbiyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'راصد التربية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: MainDashboardScreen(),
      ),
    );
  }
}

class NewsArticle {
  final String title;
  final String source;
  final String url;
  final String date;

  NewsArticle({
    required this.title,
    required this.source,
    required this.url,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'source': source,
        'url': url,
        'date': date,
      };

  factory NewsArticle.fromJson(Map<String, dynamic> json) => NewsArticle(
        title: json['title'] ?? '',
        source: json['source'] ?? '',
        url: json['url'] ?? '',
        date: json['date'] ?? '',
      );
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late StreamSubscription _intentSub;

  List<NewsArticle> _tissemsiltNews = [];
  List<NewsArticle> _nationalNews = [];
  List<NewsArticle> _sharedSavedNews = [];

  bool _isLoadingTissemsilt = true;
  bool _isLoadingNational = true;
  String? _errorTissemsilt;
  String? _errorNational;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSavedSharedNews();
    _fetchAllNews();
    _initSharingIntent();
  }

  // استقبال الروابط والمنشورات المشتركة من فيسبوك ويوتيوب
  void _initSharingIntent() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _processSharedText(value.first.path);
        }
      },
      onError: (err) => debugPrint("Share Stream Error: $err"),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _processSharedText(value.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

  Future<void> _processSharedText(String rawText) async {
    if (rawText.trim().isEmpty) return;

    // استخراج الرابط من النص في حال أرسل فيسبوك أو يوتيوب عنواناً مع الرابط
    final RegExp urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final Match? match = urlRegExp.firstMatch(rawText);
    final String extractedUrl = match != null ? match.group(0)! : rawText.trim();

    String sourceLabel = "رابط خارجي";
    if (extractedUrl.contains("youtube.com") || extractedUrl.contains("youtu.be")) {
      sourceLabel = "فيديو يوتيوب";
    } else if (extractedUrl.contains("facebook.com") || extractedUrl.contains("fb.watch")) {
      sourceLabel = "منشور فيسبوك";
    }

    String cleanTitle = rawText.replaceAll(extractedUrl, '').trim();
    if (cleanTitle.isEmpty) {
      cleanTitle = "محتوى مرصود من $sourceLabel";
    }

    final newArticle = NewsArticle(
      title: cleanTitle,
      source: sourceLabel,
      url: extractedUrl,
      date: DateTime.now().toString().substring(0, 16),
    );

    setState(() {
      _sharedSavedNews.insert(0, newArticle);
      _tabController.animateTo(2); // الانتقال تلقائياً لتبويب المرصودات المشتركة
    });

    await _saveSharedNewsToStorage();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("تمت إضافة $sourceLabel إلى قائمة المرصودات بنجاح"),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _loadSavedSharedNews() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? encodedList = prefs.getStringList('saved_shared_news');
    if (encodedList != null) {
      setState(() {
        _sharedSavedNews = encodedList
            .map((item) => NewsArticle.fromJson(jsonDecode(item)))
            .toList();
      });
    }
  }

  Future<void> _saveSharedNewsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> encodedList =
        _sharedSavedNews.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList('saved_shared_news', encodedList);
  }

  Future<void> _deleteSharedItem(int index) async {
    setState(() {
      _sharedSavedNews.removeAt(index);
    });
    await _saveSharedNewsToStorage();
  }

  Future<void> _fetchAllNews() async {
    _fetchTissemsiltNews();
    _fetchNationalNews();
  }

  // جلب أخبار مديرية التربية لتيسمسيلت والولاية
  Future<void> _fetchTissemsiltNews() async {
    setState(() {
      _isLoadingTissemsilt = true;
      _errorTissemsilt = null;
    });

    try {
      final query = Uri.encodeComponent('مديرية التربية تيسمسيلت OR التربية تيسمسيلت');
      final url = 'https://news.google.com/rss/search?q=$query&hl=ar&gl=DZ&ceid=DZ:ar';
      final articles = await _parseRssFeed(url, 'مديرية التربية تيسمسيلت');
      setState(() {
        _tissemsiltNews = articles;
        _isLoadingTissemsilt = false;
      });
    } catch (e) {
      setState(() {
        _errorTissemsilt = 'تعذر جلب أخبار تيسمسيلت. تأكد من الاتصال بالإنترنت.';
        _isLoadingTissemsilt = false;
      });
    }
  }

  // جلب أخبار وزارة التربية الوطنية والمديريات 69
  Future<void> _fetchNationalNews() async {
    setState(() {
      _isLoadingNational = true;
      _errorNational = null;
    });

    try {
      final query = Uri.encodeComponent('وزارة التربية الوطنية الجزائر OR مديرية التربية');
      final url = 'https://news.google.com/rss/search?q=$query&hl=ar&gl=DZ&ceid=DZ:ar';
      final articles = await _parseRssFeed(url, 'وزارة التربية والمديريات');
      setState(() {
        _nationalNews = articles;
        _isLoadingNational = false;
      });
    } catch (e) {
      setState(() {
        _errorNational = 'تعذر جلب الأخبار الوطنية. اسحب للأسفل للتحديث.';
        _isLoadingNational = false;
      });
    }
  }

  Future<List<NewsArticle>> _parseRssFeed(String rssUrl, String defaultSource) async {
    final response = await http.get(
      Uri.parse(rssUrl),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    final items = document.findAllElements('item');

    return items.map((node) {
      final title = node.findElements('title').firstOrNull?.innerText ?? 'بدون عنوان';
      final link = node.findElements('link').firstOrNull?.innerText ?? '';
      final pubDate = node.findElements('pubDate').firstOrNull?.innerText ?? '';
      final sourceName = node.findElements('source').firstOrNull?.innerText ?? defaultSource;

      // تنظيف التاريخ
      String shortDate = pubDate;
      if (pubDate.length > 16) {
        shortDate = pubDate.substring(0, 16);
      }

      return NewsArticle(
        title: title,
        source: sourceName,
        url: link,
        date: shortDate,
      );
    }).toList();
  }

  Future<void> _openUrl(String urlString) async {
    final Uri uri = Uri.parse(urlString);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الرابط على هذا الجهاز')),
        );
      }
    }
  }

  @override
  void dispose() {
    _intentSub.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'راصد التربية',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              'تيسمسيلت والمديريات الـ 69',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث الأخبار',
            onPressed: _fetchAllNews,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(icon: Icon(Icons.location_city), text: 'تيسمسيلت'),
            const Tab(icon: Icon(Icons.account_balance), text: 'الوزارة والمديريات'),
            Tab(
              icon: Badge(
                label: Text('${_sharedSavedNews.length}'),
                isLabelVisible: _sharedSavedNews.isNotEmpty,
                child: const Icon(Icons.bookmark_added),
              ),
              text: 'مرصوداتي',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewsListView(
            articles: _tissemsiltNews,
            isLoading: _isLoadingTissemsilt,
            errorMsg: _errorTissemsilt,
            onRefresh: _fetchTissemsiltNews,
            emptyText: 'لا توجد أخبار محلية حالياً. اسحب للأسفل للتحديث.',
          ),
          _buildNewsListView(
            articles: _nationalNews,
            isLoading: _isLoadingNational,
            errorMsg: _errorNational,
            onRefresh: _fetchNationalNews,
            emptyText: 'لا توجد أخبار وطنية حالياً. اسحب للأسفل للتحديث.',
          ),
          _buildSharedListView(),
        ],
      ),
    );
  }

  Widget _buildNewsListView({
    required List<NewsArticle> articles,
    required bool isLoading,
    required String? errorMsg,
    required Future<void> Function() onRefresh,
    required String emptyText,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 50, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(errorMsg, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (articles.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(child: Text(emptyText)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: articles.length,
        itemBuilder: (context, index) {
          final article = articles[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              title: Text(
                article.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.source, size: 14, color: Colors.blue.shade800),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        article.source,
                        style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      article.date,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.share, color: Colors.grey),
                onPressed: () {
                  Share.share('${article.title}\n${article.url}');
                },
              ),
              onTap: () => _openUrl(article.url),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSharedListView() {
    if (_sharedSavedNews.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.share_arrival_time, size: 60, color: Colors.blueGrey),
              SizedBox(height: 16),
              Text(
                'قائمة المرصودات فارغة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'أثناء تصفحك لفيسبوك أو يوتيوب، اضغط على زر "مشاركة" واختر تطبيق "راصد التربية" لحفظ الفيديو أو المنشور هنا فوراً.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _sharedSavedNews.length,
      itemBuilder: (context, index) {
        final item = _sharedSavedNews[index];
        final bool isYoutube = item.source.contains('يوتيوب');
        final bool isFacebook = item.source.contains('فيسبوك');

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isYoutube
                  ? Colors.red.shade100
                  : (isFacebook ? Colors.blue.shade100 : Colors.grey.shade200),
              child: Icon(
                isYoutube
                    ? Icons.play_circle_fill
                    : (isFacebook ? Icons.facebook : Icons.link),
                color: isYoutube
                    ? Colors.red
                    : (isFacebook ? Colors.blue.shade800 : Colors.black87),
              ),
            ),
            title: Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  item.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.source} • ${item.date}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _deleteSharedItem(index),
            ),
            onTap: () => _openUrl(item.url),
          ),
        );
      },
    );
  }