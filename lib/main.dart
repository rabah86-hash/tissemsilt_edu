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
  final String? id;
  final String title;
  final String source;
  final String url;
  final String date;

  NewsArticle({
    this.id,
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

  factory NewsArticle.fromJson(Map<String, dynamic> json, {String? id}) =>
      NewsArticle(
        id: id,
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
  // إعدادات قاعدة البيانات السحابية ورمز المشرف
  static const String _firebaseDbUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts.json';
  static const String _firebaseBaseUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts';
  static const String _adminPin = '2026'; // الرمز السري للنشر للجميع

  late TabController _tabController;
  late StreamSubscription _intentSub;

  List<NewsArticle> _tissemsiltNews = [];
  List<NewsArticle> _nationalNews = [];
  List<NewsArticle> _cloudSharedNews = [];

  bool _isLoadingTissemsilt = true;
  bool _isLoadingNational = true;
  bool _isLoadingCloud = true;

  String? _errorTissemsilt;
  String? _errorNational;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAllData();
    _initSharingIntent();
  }

  // استقبال الروابط والمنشورات المشتركة من فيسبوك ويوتيوب
  void _initSharingIntent() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _preparePublishDialog(value.first.path);
        }
      },
      onError: (err) => debugPrint("Share Stream Error: $err"),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _preparePublishDialog(value.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

  // نافذة تأكيد النشر السحابي للجميع عند مشاركة رابط من فيسبوك أو يوتيوب
  Future<void> _preparePublishDialog(String rawText) async {
    if (rawText.trim().isEmpty) return;

    final RegExp urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final Match? match = urlRegExp.firstMatch(rawText);
    final String extractedUrl = match != null ? match.group(0)! : rawText.trim();

    String sourceLabel = "رابط خارجي";
    if (extractedUrl.contains("youtube.com") || extractedUrl.contains("youtu.be")) {
      sourceLabel = "فيديو يوتيوب";
    } else if (extractedUrl.contains("facebook.com") || extractedUrl.contains("fb.watch")) {
      sourceLabel = "منشور فيسبوك";
    }

    String initialTitle = rawText.replaceAll(extractedUrl, '').trim();
    if (initialTitle.isEmpty) {
      initialTitle = "مستجد تربوي ($sourceLabel)";
    }

    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('saved_admin_pin') ?? '';

    final titleController = TextEditingController(text: initialTitle);
    final pinController = TextEditingController(text: savedPin);

    if (!mounted) return;

    setState(() {
      _tabController.animateTo(2);
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.campaign, color: Color(0xFF0D47A1)),
              const SizedBox(width: 8),
              Expanded(child: Text("نشر $sourceLabel للجميع")),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("عنوان الخبر أو الفيديو:", style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: titleController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  extractedUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                ),
                const SizedBox(height: 12),
                const Text("رمز المشرف السري:", style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: "أدخل الرمز للنشر السحابي",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send, size: 18),
              label: const Text("نشر للجميع"),
              onPressed: () async {
                if (pinController.text.trim() != _adminPin) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("رمز المشرف غير صحيح!"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                await prefs.setString('saved_admin_pin', pinController.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);

                await _publishToFirebase(
                  title: titleController.text.trim().isEmpty
                      ? initialTitle
                      : titleController.text.trim(),
                  source: sourceLabel,
                  url: extractedUrl,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // إرسال المنشور إلى Firebase ليظهر لدى جميع المستخدمين
  Future<void> _publishToFirebase({
    required String title,
    required String source,
    required String url,
  }) async {
    try {
      final now = DateTime.now();
      final formattedDate =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      final newPost = {
        'title': title,
        'source': source,
        'url': url,
        'date': formattedDate,
        'timestamp': now.millisecondsSinceEpoch,
      };

      final response = await http.post(
        Uri.parse(_firebaseDbUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(newPost),
      );

      if (response.statusCode == 200) {
        await _fetchCloudSharedNews();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("تم النشر بنجاح! يظهر الآن لدى جميع مستخدمي التطبيق."),
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      } else {
        throw Exception("فشل النشر: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تعذر النشر السحابي، تأكد من اتصال الإنترنت."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // جلب المنشورات المشتركة من السحابة لجميع المستخدمين
  Future<void> _fetchCloudSharedNews() async {
    setState(() => _isLoadingCloud = true);
    try {
      final response = await http
          .get(Uri.parse(_firebaseDbUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final List<NewsArticle> loaded = [];

        if (decoded != null && decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              loaded.add(NewsArticle.fromJson(value, id: key));
            }
          });
        }

        // ترتيب المنشورات من الأحدث إلى الأقدم
        setState(() {
          _cloudSharedNews = loaded.reversed.toList();
          _isLoadingCloud = false;
        });
      } else {
        setState(() => _isLoadingCloud = false);
      }
    } catch (e) {
      setState(() => _isLoadingCloud = false);
    }
  }

  // حذف منشور من السحابة (للمشرف فقط)
  Future<void> _confirmDeleteCloudPost(NewsArticle article) async {
    if (article.id == null) return;
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('saved_admin_pin') ?? '';
    final pinController = TextEditingController(text: savedPin);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("حذف المنشور من عند الجميع"),
          content: TextField(
            controller: pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "رمز المشرف للتأكيد",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                if (pinController.text.trim() != _adminPin) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("رمز المشرف غير صحيح!")),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await http.delete(Uri.parse('$_firebaseBaseUrl/${article.id}.json'));
                await _fetchCloudSharedNews();
              },
              child: const Text("حذف نهائي", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchAllData() async {
    _fetchTissemsiltNews();
    _fetchNationalNews();
    _fetchCloudSharedNews();
  }

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
            tooltip: 'تحديث الكل',
            onPressed: _fetchAllData,
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
                label: Text('${_cloudSharedNews.length}'),
                isLabelVisible: _cloudSharedNews.isNotEmpty,
                child: const Icon(Icons.campaign),
              ),
              text: 'مرصودات الإدارة',
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
          _buildCloudSharedListView(),
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

  Widget _buildCloudSharedListView() {
    if (_isLoadingCloud) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_cloudSharedNews.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchCloudSharedNews,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 100),
            Icon(Icons.campaign_outlined, size: 60, color: Colors.blueGrey),
            SizedBox(height: 16),
            Text(
              'لا توجد منشورات إدارية مرصودة حالياً',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'أي فيديو يوتيوب أو منشور فيسبوك يشاركه المشرف سيظهر هنا تلقائياً لدى جميع مستخدمي التطبيق.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchCloudSharedNews,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: _cloudSharedNews.length,
        itemBuilder: (context, index) {
          final item = _cloudSharedNews[index];
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.grey, size: 20),
                    onPressed: () => Share.share('${item.title}\n${item.url}'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: () => _confirmDeleteCloudPost(item),
                  ),
                ],
              ),
              onTap: () => _openUrl(item.url),
            ),
          );
        },
      ),
    );
  }
}