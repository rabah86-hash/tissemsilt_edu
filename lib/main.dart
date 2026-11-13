import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  State createState() => _NewsDashboardState();
}

class _NewsDashboardState extends State
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isScanning = false;
  String searchQuery = "";
  String selectedTab = "الكل";
  int maxDaysOld = 7; // جلب أخبار آخر 7 أيام فقط افتراضياً (قابلة للتغيير إلى 24 ساعة)

  List newsList = [];

  final List tissemsiltKeywords = [
    "تيسمسيلت", "ثنية الحد", "برج بونعامة", "خميستي", "لرجام",
    "عماري", "بوقايد", "الأزهرية", "برج الأمير عبد القادر", "سيدي سليمان",
    "أولاد بسام", "ملعب", "سيدي عابد", "تملاحت", "سيدي بوتشنت",
    "العيون", "اليوسفية", "سيدي العنتري", "لرجام", "معاصم"
  ];

  final List tabs = [
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
          selectedTab = tabs[_tabController.index].toString();
        });
      }
    });
    _loadSavedNews();
  }

  Future _loadSavedNews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedData = prefs.getString('tissemsilt_edu_news_v4');
      if (savedData != null && savedData.isNotEmpty) {
        final decoded = json.decode(savedData) as List;
        if (decoded.isNotEmpty) {
          setState(() {
            newsList = decoded;
          });
          return;
        }
      }
    } catch (_) {}
    // تشغيل الروبوت تلقائياً عند فتح التطبيق لأول مرة لجلب الأخبار الحية فوراً
    Future.delayed(const Duration(milliseconds: 600), () {
      runSmartRadarBot();
    });
  }

  Future _saveNewsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tissemsilt_edu_news_v4', json.encode(newsList));
    } catch (_) {}
  }

  // تحويل توقيت النشر الأصلي (GMT/RFC822 أو ISO) إلى توقيت الجزائر الحقيقي وحساب الفرق
  Map _parseRealTime(String rawDate) {
    DateTime? parsed;
    try {
      parsed = DateTime.tryParse(rawDate);
      if (parsed == null) {
        // تحليل صيغة RSS القياسية مثل: Fri, 13 Nov 2026 14:22:10 GMT
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
          int minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
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

    String clock = "${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
    String fullDate = "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ($clock)";

    return {
      "timestamp": parsed.millisecondsSinceEpoch,
      "display": "$relative | $fullDate",
      "daysOld": diff.inDays,
    };
  }

  // تنظيف HTML واستخراج ملخص نظيف ومفهوم للخبر أو التقرير
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

  // الروبوت الموسع: 8 قنوات بحث متوازية مع فلترة الأخبار الجديدة فقط وحساب الوقت الحقيقي
  Future runSmartRadarBot() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('جاري مسح 8 قنوات إخبارية وتلفزيونية (أخبار آخر $maxDaysOld أيام فقط)...'),
        backgroundColor: const Color(0xFF1A237E),
        duration: const Duration(seconds: 4),
      ),
    );

    final String timeFilter = "when:${maxDaysOld}d";

    // توسيع الاستعلامات لجلب أكبر كمية من الأخبار الجديدة في تيسمسيلت والجزائر
    final List queries = [
      {"q": "تيسمسيلت تربية OR مديرية التربية تيسمسيلت $timeFilter", "type": "press", "forceLocal": true},
      {"q": "ولاية تيسمسيلت مدارس OR ثانوية OR متوسطة OR ابتدائية $timeFilter", "type": "press", "forceLocal": true},
      {"q": "تيسمسيلت (ثنية الحد OR برج بونعامة OR خميستي OR لرجام OR عماري) $timeFilter", "type": "press", "forceLocal": true},
      {"q": "وزارة التربية الوطنية الجزائر $timeFilter", "type": "press", "forceLocal": false},
      {"q": "وزير التربية الجزائر OR الدخول المدرسي OR امتحانات البكالوريا البيام $timeFilter", "type": "press", "forceLocal": false},
      {"q": "مسابقة الأساتذة OR توظيف التربية الجزائر OR مستشار التوجيه OR مدير متوسطة $timeFilter", "type": "press", "forceLocal": false},
      {"q": "(فيديو OR تقرير OR تغطية) قطاع التربية الجزائر OR مدارس تيسمسيلت $timeFilter", "type": "tv", "forceLocal": false},
      {"q": "(قناة النهار OR الشروق نيوز OR قناة البلاد OR التلفزيون الجزائري) التربية $timeFilter", "type": "tv", "forceLocal": false},
    ];

    int addedCount = 0;

    for (var queryObj in queries) {
      final String qText = queryObj["q"].toString();
      final String qType = queryObj["type"].toString();
      final bool forceLocal = queryObj["forceLocal"] == true;
      final encodedQuery = Uri.encodeComponent(qText);
      final targetRss = 'https://news.google.com/rss/search?q=$encodedQuery&hl=ar&gl=DZ&ceid=DZ:ar';

      // استخدام بوابة تحويل RSS إلى JSON مع بديل XML لضمان جلب أقصى عدد من الأخبار
      final rss2jsonUrl = Uri.parse('https://api.rss2json.com/v1/api.json?rss_url=${Uri.encodeComponent(targetRss)}');
      final allOriginsUrl = Uri.parse('https://api.allorigins.win/raw?url=${Uri.encodeComponent(targetRss)}');

      bool fetchedFromFirst = false;

      try {
        final response = await http.get(rss2jsonUrl).timeout(const Duration(seconds: 7));
        if (response.statusCode == 200) {
          final Map data = json.decode(utf8.decode(response.bodyBytes)) as Map;
          if (data["status"] == "ok" && data["items"] != null) {
            fetchedFromFirst = true;
            final List items = data["items"] as List;
            for (var item in items) {
              final String rawTitle = (item["title"] ?? "").toString().trim();
              if (rawTitle.isEmpty) continue;

              // فصل اسم الجريدة عن العنوان إن وجد
              String cleanTitle = rawTitle;
              String extractedSource = qType == "tv" ? "تقرير تلفزيوني" : "الصحافة الوطنية";
              if (rawTitle.contains(" - ")) {
                final splitParts = rawTitle.split(" - ");
                extractedSource = splitParts.last.trim();
                cleanTitle = splitParts.sublist(0, splitParts.length - 1).join(" - ").trim();
              }

              final String link = (item["link"] ?? "").toString().trim();
              final String rawDate = (item["pubDate"] ?? "").toString();
              final String rawDesc = (item["description"] ?? item["content"] ?? "").toString();

              final Map timeInfo = _parseRealTime(rawDate);
              if ((timeInfo["daysOld"] as int) > maxDaysOld) continue; // استبعاد الأخبار القديمة صارم

              bool exists = newsList.any((n) => n['title'].toString() == cleanTitle);
              if (!exists) {
                bool isTissemsilt = forceLocal ||
                    tissemsiltKeywords.any((k) => cleanTitle.contains(k.toString()) || rawDesc.contains(k.toString()));
                String category = isTissemsilt
                    ? "تيسمسيلت"
                    : (qType == "tv" ? "تقارير متلفزة" : "وطني");

                newsList.add({
                  "title": cleanTitle,
                  "summary": _cleanSummaryText(rawDesc, cleanTitle),
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
        }
      } catch (_) {}

      // إذا لم تجلب البوابة الأولى، نستخدم البوابة الثانية لقراءة XML الخام (تسمح بـ 20 خبراً لكل قناة)
      if (!fetchedFromFirst) {
        try {
          final resp = await http.get(allOriginsUrl).timeout(const Duration(seconds: 8));
          if (resp.statusCode == 200) {
            final xmlBody = utf8.decode(resp.bodyBytes, allowMalformed: true);
            final parts = xmlBody.split("<item>");
            for (int i = 1; i < parts.length && i <= 18; i++) {
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
              if (source.isEmpty) source = qType == "tv" ? "تقرير متلفز" : "الصحافة الوطنية";

              final Map timeInfo = _parseRealTime(rawDate);
              if ((timeInfo["daysOld"] as int) > maxDaysOld) continue;

              bool exists = newsList.any((n) => n['title'].toString() == rawTitle);
              if (!exists) {
                bool isTissemsilt = forceLocal ||
                    tissemsiltKeywords.any((k) => rawTitle.contains(k.toString()) || rawDesc.contains(k.toString()));
                newsList.add({
                  "title": rawTitle,
                  "summary": _cleanSummaryText(rawDesc, rawTitle),
                  "source": source,
                  "category": isTissemsilt ? "تيسمسيلت" : (qType == "tv" ? "تقارير متلفزة" : "وطني"),
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
    }

    // ترتيب صارم حسب الوقت الحقيقي (الأحدث فالأقدم) مع إعطاء أولوية لأخبار تيسمسيلت الحديثة
    newsList.sort((a, b) {
      int timeA = (a['timestamp'] ?? 0) as int;
      int timeB = (b['timestamp'] ?? 0) as int;
      return timeB.compareTo(timeA);
    });

    await _saveNewsToStorage();

    setState(() => isScanning = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('اكتمل الرصد: تم سحب $addedCount خبر وتقرير حديث بالتوقيت الحقيقي.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  // نافذة عرض ملخص الخبر والتقرير التلفزيوني داخل التطبيق دون الخروج منه
  void _showArticleSummarySheet(Map item) {
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A237E)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time, size: 15, color: Colors.deepOrange),
                    const SizedBox(width: 6),
                    Text(
                      "التوقيت الحقيقي للنشر: ${(item["time"] ?? "").toString()}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                (item["title"] ?? "").toString(),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, height: 1.4),
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
                      isTv ? "ملخص التقرير المتلفز / الفيديو:" : "الخلاصة المركزة للخبر:",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A237E)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (item["summary"] ?? item["title"] ?? "").toString(),
                      style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87),
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
                        backgroundColor: isTv ? Colors.red.shade700 : const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openNewsLink((item["url"] ?? "").toString());
                      },
                      icon: Icon(isTv ? Icons.play_circle_fill : Icons.open_in_new),
                      label: Text(isTv ? "مشاهدة الفيديو الكامل من المصدر" : "قراءة المقال الكامل من المصدر"),
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

  void _showAddFacebookModal() {
    final linkController = TextEditingController();
    final titleController = TextEditingController();
    final summaryController = TextEditingController();
    String selectedCategory = "تيسمسيلت";

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
                      const Icon(Icons.facebook, color: Color(0xFF1877F2), size: 28),
                      const SizedBox(width: 10),
                      const Text(
                        "إضافة ومشاركة خبر أو فيديو من فيسبوك",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
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
                      labelText: "رابط منشور فيسبوك أو الفيديو",
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: "عنوان الخبر البارز",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summaryController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "ملخص الخبر أو الفيديو (يظهر للمطالعين داخل التطبيق)",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField(
                    value: selectedCategory,
                    decoration: InputDecoration(
                      labelText: "تصنيف الخبر",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: const [
                      DropdownMenuItem(value: "تيسمسيلت", child: Text("أخبار تيسمسيلت (أولوية قصوى)")),
                      DropdownMenuItem(value: "وطني", child: Text("أخبار وطنية - وزارة التربية")),
                      DropdownMenuItem(value: "تقارير متلفزة", child: Text("فيديو / تقرير تلفزيوني")),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedCategory = val.toString());
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
                      label: const Text("نشر بالتوقيت الحالي", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        if (titleController.text.trim().isEmpty && linkController.text.trim().isEmpty) return;
                        String finalUrl = linkController.text.trim().isEmpty
                            ? "https://www.facebook.com"
                            : linkController.text.trim();
                        final nowInfo = _parseRealTime(DateTime.now().toIso8601String());

                        setState(() {
                          newsList.insert(0, {
                            "title": titleController.text.trim().isEmpty
                                ? "منشور تربوي مرصود عبر فيسبوك"
                                : titleController.text.trim(),
                            "summary": summaryController.text.trim().isEmpty
                                ? titleController.text.trim()
                                : summaryController.text.trim(),
                            "source": "رصد فيسبوك مباشر",
                            "category": selectedCategory,
                            "type": selectedCategory == "تقارير متلفزة" ? "tv" : "facebook",
                            "time": nowInfo["display"],
                            "timestamp": nowInfo["timestamp"],
                            "url": finalUrl,
                            "important": selectedCategory == "تيسمسيلت",
                          });
                        });
                        _saveNewsToStorage();
                        Navigator.pop(context);
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
  Widget build(BuildContext context) {
    final List filteredNews = newsList.where((item) {
      bool matchesTab = true;
      if (selectedTab == "فيسبوك") {
        matchesTab = item["type"] == "facebook";
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
            const Text("راصد التربية - ولاية تيسمسيلت", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(
              "إجمالي الأخبار المرصودة: ${newsList.length} خبر حديث",
              style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
            ),
          ],
        ),
        actions: [
          // اختيار نطاق حداثة الأخبار (آخر 24 ساعة أو 3 أيام أو 7 أيام)
          PopupMenuButton<int>(
            tooltip: "تحديد حداثة الأخبار",
            icon: const Icon(Icons.history_toggle_off, color: Colors.white),
            onSelected: (days) {
              setState(() {
                maxDaysOld = days;
                newsList.clear();
              });
              runSmartRadarBot();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 1, child: Text("أخبار آخر 24 ساعة فقط (عاجل)")),
              const PopupMenuItem(value: 3, child: Text("أخبار آخر 3 أيام")),
              const PopupMenuItem(value: 7, child: Text("أخبار هذا الأسبوع (7 أيام)")),
            ],
          ),
          IconButton(
            onPressed: isScanning ? null : runSmartRadarBot,
            tooltip: "تحديث وسحب الأخبار الجديدة الآن",
            icon: isScanning
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))
                : const Icon(Icons.radar, color: Colors.amberAccent, size: 28),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextField(
                  onChanged: (val) => setState(() => searchQuery = val),
                  decoration: InputDecoration(
                    hintText: "ابحث في العناوين والملخصات (تيسمسيلت، امتحان، بلدية...)",
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF1A237E)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
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
                  Text("جاري سحب وتلخيص أحدث الأخبار والتقارير بالتوقيت الحقيقي..."),
                ],
              ),
            )
          : ListView.builder(
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
                      color: isImportant ? Colors.amber.shade700 : Colors.transparent,
                      width: isImportant ? 1.5 : 0,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showArticleSummarySheet(item as Map),
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
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: badgeColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isImportant)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    "تيسمسيلت",
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // شريط التوقيت الحقيقي للخبر
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 13, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                (item["time"] ?? "").toString(),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (item["title"] ?? "").toString(),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.35),
                          ),
                          const SizedBox(height: 6),
                          // عرض ملخص الخبر أو الفيديو مباشرة في البطاقة
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (item["summary"] ?? item["title"] ?? "").toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800, height: 1.4),
                            ),
                          ),
                          const Divider(height: 16),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _showArticleSummarySheet(item as Map),
                                icon: Icon(type == "tv" ? Icons.ondemand_video : Icons.menu_book, size: 16),
                                label: Text(type == "tv" ? "ملخص التقرير والفيديو" : "قراءة الملخص"),
                              ),
                              TextButton.icon(
                                onPressed: () => _openNewsLink((item["url"] ?? "").toString()),
                                icon: const Icon(Icons.open_in_new, size: 15),
                                label: const Text("المصدر"),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 19),
                                onPressed: () {
                                  setState(() {
                                    newsList.remove(item);
                                  });
                                  _saveNewsToStorage();
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1877F2),
        foregroundColor: Colors.white,
        onPressed: _showAddFacebookModal,
        icon: const Icon(Icons.add_link),
        label: const Text("إضافة من فيسبوك", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}