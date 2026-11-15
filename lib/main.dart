import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TissemsiltNewsApp());
}

class TissemsiltNewsApp extends StatelessWidget {
  const TissemsiltNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'راصد التربية - تيسمسيلت',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: const Color(0xFF1A237E),
        scaffoldBackgroundColor: const Color(0xFFF0F2F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox(),
        );
      },
      home: const NewsDashboard(),
    );
  }
}

class NewsDashboard extends StatefulWidget {
  const NewsDashboard({super.key});

  @override
  State<NewsDashboard> createState() => _NewsDashboardState();
}

class _NewsDashboardState extends State<NewsDashboard>
    with SingleTickerProviderStateMixin {
  static const String _firebaseDbUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts.json';
  static const String _firebaseBaseUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts';

  late TabController _tabController;
  late StreamSubscription _intentSub;
  bool isScanning = false;
  String searchQuery = "";
  String selectedTab = "الكل";
  int maxDaysOld = 7;

  List> newsList = [];

  final List<String> tissemsiltKeywords = [
    "تيسمسيلت", "ثنية الحد", "برج بونعامة", "خميستي", "لرجام",
    "عماري", "بوقايد", "الأزهرية", "برج الأمير عبد القادر", "سيدي سليمان",
    "أولاد بسام", "ملعب", "سيدي عابد", "تملاحت", "سيدي بوتشنت",
    "العيون", "اليوسفية", "سيدي العنتري", "معاصم"
  ];

  final List<String> tabs = [
    "الكل",
    "تيسمسيلت",
    "وطني",
    "تقارير متلفزة",
    "فيسبوك"
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          selectedTab = tabs[_tabController.index];
        });
      }
    });
    _loadSavedNews();
    _initSharingIntent();
  }

  // استقبال الروابط والمنشورات المشتركة من فيسبوك ويوتيوب
  void _initSharingIntent() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _openQuickShareFromExternalApp(value.first.path);
        }
      },
      onError: (err) => debugPrint("Share Error: $err"),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _openQuickShareFromExternalApp(value.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

  // فتح نافذة الإضافة والنشر الفوري للجميع عند مشاركة رابط من فيسبوك أو يوتيوب
  void _openQuickShareFromExternalApp(String rawSharedText) {
    if (rawSharedText.trim().isEmpty) return;

    final RegExp urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final Match? match = urlRegExp.firstMatch(rawSharedText);
    final String extractedUrl =
        match != null ? match.group(0)! : rawSharedText.trim();
    final String extractedTitle =
        rawSharedText.replaceAll(extractedUrl, '').trim();

    final bool isYoutube = extractedUrl.contains("youtube.com") ||
        extractedUrl.contains("youtu.be");

    _showAddFacebookModal(
      prefillUrl: extractedUrl,
      prefillTitle: extractedTitle.isNotEmpty
          ? extractedTitle
          : (isYoutube
              ? "فيديو تربوي مرصود عبر يوتيوب"
              : "منشور تربوي مرصود عبر فيسبوك"),
      defaultCategory: isYoutube ? "تقارير متلفزة" : "تيسمسيلت",
    );
  }

  Future<void> _loadSavedNews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedData = prefs.getString('tissemsilt_edu_news_v5');
      if (savedData != null && savedData.isNotEmpty) {
        final decoded = json.decode(savedData) as List;
        if (decoded.isNotEmpty) {
          setState(() {
            newsList =
                decoded.map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      }
    } catch (_) {}

    // جلب المنشورات السحابية المشتركة + تحديث الأخبار الحية تلقائياً
    await _fetchCloudPosts();
    if (newsList.isEmpty) {
      runSmartRadarBot();
    }
  }

  Future<void> _saveNewsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tissemsilt_edu_news_v5', json.encode(newsList));
    } catch (_) {}
  }

  // جلب المنشورات المشتركة من Firebase لتظهر عند جميع المستخدمين
  Future<void> _fetchCloudPosts() async {
    try {
      final response = await http
          .get(Uri.parse(_firebaseDbUrl))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded != null && decoded is Map) {
          decoded.forEach((key, value) {
            if (value is Map) {
              final String title = (value["title"] ?? "").toString();
              final String url = (value["url"] ?? "").toString();
              if (title.isEmpty) return;

              final int ts = (value["timestamp"] is int)
                  ? value["timestamp"] as int
                  : DateTime.now().millisecondsSinceEpoch;
              final parsedDate =
                  DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String();
              final timeInfo = _parseRealTime(parsedDate);

              final existingIndex =
                  newsList.indexWhere((n) => n['cloudId'] == key);
              final postMap = <String, dynamic>{
                "cloudId": key,
                "title": title,
                "summary": (value["summary"] ?? title).toString(),
                "source": (value["source"] ?? "رصد الإدارة المباشر").toString(),
                "category": (value["category"] ?? "تيسمسيلت").toString(),
                "type": (value["type"] ?? "facebook").toString(),
                "time": timeInfo["display"],
                "timestamp": ts,
                "url": url,
                "important": (value["category"] ?? "تيسمسيلت") == "تيسمسيلت",
              };

              if (existingIndex == -1) {
                newsList.insert(0, postMap);
              } else {
                newsList[existingIndex] = postMap;
              }
            }
          });
          newsList.sort((a, b) =>
              ((b['timestamp'] ?? 0) as int).compareTo((a['timestamp'] ?? 0) as int));
          if (mounted) setState(() {});
          await _saveNewsToStorage();
        }
      }
    } catch (_) {}
  }

  // رفع المنشور أو الفيديو إلى Firebase ليظهر لدى جميع المستخدمين فوراً
  Future<void> _publishPostToCloud(Map<String, dynamic> postData) async {
    try {
      final response = await http.post(
        Uri.parse(_firebaseDbUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(postData),
      );
      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        if (resData is Map && resData['name'] != null) {
          postData['cloudId'] = resData['name'];
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("تم النشر السحابي بنجاح! يظهر الآن لدى جميع مستخدمي التطبيق."),
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم الحفظ محلياً (تعذر الوصول للسحابة، تحقق من الإنترنت)."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Map<String, dynamic> _parseRealTime(String rawDate) {
    DateTime? parsed;
    try {
      parsed = DateTime.tryParse(rawDate);
      if (parsed == null) {
        final months = {
          'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
        };
        final parts = rawDate.replaceAll(',', '').split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          int day = int.tryParse(parts[1]) ?? 1;
          int month = months[parts[2]] ?? 1;
          int year = int.tryParse(parts[3]) ?? DateTime.now().year;
          final timeParts = parts[4].split(':');
          int hour = int.tryParse(timeParts[0]) ?? 0;
          int minute =
              timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
          parsed = DateTime.utc(year, month, day, hour, minute).toLocal();
        }
      } else {
        parsed = parsed.toLocal();
      }
    } catch (_) {}

    final now = DateTime.now();
    parsed ??= now;

    final diff = now.difference(parsed);
    String relative = "";
    if (diff.inMinutes < 2) {
      relative = "الآن";
    } else if (diff.inMinutes < 60) {
      relative = "منذ ${diff.inMinutes} دقيقة";
    } else if (diff.inHours < 24) {
      relative = "منذ ${diff.inHours} ساعة";
    } else {
      relative = "منذ ${diff.inDays} يوم";
    }

    String clock =
        "${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
    String fullDate =
        "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ($clock)";

    return {
      "timestamp": parsed.millisecondsSinceEpoch,
      "display": "$relative | $fullDate",
      "daysOld": diff.inDays < 0 ? 0 : diff.inDays,
    };
  }

  String _cleanSummaryText(String rawHtml, String fallbackTitle) {
    String text = rawHtml
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.length < 25 || text == fallbackTitle) {
      return "ملخص الخبر: $fallbackTitle. (اضغط لعرض التفاصيل الكاملة أو فتح التقرير الأصلي).";
    }
    return text.length > 260 ? "${text.substring(0, 260)}..." : text;
  }

  // الروبوت الموسع: اتصال مباشر ومستقر بـ Google News RSS مع فلترة صارمة للتاريخ الحديث
  Future<void> runSmartRadarBot() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'جاري مسح 8 قنوات إخبارية وتلفزيونية (أخبار آخر $maxDaysOld أيام فقط)...'),
          backgroundColor: const Color(0xFF1A237E),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    await _fetchCloudPosts();

    // حساب تاريخ البداية الدقيق بصيغة YYYY-MM-DD لإجبار محرك الأخبار على جلب الحديث فقط
    final DateTime cutoffDate =
        DateTime.now().subtract(Duration(days: maxDaysOld));
    final String afterDateStr =
        "${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}";

    final List> queries = [
      {
        "q": "تيسمسيلت تربية OR مديرية التربية تيسمسيلت after:$afterDateStr",
        "type": "press",
        "forceLocal": true
      },
      {
        "q": "ولاية تيسمسيلت مدارس OR ثانوية OR متوسطة OR ابتدائية after:$afterDateStr",
        "type": "press",
        "forceLocal": true
      },
      {
        "q": "تيسمسيلت (ثنية الحد OR برج بونعامة OR خميستي OR لرجام OR عماري) after:$afterDateStr",
        "type": "press",
        "forceLocal": true
      },
      {
        "q": "وزارة التربية الوطنية الجزائر after:$afterDateStr",
        "type": "press",
        "forceLocal": false
      },
      {
        "q": "وزير التربية الجزائر OR الدخول المدرسي OR البكالوريا OR البيام after:$afterDateStr",
        "type": "press",
        "forceLocal": false
      },
      {
        "q": "مسابقة الأساتذة OR توظيف التربية الجزائر OR مدير متوسطة after:$afterDateStr",
        "type": "press",
        "forceLocal": false
      },
      {
        "q": "(فيديو OR تقرير OR تغطية) قطاع التربية الجزائر OR مدارس تيسمسيلت after:$afterDateStr",
        "type": "tv",
        "forceLocal": false
      },
      {
        "q": "(قناة النهار OR الشروق نيوز OR قناة البلاد OR التلفزيون الجزائري) التربية after:$afterDateStr",
        "type": "tv",
        "forceLocal": false
      },
    ];

    int addedCount = 0;

    for (var queryObj in queries) {
      final String qText = queryObj["q"].toString();
      final String qType = queryObj["type"].toString();
      final bool forceLocal = queryObj["forceLocal"] == true;
      final encodedQuery = Uri.encodeComponent(qText);
      final directRssUrl = Uri.parse(
          'https://news.google.com/rss/search?q=$encodedQuery&hl=ar&gl=DZ&ceid=DZ:ar');

      try {
        final response = await http.get(
          directRssUrl,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
            'Accept': 'application/rss+xml, application/xml, text/xml, */*',
          },
        ).timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final document =
              XmlDocument.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
          final items = document.findAllElements('item');

          for (var node in items) {
            String rawTitle =
                node.findElements('title').firstOrNull?.innerText.trim() ?? "";
            if (rawTitle.isEmpty) continue;

            final String link =
                node.findElements('link').firstOrNull?.innerText.trim() ?? "";
            final String rawDate =
                node.findElements('pubDate').firstOrNull?.innerText.trim() ?? "";
            final String rawDesc =
                node.findElements('description').firstOrNull?.innerText ?? "";
            String extractedSource =
                node.findElements('source').firstOrNull?.innerText.trim() ?? "";

            if (rawTitle.contains(" - ")) {
              final splitParts = rawTitle.split(" - ");
              if (extractedSource.isEmpty) {
                extractedSource = splitParts.last.trim();
              }
              rawTitle =
                  splitParts.sublist(0, splitParts.length - 1).join(" - ").trim();
            }
            if (extractedSource.isEmpty) {
              extractedSource =
                  qType == "tv" ? "تقرير تلفزيوني" : "الصحافة الوطنية";
            }

            final Map<String, dynamic> timeInfo = _parseRealTime(rawDate);
            // استبعاد صارم لأي خبر أقدم من النطاق المحدد
            if ((timeInfo["daysOld"] as int) > maxDaysOld) continue;

            bool exists = newsList.any((n) => n['title'].toString() == rawTitle);
            if (!exists) {
              bool isTissemsilt = forceLocal ||
                  tissemsiltKeywords.any(
                      (k) => rawTitle.contains(k) || rawDesc.contains(k));
              String category = isTissemsilt
                  ? "تيسمسيلت"
                  : (qType == "tv" ? "تقارير متلفزة" : "وطني");

              newsList.add({
                "title": rawTitle,
                "summary": _cleanSummaryText(rawDesc, rawTitle),
                "source": extractedSource,
                "category": category,
                "type": qType,
                "time": timeInfo["display"],
                "timestamp": timeInfo["timestamp"],
                "url": link,
                "important": isTissemsilt
              });
              addedCount++;
            }
          }
        }
      } catch (_) {}
    }

    // إزالة أي أخبار قديمة مخزنة سابقاً تتجاوز النطاق المحدد (ما عدا منشورات الإدارة السحابية)
    newsList.removeWhere((item) {
      if (item['cloudId'] != null) return false;
      final int ts = (item['timestamp'] ?? 0) as int;
      final ageDays = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ts))
          .inDays;
      return ageDays > maxDaysOld;
    });

    // ترتيب صارم من الأحدث إلى الأقدم
    newsList.sort((a, b) {
      int timeA = (a['timestamp'] ?? 0) as int;
      int timeB = (b['timestamp'] ?? 0) as int;
      return timeB.compareTo(timeA);
    });

    await _saveNewsToStorage();

    if (mounted) {
      setState(() => isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'اكتمل الرصد: تم سحب $addedCount خبر وتقرير حديث بالتوقيت الحقيقي.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  void _showArticleSummarySheet(Map<String, dynamic> item) {
    final String type = (item["type"] ?? "press").toString();
    final bool isTv = type == "tv";
    final bool isFb = type == "facebook";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isTv ? Icons.live_tv : (isFb ? Icons.facebook : Icons.summarize),
                    color: isTv ? Colors.red.shade700 : const Color(0xFF1A237E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "بطاقة الملخص الإعلامي - ${(item["source"] ?? "").toString()}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF1A237E)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  )
                ],
              ),
              const Divider(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time,
                        size: 15, color: Colors.deepOrange),
                    const SizedBox(width: 6),
                    Text(
                      "التوقيت الحقيقي للنشر: ${(item["time"] ?? "").toString()}",
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                (item["title"] ?? "").toString(),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTv
                          ? "ملخص التقرير المتلفز / الفيديو:"
                          : "الخلاصة المركزة للخبر:",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF1A237E)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (item["summary"] ?? item["title"] ?? "").toString(),
                      style: const TextStyle(
                          fontSize: 14, height: 1.6, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isTv ? Colors.red.shade700 : const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openNewsLink((item["url"] ?? "").toString());
                      },
                      icon: Icon(
                          isTv ? Icons.play_circle_fill : Icons.open_in_new),
                      label: Text(isTv
                          ? "مشاهدة الفيديو الكامل من المصدر"
                          : "قراءة المقال الكامل من المصدر"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddFacebookModal({
    String prefillUrl = "",
    String prefillTitle = "",
    String defaultCategory = "تيسمسيلت",
  }) {
    final linkController = TextEditingController(text: prefillUrl);
    final titleController = TextEditingController(text: prefillTitle);
    final summaryController = TextEditingController();
    String selectedCategory = defaultCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign,
                          color: Color(0xFF1877F2), size: 28),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "نشر خبر أو فيديو للجميع (فيسبوك / يوتيوب)",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: linkController,
                    decoration: InputDecoration(
                      labelText: "رابط المنشور أو الفيديو",
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: "عنوان الخبر البارز",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summaryController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: "ملخص الخبر (اختياري - يظهر للمطالعين)",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: InputDecoration(
                      labelText: "تصنيف الخبر",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: "تيسمسيلت",
                          child: Text("أخبار تيسمسيلت (أولوية قصوى)")),
                      DropdownMenuItem(
                          value: "وطني",
                          child: Text("أخبار وطنية - وزارة التربية")),
                      DropdownMenuItem(
                          value: "تقارير متلفزة",
                          child: Text("فيديو / تقرير يوتيوب أو تلفزيون")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedCategory = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.send),
                      label: const Text("نشر للجميع الآن",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        if (titleController.text.trim().isEmpty &&
                            linkController.text.trim().isEmpty) return;

                        String finalUrl = linkController.text.trim().isEmpty
                            ? "https://www.facebook.com"
                            : linkController.text.trim();
                        final bool isYt = finalUrl.contains("youtube.com") ||
                            finalUrl.contains("youtu.be");
                        final int nowTs = DateTime.now().millisecondsSinceEpoch;
                        final nowInfo =
                            _parseRealTime(DateTime.now().toIso8601String());

                        final String finalTitle =
                            titleController.text.trim().isEmpty
                                ? (isYt
                                    ? "فيديو تربوي مرصود عبر يوتيوب"
                                    : "منشور تربوي مرصود عبر فيسبوك")
                                : titleController.text.trim();

                        final String finalSummary =
                            summaryController.text.trim().isEmpty
                                ? finalTitle
                                : summaryController.text.trim();

                        final String sourceName =
                            isYt ? "رصد يوتيوب مباشر" : "رصد فيسبوك مباشر";
                        final String itemType =
                            (selectedCategory == "تقارير متلفزة" || isYt)
                                ? "tv"
                                : "facebook";

                        final newPost = <String, dynamic>{
                          "title": finalTitle,
                          "summary": finalSummary,
                          "source": sourceName,
                          "category": selectedCategory,
                          "type": itemType,
                          "time": nowInfo["display"],
                          "timestamp": nowTs,
                          "url": finalUrl,
                          "important": selectedCategory == "تيسمسيلت",
                        };

                        setState(() {
                          newsList.insert(0, newPost);
                        });
                        Navigator.pop(context);
                        await _publishPostToCloud(newPost);
                        await _saveNewsToStorage();
                      },
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openNewsLink(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _intentSub.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List> filteredNews = newsList.where((item) {
      bool matchesTab = true;
      if (selectedTab == "فيسبوك") {
        matchesTab = item["type"] == "facebook" || item["cloudId"] != null;
      } else if (selectedTab != "الكل") {
        matchesTab = item["category"] == selectedTab;
      }

      bool matchesSearch = searchQuery.isEmpty ||
          item["title"].toString().contains(searchQuery) ||
          (item["summary"] ?? "").toString().contains(searchQuery) ||
          item["source"].toString().contains(searchQuery);

      return matchesTab && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("راصد التربية - ولاية تيسمسيلت",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(
              "إجمالي الأخبار المرصودة: ${newsList.length} خبر حديث",
              style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: "تحديد حداثة الأخبار",
            icon: const Icon(Icons.history_toggle_off, color: Colors.white),
            onSelected: (days) {
              setState(() {
                maxDaysOld = days;
                newsList.removeWhere((item) => item['cloudId'] == null);
              });
              runSmartRadarBot();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                  value: 1, child: Text("أخبار آخر 24 ساعة فقط (عاجل)")),
              const PopupMenuItem(value: 3, child: Text("أخبار آخر 3 أيام")),
              const PopupMenuItem(
                  value: 7, child: Text("أخبار هذا الأسبوع (7 أيام)")),
            ],
          ),
          IconButton(
            onPressed: isScanning ? null : runSmartRadarBot,
            tooltip: "تحديث وسحب الأخبار الجديدة الآن",
            icon: isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.amber, strokeWidth: 2))
                : const Icon(Icons.radar, color: Colors.amberAccent, size: 28),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextField(
                  onChanged: (val) => setState(() => searchQuery = val),
                  decoration: InputDecoration(
                    hintText:
                        "ابحث في العناوين والملخصات (تيسمسيلت، امتحان، بلدية...)",
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFF1A237E)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Container(
                color: Colors.white,
                width: double.infinity,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: const Color(0xFF1A237E),
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: const Color(0xFFD97706),
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(text: "الكل"),
                    Tab(text: "تيسمسيلت"),
                    Tab(text: "وطني"),
                    Tab(text: "تقارير متلفزة"),
                    Tab(text: "فيسبوك"),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: isScanning && newsList.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text(
                      "جاري سحب وتلخيص أحدث الأخبار والتقارير بالتوقيت الحقيقي..."),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: runSmartRadarBot,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filteredNews.length,
                itemBuilder: (context, index) {
                  final item = filteredNews[index];
                  final bool isImportant = item["important"] == true;
                  final String type = (item["type"] ?? "press").toString();

                  IconData badgeIcon = Icons.article;
                  Color badgeColor = Colors.teal.shade700;
                  if (type == "facebook") {
                    badgeIcon = Icons.facebook;
                    badgeColor = const Color(0xFF1877F2);
                  } else if (type == "tv") {
                    badgeIcon = Icons.live_tv;
                    badgeColor = Colors.red.shade700;
                  }

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isImportant
                            ? Colors.amber.shade700
                            : Colors.transparent,
                        width: isImportant ? 1.5 : 0,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showArticleSummarySheet(item),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(badgeIcon, size: 17, color: badgeColor),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    (item["source"] ?? "").toString(),
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: badgeColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isImportant)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      "تيسمسيلت",
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade800),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.schedule,
                                    size: 13, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  (item["time"] ?? "").toString(),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              (item["title"] ?? "").toString(),
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  height: 1.35),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                (item["summary"] ?? item["title"] ?? "")
                                    .toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade800,
                                    height: 1.4),
                              ),
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () =>
                                      _showArticleSummarySheet(item),
                                  icon: Icon(
                                      type == "tv"
                                          ? Icons.ondemand_video
                                          : Icons.menu_book,
                                      size: 16),
                                  label: Text(type == "tv"
                                      ? "ملخص التقرير والفيديو"
                                      : "قراءة الملخص"),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openNewsLink(
                                      (item["url"] ?? "").toString()),
                                  icon: const Icon(Icons.open_in_new, size: 15),
                                  label: const Text("المصدر"),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent, size: 19),
                                  onPressed: () async {
                                    final cloudId = item['cloudId'];
                                    setState(() {
                                      newsList.remove(item);
                                    });
                                    await _saveNewsToStorage();
                                    if (cloudId != null) {
                                      try {
                                        await http.delete(Uri.parse(
                                            '$_firebaseBaseUrl/$cloudId.json'));
                                      } catch (_) {}
                                    }
                                  },
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1877F2),
        foregroundColor: Colors.white,
        onPressed: () => _showAddFacebookModal(),
        icon: const Icon(Icons.add_link),
        label: const Text("إضافة من فيسبوك",
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}