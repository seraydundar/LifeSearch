import 'package:flutter/material.dart';

import '../../../ai_chat/presentation/screens/ai_chat_tab.dart';
import 'search_tab.dart';

class SearchHubScreen extends StatefulWidget {
  const SearchHubScreen({super.key, this.initialQuery});

  final String? initialQuery;

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
        children: [SearchTab(initialQuery: widget.initialQuery), const AiChatTab()],
      ),
    );
  }
}
