// Tests for Data Table. Copied into your app by `ashlar add data-table` with the component: they
// check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/checkbox.dart';
import 'package:shorecat_dashboard/ui/data_table.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

Widget app2(Widget child) => AshlarApp(
  home: Center(child: SizedBox(width: 500, child: child)),
);

final invoices = [('INV001', 2500), ('INV002', 1500), ('INV003', 3500)];

Widget app3(Widget child) => AshlarApp(
  home: Center(child: SizedBox(width: 500, child: child)),
);

Widget app4(Widget child) => AshlarApp(
  home: Center(child: SizedBox(width: 500, child: child)),
);

void main() {
  group('Data Table', () {
    Widget table({ValueChanged<int>? onRowPressed}) => SizedBox(
      width: 480,
      child: DataTable(
        columns: const [
          DataColumn(Text('Invoice')),
          DataColumn(Text('Status')),
          DataColumn(Text('Amount'), numeric: true),
        ],
        rows: const [
          [Text('INV001'), Text('Paid'), Text('\$2,500')],
          [Text('INV002'), Text('Pending'), Text('\$1,500')],
        ],
        footer: const [Text('Total'), SizedBox(), Text('\$4,000')],
        caption: const Text('Recent invoices.'),
        onRowPressed: onRowPressed,
      ),
    );

    testWidgets('headings are headings; numbers sit at the end', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(table()));
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSemantics(find.text('Invoice'))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
      );
      final amount = tester.getRect(find.text('\$2,500')),
          cell = tester.getRect(find.byType(DataTable));
      expect(amount.right, closeTo(cell.right - 8, 1));
      semantics.dispose();
    });

    testWidgets('with onRowPressed, each row is a button', (tester) async {
      final semantics = tester.ensureSemantics();
      final pressed = <int>[];
      await tester.pumpWidget(app(table(onRowPressed: pressed.add)));
      await tester.tap(find.text('Pending'));
      expect(pressed, [1]);
      final row = tester.getSemantics(find.text('Pending')).getSemanticsData();
      expect(row.flagsCollection.isButton, isTrue);
      expect(row.label, contains('INV002'));
      semantics.dispose();
    });
  });

  testWidgets(
    'a sortable heading asks for the sort, and shows which way it is sorted',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var ascending = true;
      await tester.pumpWidget(
        app2(
          StatefulBuilder(
            builder: (context, set) {
              final rows = [...invoices]
                ..sort(
                  (a, b) =>
                      ascending ? a.$2.compareTo(b.$2) : b.$2.compareTo(a.$2),
                );
              return DataTable(
                columns: const [
                  DataColumn(Text('Invoice')),
                  DataColumn(Text('Amount'), numeric: true, sortable: true),
                ],
                sortColumn: 1,
                sortAscending: ascending,
                onSort: (_) => set(() => ascending = !ascending),
                rows: [
                  for (final r in rows) [Text(r.$1), Text('${r.$2}')],
                ],
              );
            },
          ),
        ),
      );
      double top(String s) => tester.getTopLeft(find.text(s)).dy;
      expect(top('1500'), lessThan(top('3500')));
      expect(
        tester.getSemantics(find.text('Amount')).getSemanticsData().label,
        contains('sorted ascending'),
      );
      await tester.tap(find.text('Amount'));
      await tester.pump();
      expect(top('3500'), lessThan(top('1500')));
      expect(
        tester.getSemantics(find.text('Amount')).getSemanticsData().label,
        contains('sorted descending'),
      );
      // From the keyboard too.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(top('1500'), lessThan(top('3500')));
      semantics.dispose();
    },
  );

  testWidgets('rows are picked one by one, or all from the heading', (
    tester,
  ) async {
    var picked = <int>{};
    await tester.pumpWidget(
      app3(
        StatefulBuilder(
          builder: (context, set) => DataTable(
            columns: const [
              DataColumn(Text('Invoice')),
              DataColumn(Text('Amount'), numeric: true),
            ],
            selected: picked,
            onSelectChanged: (s) => set(() => picked = s),
            rows: [
              for (final r in invoices) [Text(r.$1), Text('${r.$2}')],
            ],
          ),
        ),
      ),
    );
    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(4));
    await tester.tap(boxes.at(2));
    await tester.pump();
    expect(picked, {1});
    await tester.tap(boxes.first);
    await tester.pump();
    expect(picked, {0, 1, 2});
    await tester.tap(boxes.first);
    await tester.pump();
    expect(picked, isEmpty);
  });

  testWidgets(
    'with 10,000 rows the builder builds a screenful under a fixed heading',
    (tester) async {
      await tester.pumpWidget(
        app4(
          DataTable.builder(
            columns: const [
              DataColumn(Text('Order')),
              DataColumn(Text('Amount'), numeric: true),
            ],
            rowCount: 10000,
            height: 400,
            rowBuilder: (i) => [Text('Order $i'), Text('${i * 10}')],
          ),
        ),
      );
      expect(find.textContaining('Order ').evaluate().length, lessThan(20));
      await tester.drag(find.text('Order 3'), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(find.textContaining('Order ').evaluate().length, lessThan(20));
      expect(find.text('Order').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
