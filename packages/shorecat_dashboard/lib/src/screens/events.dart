import 'package:flutter/widgets.dart';

import '../../ui/card.dart';
import '../../ui/data_table.dart';
import '../../ui/theme.dart';
import '../../ui/toggle_group.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/common.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  Set<EventKind> kinds = {};

  static final _filters = [
    for (final kind in EventKind.values)
      if (kind != EventKind.check) kind,
  ];

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final events = SessionScope.of(context).events;
    final shown = [
      for (final e in events)
        if (kinds.isEmpty || kinds.contains(e.kind)) e,
    ]..sort((a, b) => b.at.compareTo(a.at));
    return PageBody(
      children: [
        Card(
          children: [
            CardHeader(
              title: const Text('Recent device events'),
              description: Text(
                'The last ${events.length} reports, by when they happened',
              ),
            ),
            CardContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ToggleGroup<EventKind>(
                    multiple: true,
                    spacing: 6,
                    values: kinds,
                    semanticLabel: 'Filter by event',
                    onChanged: (v) => setState(() => kinds = v),
                    items: [
                      for (final k in _filters)
                        ToggleGroupItem(k, Text(k.label)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (shown.isEmpty)
                    const NothingYet(
                      title: 'All quiet on the windowsill',
                      description:
                          'Events show up here as devices report them.',
                    )
                  else
                    LayoutBuilder(
                      builder: (context, box) {
                        final isWide = box.maxWidth >= 720;
                        return DataTable(
                          columns: [
                            const DataColumn(Text('When')),
                            const DataColumn(Text('Event'), flex: 2),
                            const DataColumn(Text('Release')),
                            const DataColumn(Text('Patch')),
                            if (isWide) const DataColumn(Text('Arch')),
                            if (isWide)
                              const DataColumn(Text('Device'), flex: 2),
                            if (isWide)
                              const DataColumn(Text('Detail'), flex: 3),
                          ],
                          rows: [
                            for (final e in shown.take(200))
                              [
                                Text(
                                  ago(e.at),
                                  style: t.text.sm.copyWith(
                                    color: c.mutedForeground,
                                  ),
                                ),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: EventBadge(kind: e.kind),
                                ),
                                Text(e.releaseVersion),
                                Text('#${e.patchNumber}'),
                                if (isWide) Text(e.arch),
                                if (isWide)
                                  Text(
                                    e.clientId.length > 12
                                        ? '${e.clientId.substring(0, 12)}...'
                                        : e.clientId,
                                    style: t.text.xs.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                if (isWide)
                                  Text(
                                    e.message ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: t.text.sm.copyWith(
                                      color: c.mutedForeground,
                                    ),
                                  ),
                              ],
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
