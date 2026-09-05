import 'package:flutter/material.dart';

import '../../../ai_chat/presentation/screens/ai_chat_tab.dart';
import 'search_tab.dart';

/// "Tab: Search | Ask AI" (requirements doc, section 23) — one screen,
/// two ways to find something in the archive: type a query, or ask a
/// question and get a sourced answer.
class SearchHubScreen extends StatefulWidget {
  const SearchHubScreen({super.key});

  @override
  State<SearchHubScreen> createState() => _SearchHubScreenState();
}

class _SearchHubScreenState extends State<SearchHubScreen>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LifeSearch'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Search'),
            Tab(text: 'Ask AI'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [SearchTab(), AiChatTab()],
      ),
    );
  }
}
