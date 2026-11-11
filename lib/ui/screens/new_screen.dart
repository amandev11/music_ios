import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../theme/theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'home.dart';

/// "New": the same catalogue shelves as a browsable grid (charts, new releases, playlists, artists).
class NewScreen extends StatelessWidget {
  const NewScreen({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<List<HomeSection>>(
        future: AppController.I.catalog.home(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CupertinoActivityIndicator());
          }
          final sections = [for (final s in snap.data ?? const <HomeSection>[]) if (s.style != SectionStyle.songs && s.style != SectionStyle.wide) s];
          if (sections.isEmpty) {
            return const EmptyState(icon: Icons.cloud_off_rounded, title: 'Nothing New Yet', message: 'Connect to the internet to browse new music.');
          }
          return ListView(padding: const EdgeInsets.only(bottom: kListBottomPad), children: [
            const LargeTitle('New'),
            for (final s in sections) ...[
              SectionHeader(s.title),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(builder: (context, c) {
                  final cols = (c.maxWidth / 170).floor().clamp(2, 8);
                  final w = (c.maxWidth - (cols - 1) * 14) / cols;
                  return Wrap(spacing: 14, runSpacing: 18, children: [
                    for (final i in s.items) ItemCard(item: i, width: w),
                  ]);
                }),
              ),
            ],
          ]);
        },
      );
}
