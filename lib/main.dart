import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RabahEduNewsApp());
}

class RabahEduNewsApp extends StatelessWidget {
  const RabahEduNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تطبيق Rabah لأخبار التربية والتعليم',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F2557),
          primary: const Color(0xFF0F2557),
          secondary: const Color(0xFFD97706),
          surface: const Color(0xFFF4F6FB),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F2557),
          foregroundColor: Colors.white,
          elevation: 0,
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
  State createState() => _NewsDashboardState();
}

class _NewsDashboardState extends State
    with SingleTickerProviderStateMixin {
  static const String _firebaseDbUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts.json';
  static const String _firebaseBaseUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts';

  late TabController _tabController;
  late StreamSubscription _intentSub;
  final TextEditingController _searchController = TextEditingController();

  bool isScanning = false;
  bool isCustomSearching = false;
  String searchQuery = "";
  String selectedTab = "الكل";
  int maxDaysOld = 7;

  List newsList = [];

  final List tissemsiltKeywords = [
    "تيسمسيلت", "ثنية الحد", "برج بونعامة", "خميستي", "لرجام",
    "عماري", "بوقايد", "الأزهرية", "برج الأمير عبد القادر", "سيدي سليمان",
    "أولاد بسام", "ملعب", "سيدي عابد", "تملاحت", "سيدي بوتشنت",
    "العيون", "اليوسفية", "سيدي العنتري", "معاصم"
  ];

  final List tabs = [
    "الكل",
    "تيسمسيلت",
    "الصحافة الوطنية",
    "تقارير وفيديوهات",
    "فيسبوك"
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          selectedTab = tabs[_tabController.index].toString();
        });
      }
    });
    _loadSavedNews();
    _initSharingIntent();
  }

  void _initSharingIntent() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (value) {
        if (value.isNotEmpty) {
          _openQuickShareFromExternalApp(value.first.path);
        }
      },
      onError: (err) => debugPrint("Share Error: $err"),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (value) {
        if (value.isNotEmpty) {
          _openQuickShareFromExternalApp(value.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

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
              ? "فيديو تربوي عبر يوتيوب"
              : "منشور تربوي عبر فيسبوك"),
      defaultCategory: isYoutube ? "تقارير وفيديوهات" : "تيسمسيلت",
    );
  }

  Future _loadSavedNews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedData = prefs.getString('rabah_edu_news_v2');
      if (savedData != null && savedData.isNotEmpty) {
        final decoded = json.decode(savedData) as List;
        if (decoded.isNotEmpty) {
          setState(() {
            newsList = decoded;
          });
        }
      }
    } catch (_) {}

    await _fetchCloudPosts();
    if (newsList.isEmpty) {
      runFastParallelEngine();
    }
  }

  Future _saveNewsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rabah_edu_news_v2', json.encode(newsList));
    } catch (_) {}
  }

  Future _fetchCloudPosts() async {
    try {
      final response = await http
          .get(Uri.parse(_firebaseDbUrl))
          .timeout(const Duration(seconds: 8));
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
              final postMap = {
                "cloudId": key,
                "title": title,
                "summary": (value["summary"] ?? title).toString(),
                "source": (value["source"] ?? "إدارة التطبيق").toString(),
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

  Future _publishPostToCloud(Map postData) async {
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
              content: const Text("تم النشر بنجاح! يظهر الآن لدى جميع مستخدمي تطبيق Rabah."),
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

  Map _parseRealTime(String rawDate) {
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

  // استخراج وتنسيق ملخص غني ومفهوم من متن الخبر القادم من المصدر
  String _cleanSummaryText(String rawHtml, String fallbackTitle, String sourceName) {
    String text = rawHtml
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&laquo;', '«')
        .replaceAll('&raquo;', '»')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // إزالة تكرار العنوان واسم المصدر من بداية الملخص إن وجدا
    if (text.startsWith(fallbackTitle)) {
      text = text.substring(fallbackTitle.length).trim();
    }
    if (text.endsWith(sourceName)) {
      text = text.substring(0, text.length - sourceName.length).trim();
    }
    text = text.replaceAll(RegExp(r'^[-–—:\s]+'), '').trim();

    if (text.length < 25) {
      return "تغطية إخبارية حول: $fallbackTitle — وردت عبر ($sourceName) ضمن متابعة مستجدات قطاع التربية والتعليم. اضغط لفتح المقال الكامل.";
    }
    return text.length > 380 ? "${text.substring(0, 380)}..." : text;
  }

  String _extractTagContent(String xml, String tag) {
    final startTag = "<$tag>";
    final endTag = "</$tag>";
    int startIndex = xml.indexOf(startTag);
    if (startIndex == -1) {
      startIndex = xml.indexOf("<$tag ");
      if (startIndex != -1) {
        startIndex = xml.indexOf(">", startIndex);
        if (startIndex != -1) startIndex += 1;
      }
    } else {
      startIndex += startTag.length;
    }
    if (startIndex == -1) return "";
    int endIndex = xml.indexOf(endTag, startIndex);
    if (endIndex == -1) return "";
    return xml
        .substring(startIndex, endIndex)
        .replaceAll("<![CDATA[", "")
        .replaceAll("]]>", "")
        .trim();
  }

  Future<List> _fetchSingleChannel(Map queryObj) async {
    final String qText = queryObj["q"].toString();
    final String qType = queryObj["type"].toString();
    final bool forceLocal = queryObj["forceLocal"] == true;
    final encodedQuery = Uri.encodeComponent(qText);
    final targetRss =
        'https://news.google.com/rss/search?q=$encodedQuery&hl=ar&gl=DZ&ceid=DZ:ar';

    final rss2jsonUrl = Uri.parse(
        'https://api.rss2json.com/v1/api.json?rss_url=${Uri.encodeComponent(targetRss)}');
    final allOriginsUrl = Uri.parse(
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(targetRss)}');

    List results = [];
    bool fetched = false;

    try {
      final response =
          await http.get(rss2jsonUrl).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final Map data = json.decode(utf8.decode(response.bodyBytes)) as Map;
        if (data["status"] == "ok" && data["items"] != null) {
          fetched = true;
          final List items = data["items"] as List;
          for (var item in items) {
            final String rawTitle = (item["title"] ?? "").toString().trim();
            if (rawTitle.isEmpty) continue;

            String cleanTitle = rawTitle;
            String extractedSource =
                qType == "tv" ? "تقرير تلفزيوني / فيديو" : "الصحافة المكتوبة";
            if (rawTitle.contains(" - ")) {
              final splitParts = rawTitle.split(" - ");
              extractedSource = splitParts.last.trim();
              cleanTitle =
                  splitParts.sublist(0, splitParts.length - 1).join(" - ").trim();
            }

            final String link = (item["link"] ?? "").toString().trim();
            final String rawDate = (item["pubDate"] ?? "").toString();
            final String rawDesc =
                (item["description"] ?? item["content"] ?? "").toString();

            final Map timeInfo = _parseRealTime(rawDate);
            if ((timeInfo["daysOld"] as int) > maxDaysOld) continue;

            bool isTissemsilt = forceLocal ||
                tissemsiltKeywords.any((k) =>
                    cleanTitle.contains(k.toString()) ||
                    rawDesc.contains(k.toString()));
            bool isVideoItem = qType == "tv" ||
                link.contains("youtube.com") ||
                link.contains("youtu.be") ||
                cleanTitle.contains("فيديو") ||
                cleanTitle.contains("تقرير") ||
                cleanTitle.contains("شاهد");

            String category = isTissemsilt
                ? "تيسمسيلت"
                : (isVideoItem ? "تقارير وفيديوهات" : "الصحافة الوطنية");

            results.add({
              "title": cleanTitle,
              "summary": _cleanSummaryText(rawDesc, cleanTitle, extractedSource),
              "source": extractedSource,
              "category": category,
              "type": isVideoItem ? "tv" : "press",
              "time": timeInfo["display"],
              "timestamp": timeInfo["timestamp"],
              "url": link,
              "important": isTissemsilt
            });
          }
        }
      }
    } catch (_) {}

    if (!fetched) {
      try {
        final resp =
            await http.get(allOriginsUrl).timeout(const Duration(seconds: 7));
        if (resp.statusCode == 200) {
          final xmlBody = utf8.decode(resp.bodyBytes, allowMalformed: true);
          final parts = xmlBody.split("<item>");
          for (int i = 1; i < parts.length && i <= 15; i++) {
            final itemXml = parts[i];
            String rawTitle = _extractTagContent(itemXml, "title");
            final link = _extractTagContent(itemXml, "link");
            final rawDate = _extractTagContent(itemXml, "pubDate");
            final rawDesc = _extractTagContent(itemXml, "description");
            String source = _extractTagContent(itemXml, "source");

            if (rawTitle.isEmpty) continue;
            if (source.isEmpty && rawTitle.contains(" - ")) {
              final sp = rawTitle.split(" - ");
              source = sp.last.trim();
              rawTitle = sp.sublist(0, sp.length - 1).join(" - ").trim();
            }
            if (source.isEmpty) {
              source = qType == "tv" ? "تقرير تلفزيوني" : "الصحافة المكتوبة";
            }

            final Map timeInfo = _parseRealTime(rawDate);
            if ((timeInfo["daysOld"] as int) > maxDaysOld) continue;

            bool isTissemsilt = forceLocal ||
                tissemsiltKeywords.any((k) =>
                    rawTitle.contains(k.toString()) ||
                    rawDesc.contains(k.toString()));
            bool isVideoItem = qType == "tv" ||
                link.contains("youtube.com") ||
                link.contains("youtu.be") ||
                rawTitle.contains("فيديو") ||
                rawTitle.contains("تقرير");

            results.add({
              "title": rawTitle,
              "summary": _cleanSummaryText(rawDesc, rawTitle, source),
              "source": source,
              "category": isTissemsilt
                  ? "تيسمسيلت"
                  : (isVideoItem ? "تقارير وفيديوهات" : "الصحافة الوطنية"),
              "type": isVideoItem ? "tv" : "press",
              "time": timeInfo["display"],
              "timestamp": timeInfo["timestamp"],
              "url": link,
              "important": isTissemsilt
            });
          }
        }
      } catch (_) {}
    }

    return results;
  }

  // محرك الجلب المتوازي الموسع (16 قناة تغطي كل مصطلحات التربية والتعليم في الجزائر)
  Future runFastParallelEngine() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    await _fetchCloudPosts();

    final String timeFilter = "when:${maxDaysOld}d";

    final List queries = [
      // 1. أخبار تيسمسيلت وبلدياتها
      {"q": "تيسمسيلت تربية OR مديرية التربية تيسمسيلت $timeFilter", "type": "press", "forceLocal": true},
      {"q": "ولاية تيسمسيلت مدارس OR ثانوية OR متوسطة OR ابتدائية $timeFilter", "type": "press", "forceLocal": true},
      {"q": "تيسمسيلت (ثنية الحد OR برج بونعامة OR خميستي OR لرجام OR عماري) $timeFilter", "type": "press", "forceLocal": true},

      // 2. الوزارة والمديريات الولائية والقرارات الرسمية
      {"q": "وزارة التربية الوطنية الجزائر OR وزير التربية $timeFilter", "type": "press", "forceLocal": false},
      {"q": "مديرية التربية الجزائر OR مديريات التربية الولائية $timeFilter", "type": "press", "forceLocal": false},
      {"q": "قطاع التربية والتعليم في الجزائر OR المنظومة التربوية $timeFilter", "type": "press", "forceLocal": false},

      // 3. الامتحانات الوطنية والتقييمات البيداغوجية
      {"q": "البكالوريا الجزائر OR شهادة التعليم المتوسط OR البيام $timeFilter", "type": "press", "forceLocal": false},
      {"q": "تقييم المكتسبات OR الاختبارات الفصلية OR العطل المدرسية الجزائر $timeFilter", "type": "press", "forceLocal": false},

      // 4. المسابقات المهنية، التوظيف، والرتب الإدارية والتربوية
      {"q": "مسابقة الأساتذة OR توظيف التربية الجزائر OR الإدماج $timeFilter", "type": "press", "forceLocal": false},
      {"q": "مدير متوسطة OR مدير ثانوية OR مفتش التربية OR أستاذ مكون الجزائر $timeFilter", "type": "press", "forceLocal": false},
      {"q": "مشرف التربية OR مستشار التوجيه OR مقتصد الجزائر $timeFilter", "type": "press", "forceLocal": false},

      // 5. الرقمنة، الخدمات الاجتماعية، والنقابات
      {"q": "فضاء الأولياء OR الأرضية الرقمية وزارة التربية OR كشف النقاط $timeFilter", "type": "press", "forceLocal": false},
      {"q": "منحة التمدرس OR الكتاب المدرسي OR المطاعم المدرسية الجزائر $timeFilter", "type": "press", "forceLocal": false},
      {"q": "نقابات التربية الجزائر OR القانون الأساسي لعمال التربية $timeFilter", "type": "press", "forceLocal": false},

      // 6. تقارير متلفزة وفيديوهات يوتيوب حول التربية ومديرياتها
      {"q": "(تقرير OR فيديو OR روبورتاج) مديرية التربية الجزائر OR وزارة التربية $timeFilter", "type": "tv", "forceLocal": false},
      {"q": "(قناة النهار OR الشروق نيوز OR قناة البلاد OR التلفزيون الجزائري) التربية $timeFilter", "type": "tv", "forceLocal": false},
    ];

    final List<List> allBatches =
        await Future.wait(queries.map((q) => _fetchSingleChannel(q as Map)));

    int addedCount = 0;
    for (var batch in allBatches) {
      for (var item in batch) {
        final String title = (item['title'] ?? '').toString();
        bool exists = newsList.any((n) => n['title'].toString() == title);
        if (!exists && title.isNotEmpty) {
          newsList.add(item);
          addedCount++;
        }
      }
    }

    newsList.removeWhere((item) {
      if (item['cloudId'] != null) return false;
      final int ts = (item['timestamp'] ?? 0) as int;
      final ageDays = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ts))
          .inDays;
      return ageDays > maxDaysOld;
    });

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
              'تم التحديث الفوري: إضافة $addedCount خبر وتقرير تربوي جديد.'),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future _searchCustomTopicOnline(String topic) async {
    final cleanTopic = topic.trim();
    if (cleanTopic.isEmpty || isCustomSearching) return;

    setState(() => isCustomSearching = true);

    final customQueries = [
      {"q": "$cleanTopic التربية الجزائر", "type": "press", "forceLocal": cleanTopic.contains("تيسمسيلت")},
      {"q": "$cleanTopic فيديو OR تقرير OR يوتيوب", "type": "tv", "forceLocal": cleanTopic.contains("تيسمسيلت")},
    ];

    final batches = await Future.wait(
        customQueries.map((q) => _fetchSingleChannel(q as Map)));

    int found = 0;
    for (var batch in batches) {
      for (var item in batch) {
        final String title = (item['title'] ?? '').toString();
        if (!newsList.any((n) => n['title'].toString() == title)) {
          newsList.insert(0, item);
          found++;
        }
      }
    }

    await _saveNewsToStorage();
    if (mounted) {
      setState(() => isCustomSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(found > 0
              ? 'تم العثور على $found نتيجة جديدة حول "$cleanTopic"'
              : 'تم عرض النتائج المطابقة لـ "$cleanTopic" في القائمة'),
          backgroundColor: const Color(0xFF0F2557),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showArticleSummarySheet(Map item) {
    final String type = (item["type"] ?? "press").toString();
    final bool isTv = type == "tv";
    final bool isFb = type == "facebook";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(
                    isTv
                        ? Icons.ondemand_video
                        : (isFb ? Icons.facebook : Icons.newspaper),
                    color: isTv ? Colors.red.shade700 : const Color(0xFF0F2557),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (item["source"] ?? "").toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0F2557)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  )
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time,
                        size: 15, color: Colors.deepOrange),
                    const SizedBox(width: 6),
                    Text(
                      (item["time"] ?? "").toString(),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "عنوان الخبر:",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                (item["title"] ?? "").toString(),
                style: const TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F2557),
                    height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notes,
                            size: 16, color: Colors.amber.shade800),
                        const SizedBox(width: 6),
                        Text(
                          isTv ? "ملخص التقرير / الفيديو:" : "ملخص الخبر:",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (item["summary"] ?? item["title"] ?? "").toString(),
                      style: const TextStyle(
                          fontSize: 14.5, height: 1.65, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isTv ? Colors.red.shade700 : const Color(0xFF0F2557),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openNewsLink((item["url"] ?? "").toString());
                  },
                  icon: Icon(
                      isTv ? Icons.play_circle_fill : Icons.open_in_new),
                  label: Text(
                    isTv
                        ? "مشاهدة التقرير / الفيديو كاملاً"
                        : "قراءة المقال كاملاً من المصدر",
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                      const Icon(Icons.share,
                          color: Color(0xFF1877F2), size: 26),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "نشر خبر أو فيديو للجميع",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: linkController,
                    decoration: InputDecoration(
                      labelText: "رابط المنشور أو الفيديو (فيسبوك / يوتيوب)",
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: "عنوان الخبر",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summaryController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "ملخص الخبر (يظهر للمطالعين داخل البطاقة)",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField(
                    value: selectedCategory,
                    decoration: InputDecoration(
                      labelText: "القسم المناسب",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: "تيسمسيلت",
                          child: Text("أخبار تيسمسيلت (أولوية)")),
                      DropdownMenuItem(
                          value: "الصحافة الوطنية",
                          child: Text("الصحافة الوطنية - وزارة التربية")),
                      DropdownMenuItem(
                          value: "تقارير وفيديوهات",
                          child: Text("تقارير متلفزة وفيديوهات")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedCategory = val.toString());
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F2557),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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
                                    ? "فيديو تربوي عبر يوتيوب"
                                    : "منشور تربوي عبر فيسبوك")
                                : titleController.text.trim();

                        final String finalSummary =
                            summaryController.text.trim().isEmpty
                                ? "منشور تربوي مشارك عبر بوابة التطبيق — اضغط لفتح الرابط الأصلي ومتابعة التفاصيل."
                                : summaryController.text.trim();

                        final String sourceName =
                            isYt ? "قناة يوتيوب التربوية" : "بوابة فيسبوك التربوية";
                        final String itemType =
                            (selectedCategory == "تقارير وفيديوهات" || isYt)
                                ? "tv"
                                : "facebook";

                        final newPost = {
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

  Future _openNewsLink(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _intentSub.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List filteredNews = newsList.where((item) {
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(178),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A1931), Color(0xFF185ADB)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.school,
                            color: Colors.amberAccent, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "تطبيق Rabah لأخبار التربية والتعليم",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              "متابعة شاملة • ${newsList.length} خبر وتقرير",
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.amberAccent),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton(
                        tooltip: "الفترة الزمنية",
                        icon: const Icon(Icons.tune, color: Colors.white),
                        onSelected: (days) {
                          setState(() {
                            maxDaysOld = int.parse(days.toString());
                            newsList
                                .removeWhere((item) => item['cloudId'] == null);
                          });
                          runFastParallelEngine();
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                              value: 1, child: Text("أخبار آخر 24 ساعة (عاجل)")),
                          PopupMenuItem(
                              value: 3, child: Text("أخبار آخر 3 أيام")),
                          PopupMenuItem(
                              value: 7, child: Text("أخبار الأسبوع (7 أيام)")),
                        ],
                      ),
                      IconButton(
                        onPressed: isScanning ? null : runFastParallelEngine,
                        tooltip: "تحديث فوري",
                        icon: isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.amberAccent, strokeWidth: 2))
                            : const Icon(Icons.sync,
                                color: Colors.amberAccent, size: 26),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => searchQuery = val),
                      onSubmitted: (val) => _searchCustomTopicOnline(val),
                      decoration: InputDecoration(
                        hintText: "ابحث في العناوين (مسابقة، مدير، منحة، بكالوريا...)",
                        hintStyle: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade500),
                        prefixIcon: const Icon(Icons.search,
                            color: Color(0xFF0F2557), size: 20),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (searchQuery.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 18, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => searchQuery = "");
                                },
                              ),
                            InkWell(
                              onTap: () =>
                                  _searchCustomTopicOnline(_searchController.text),
                              child: Container(
                                margin: const EdgeInsets.all(5),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD97706),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: isCustomSearching
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2))
                                    : const Text(
                                        "بحث حي",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Colors.amberAccent,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.amberAccent,
                  indicatorWeight: 3,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5),
                  tabs: const [
                    Tab(text: "الكل"),
                    Tab(text: "تيسمسيلت"),
                    Tab(text: "الصحافة الوطنية"),
                    Tab(text: "تقارير وفيديوهات"),
                    Tab(text: "فيسبوك"),
                  ],
                ),
              ],
            ),
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
                    "جاري جلب أحدث الأخبار والتقارير التربوية...",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          : filteredNews.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.manage_search,
                            size: 64, color: Colors.indigo.shade200),
                        const SizedBox(height: 12),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'لا توجد نتائج محلية لـ "$searchQuery"'
                              : 'لا توجد أخبار في هذا القسم حالياً',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (searchQuery.isNotEmpty)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                _searchCustomTopicOnline(searchQuery),
                            icon: const Icon(Icons.travel_explore),
                            label: Text('ابحث في الإنترنت عن "$searchQuery"'),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: runFastParallelEngine,
                            icon: const Icon(Icons.refresh),
                            label: const Text("تحديث الأخبار الآن"),
                          ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: runFastParallelEngine,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                    itemCount: filteredNews.length,
                    itemBuilder: (context, index) {
                      final item = filteredNews[index] as Map;
                      final bool isImportant = item["important"] == true;
                      final String type = (item["type"] ?? "press").toString();

                      IconData badgeIcon = Icons.newspaper;
                      Color badgeColor = const Color(0xFF0D9488);
                      if (type == "facebook") {
                        badgeIcon = Icons.facebook;
                        badgeColor = const Color(0xFF1877F2);
                      } else if (type == "tv") {
                        badgeIcon = Icons.ondemand_video;
                        badgeColor = const Color(0xFFDC2626);
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isImportant
                                ? Colors.amber.shade600
                                : Colors.grey.shade200,
                            width: isImportant ? 1.5 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _showArticleSummarySheet(item),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(badgeIcon,
                                          size: 16, color: badgeColor),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        (item["source"] ?? "").toString(),
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                            color: badgeColor),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isImportant)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          "تيسمسيلت",
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.schedule,
                                        size: 13, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(
                                      (item["time"] ?? "").toString(),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // عنوان الخبر البارز
                                Text(
                                  (item["title"] ?? "").toString(),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F2557),
                                      height: 1.35),
                                ),
                                const SizedBox(height: 8),
                                // صندوق ملخص الخبر الواضح
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.blueGrey.shade50),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "ملخص الخبر:",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        (item["summary"] ?? item["title"] ?? "")
                                            .toString(),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.grey.shade800,
                                            height: 1.45),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          _showArticleSummarySheet(item),
                                      icon: Icon(
                                          type == "tv"
                                              ? Icons.play_circle_outline
                                              : Icons.article_outlined,
                                          size: 17),
                                      label: Text(
                                        type == "tv"
                                            ? "ملخص الفيديو"
                                            : "قراءة الملخص الكامل",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _openNewsLink(
                                          (item["url"] ?? "").toString()),
                                      icon:
                                          const Icon(Icons.open_in_new, size: 15),
                                      label: const Text("المصدر"),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.redAccent, size: 20),
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
        backgroundColor: const Color(0xFF0F2557),
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () => _showAddFacebookModal(),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text("إضافة منشور / فيديو",
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}