import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const TikTokExplorerApp());
}

class TikTokExplorerApp extends StatelessWidget {
  const TikTokExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TikTok Saved Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFE2C55),
          secondary: Color(0xFF25F4EE),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class VideoItem {
  final String id;
  final String date;
  final int timestamp;
  final String link;
  final String content;
  String? coverUrl;
  String? author;
  String? title;

  VideoItem({
    required this.id,
    required this.date,
    required this.timestamp,
    required this.link,
    required this.content,
    this.coverUrl,
    this.author,
    this.title,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, List<VideoItem>> allCategories = {};
  String selectedCategory = "Favorite Videos";
  List<VideoItem> activeList = [];
  List<VideoItem> filteredList = [];

  bool isLoading = false;
  String statusMessage = "Pilih file user_data.json TikTok";
  String searchQuery = "";
  String sortOrder = "newest"; // "newest" atau "oldest"
  String selectedYear = "Semua";

  final TextEditingController searchController = TextEditingController();

  Future<void> pickJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      isLoading = true;
      statusMessage = "Membaca file JSON (10.8 MB)...";
    });

    try {
      final bytes = result.files.first.bytes;
      if (bytes == null) throw Exception("Gagal membaca file");

      final rawString = utf8.decode(bytes);
      final dynamic root = jsonDecode(rawString);

      setState(() => statusMessage = "Mengindeks kategori & video...");

      final Map<String, List<VideoItem>> parsed = {};
      final block = _findLikesFavorites(root);

      if (block != null) {
        block.forEach((k, v) {
          List items = [];
          if (v is List) {
            items = v;
          } else if (v is Map) {
            for (var val in v.values) {
              if (val is List) { items = val; break; }
            }
          }

          parsed[k.toString()] = items.map((item) {
            final rawDate = (item['Date'] ?? item['date'] ?? item['DateAdd'] ?? '').toString();
            final link = (item['Link'] ?? item['link'] ?? item['VideoLink'] ?? '').toString();
            final content = (item['FavoriteComment'] ?? item['FavoriteCollection'] ?? item['Comment'] ?? '').toString();

            String id = "";
            final match = RegExp(r'(?:video/|/share/video/)(\d{15,22})').firstMatch(link);
            if (match != null) id = match.group(1)!;

            int ts = 0;
            String displayDate = rawDate.split(' ').first;
            try {
              ts = DateTime.parse(rawDate.replaceAll(' ', 'T')).millisecondsSinceEpoch;
            } catch (_) {}

            return VideoItem(
              id: id,
              date: displayDate.isEmpty ? 'No Date' : displayDate,
              timestamp: ts,
              link: link,
              content: content,
            );
          }).toList();
        });
      }

      setState(() {
        allCategories = parsed;
        if (allCategories.containsKey("Favorite Videos")) {
          selectedCategory = "Favorite Videos";
        } else if (allCategories.isNotEmpty) {
          selectedCategory = allCategories.keys.first;
        }
        activeList = allCategories[selectedCategory] ?? [];
        isLoading = false;
        _applyFilter();
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        statusMessage = "Error: $e";
      });
    }
  }

  dynamic _findLikesFavorites(dynamic root) {
    if (root is! Map) return null;
    for (var k in root.keys) {
      final str = k.toString().toLowerCase();
      if (str.contains('likes and favorites') || str == 'favorite videos' || str == 'like list') {
        return root[k] is Map ? root[k] : root;
      }
    }
    for (var v in root.values) {
      if (v is Map) {
        final res = _findLikesFavorites(v);
        if (res != null) return res;
      }
    }
    return null;
  }

  void _applyFilter() {
    List<VideoItem> temp = List.from(activeList);

    // Filter Pencarian
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      temp = temp.where((item) {
        return item.id.contains(q) ||
               item.date.toLowerCase().contains(q) ||
               item.content.toLowerCase().contains(q) ||
               (item.title != null && item.title!.toLowerCase().contains(q)) ||
               (item.author != null && item.author!.toLowerCase().contains(q));
      }).toList();
    }

    // Filter Tahun
    if (selectedYear != "Semua") {
      temp = temp.where((item) => item.date.startsWith(selectedYear) || item.date.endsWith(selectedYear)).toList();
    }

    // Sortir Tanggal
    if (sortOrder == "newest") {
      temp.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } else {
      temp.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    setState(() {
      filteredList = temp;
    });
  }

  void openPlayerModal(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoDetailModal(
        items: filteredList,
        initialIndex: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              color: Colors.black.withOpacity(0.45),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFFE2C55), Color(0xFF25F4EE)]),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.play_arrow, size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'TikTok Explorer',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFE2C55),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: pickJsonFile,
                      icon: const Icon(Icons.folder_open, size: 16, color: Colors.white),
                      label: const Text('Buka JSON', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: allCategories.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isLoading)
                      const CircularProgressIndicator(color: Color(0xFFFE2C55))
                    else
                      const Icon(Icons.video_library_outlined, size: 64, color: Colors.white24),
                    const SizedBox(height: 16),
                    Text(statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                const SizedBox(height: 85),
                
                // 1. HORIZONTAL TABS KATEGORI
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: allCategories.keys.map((cat) {
                      final isSelected = cat == selectedCategory;
                      final count = allCategories[cat]?.length ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('$cat (${count > 999 ? "${(count/1000).toStringAsFixed(1)}k" : count})'),
                          selected: isSelected,
                          selectedColor: Colors.white,
                          backgroundColor: const Color(0xFF181A24),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                selectedCategory = cat;
                                activeList = allCategories[cat] ?? [];
                                _applyFilter();
                              });
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                
                // 2. SEARCH & CONTROLS TOOLBAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF161822),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: TextField(
                            controller: searchController,
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Cari ID, judul, tanggal...',
                              hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                              prefixIcon: Icon(Icons.search, size: 16, color: Colors.white38),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            onChanged: (val) {
                              searchQuery = val;
                              _applyFilter();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Dropdown Urutan
                      Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161822),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: sortOrder,
                            dropdownColor: const Color(0xFF1C1F2D),
                            style: const TextStyle(fontSize: 11, color: Colors.white),
                            items: const [
                              DropdownMenuItem(value: "newest", child: Text("Terbaru")),
                              DropdownMenuItem(value: "oldest", child: Text("Terlama")),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                sortOrder = val;
                                _applyFilter();
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Dropdown Loncat Tahun
                      Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161822),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedYear,
                            dropdownColor: const Color(0xFF1C1F2D),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF25F4EE)),
                            items: ["Semua", "2026", "2025", "2024", "2023", "2022", "2021", "2020"]
                                .map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                selectedYear = val;
                                _applyFilter();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Info Jumlah Hasil
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Menampilkan ${filteredList.length} video',
                      style: const TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                  ),
                ),

                // 3. GRID FEED VIDEO TIKTOK (9:14)
                Expanded(
                  child: filteredList.isEmpty
                      ? const Center(child: Text("Tidak ada video yang cocok", style: TextStyle(color: Colors.white38, fontSize: 12)))
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 9 / 14,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final item = filteredList[index];
                            return VideoCard(
                              item: item,
                              onTap: () => openPlayerModal(index),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class VideoCard extends StatefulWidget {
  final VideoItem item;
  final VoidCallback onTap;

  const VideoCard({super.key, required this.item, required this.onTap});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  @override
  void initState() {
    super.initState();
    if (widget.item.coverUrl == null && widget.item.id.isNotEmpty) {
      _fetchCover();
    }
  }

  Future<void> _fetchCover() async {
    try {
      final res = await http.get(Uri.parse('https://www.tikwm.com/api/?url=${widget.item.id}')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        if (data != null && mounted) {
          setState(() {
            widget.item.coverUrl = data['cover'] ?? data['origin_cover'];
            widget.item.author = data['author']?['nickname'];
            widget.item.title = data['title'];
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: const Color(0xFF141722),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.item.coverUrl != null)
                CachedNetworkImage(
                  imageUrl: widget.item.coverUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: const Color(0xFF181B28)),
                  errorWidget: (_, __, ___) => _fallbackCover(),
                )
              else
                _fallbackCover(),
              
              // Gradient Overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
              ),

              // Header Kartu
              Positioned(
                top: 8, left: 8, right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.item.author != null ? '@${widget.item.author}' : 'TikTok',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF25F        child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title ?? widget.item.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(widget.item.date, style: const TextStyle(fontSize: 9, color: Colors.white54)),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class VideoPlayerModal extends StatefulWidget {
  final List<VideoItem> items;
  final int initialIndex;

  const VideoPlayerModal({super.key, required this.items, required this.initialIndex});

  @override
  State<VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<VideoPlayerModal> {
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
  }

  void openInApp() async {
    final item = widget.items[currentIndex];
    final uri = Uri.parse('snssdk1180://aweme/detail/${item.id}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(Uri.parse('https://www.tiktok.com/@/video/${item.id}'), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[currentIndex];

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ID: ${item.id}', style: const TextStyle(color: Color(0xFF25F4EE), fontFamily: 'monospace')),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.coverUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(imageUrl: item.coverUrl!, height: 350, fit: BoxFit.cover),
                      ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFE2C55),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: openInApp,
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: const Text('Putar Video di Aplikasi TikTok', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: currentIndex > 0 ? () => setState(() => currentIndex--) : null,
                  child: const Text('⏮ Sebelumnya'),
                ),
                Text('${currentIndex + 1} / ${widget.items.length}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ElevatedButton(
                  onPressed: currentIndex < widget.items.length - 1 ? () => setState(() => currentIndex++) : null,
                  child: const Text('Berikutnya ⏭'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
