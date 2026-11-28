import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/csv_exporter.dart';
import 'package:simanja/models/transaction_model.dart';

// A1-07: bukti Unicode + quoting + kebijakan CSV.
// Expected ditulis sebagai literal yang diketahui; TIDAK menyalin output
// serializer sebagai expected. Parsing round-trip memakai parser CSV
// INDEPENDEN `CsvExporter.parseCsv`, bukan menyalin logika serializer.
void main() {
  const header = [
    'tanggal_iso',
    'kategori',
    'keterangan',
    'jenis',
    'nominal_rupiah',
  ];

  TransactionModel tx({
    required String id,
    required String category,
    required String description,
    required double amount,
    bool isIncome = true,
  }) => TransactionModel(
    id: id,
    category: category,
    description: description,
    amount: amount,
    isIncome: isIncome,
    date: DateTime.utc(2026, 11, 27),
  );

  // Lokasi header kolom; baris komentar metadata (#...) diabaikan.
  int headerIndex(List<List<String>> rows) => rows.indexWhere(
    (r) =>
        r.length == 5 &&
        r[0] == 'tanggal_iso' &&
        r[1] == 'kategori' &&
        r[2] == 'keterangan' &&
        r[3] == 'jenis' &&
        r[4] == 'nominal_rupiah',
  );

  List<List<String>> dataRows(List<List<String>> rows) {
    final hi = headerIndex(rows);
    expect(hi, greaterThanOrEqualTo(0), reason: 'header kolom harus ada');
    return rows.sublist(hi + 1);
  }

  group('encode -> decodeStrict -> parseCsv round-trip', () {
    final fixture = <TransactionModel>[
      tx(id: 'a', category: 'Café', description: 'kopi Café', amount: 12345),
      tx(
        id: 'b',
        category: '中文',
        description: '购物, 商品',
        amount: 67890,
        isIncome: false,
      ),
      tx(
        id: 'c',
        category: 'Emoji 😀',
        description: 'party 🎉🚀',
        amount: 9007199254740991,
      ),
      tx(
        id: 'd',
        category: 'koma, dan',
        description: 'kutip "ganda" dan koma,',
        amount: 1000,
        isIncome: false,
      ),
      tx(
        id: 'e',
        category: 'newline',
        description: 'baris1\nbaris2\r\nbaris3\rbaris4',
        amount: 2000,
      ),
      tx(
        id: 'f',
        category: '=1+1',
        description: '@SUM(1,2)',
        amount: 3000,
        isIncome: false,
      ),
    ];

    test('BOM + strict UTF-8 + header + scope + nominal exact', () {
      final bytes = CsvExporter.encode(fixture, 'Nov 2026');

      // BOM UTF-8 di awal; encoding UTF-8 (é -> C3 A9), bukan UTF-16.
      expect(
        bytes.sublist(0, 3),
        equals(CsvExporter.utf8Bom),
        reason: 'UTF-8 + BOM',
      );
      expect(CsvExporter.utf8Bom, equals([0xEF, 0xBB, 0xBF]));

      // Strict decode; Unicode tidak rusak.
      final text = CsvExporter.decodeStrict(bytes);
      expect(text.startsWith('\uFEFF'), isFalse, reason: 'BOM dilepas');
      expect(text.contains('�'), isFalse, reason: 'tidak ada U+FFFD');

      final rows = CsvExporter.parseCsv(text);
      final hi = headerIndex(rows);
      expect(hi, greaterThanOrEqualTo(0));
      expect(rows[hi], equals(header), reason: 'header kolom benar');

      final data = dataRows(rows);
      // Scope: tepat N baris data; teks tidak menyisipkan record tambahan.
      expect(data, hasLength(fixture.length));
      expect(data.every((r) => r.length == 5), isTrue);

      // Tanggal ISO + jenis.
      expect(data[0][0], equals('2026-11-27'));
      expect(data[1][3], equals('pengeluaran'));
      expect(data[0][3], equals('pemasukan'));

      // Unicode + koma + kutip dipertahankan persis.
      expect(data[0][1], equals('Café'));
      expect(data[0][2], equals('kopi Café'));
      expect(data[1][1], equals('中文'));
      expect(data[1][2], equals('购物, 商品'));
      expect(data[2][1], equals('Emoji 😀'));
      expect(data[2][2], equals('party 🎉🚀'));
      expect(data[3][1], equals('koma, dan'));
      expect(data[3][2], equals('kutip "ganda" dan koma,'));

      // Newline di dalam teks dinormalisasi jadi satu spasi; tidak ada
      // record tambahan; CRLF/CR/LF tidak bocor.
      expect(data[4][2], equals('baris1 baris2 baris3 baris4'));
      expect(text.contains('\r'), isFalse);

      // Nominal exact: string integer desimal persis, tidak ada spasi/pembulatan.
      expect(data[0][4], equals('12345'));
      expect(data[1][4], equals('67890'));
      expect(data[2][4], equals('9007199254740991'));
      expect(data[3][4], equals('1000'));
      expect(data[4][4], equals('2000'));
      expect(data[5][4], equals('3000'));
      expect(BigInt.parse(data[2][4]), equals(BigInt.from(9007199254740991)));
    });

    test('kolom koma/kutip/newline/Café/中文/emoji tidak menyisipkan record', () {
      final tricky = <TransactionModel>[
        tx(
          id: 'x',
          category: 'Café, 中文 😀',
          description: 'a,b\n"c"\r\nd\re',
          amount: 42,
        ),
      ];
      final rows = CsvExporter.parseCsv(
        CsvExporter.decodeStrict(CsvExporter.encode(tricky, 'P')),
      );
      final data = dataRows(rows);
      expect(data, hasLength(1));
      expect(data.single.length, equals(5));
      expect(data.single[1], equals('Café, 中文 😀'));
      expect(data.single[2], equals('a,b "c" d e'));
      expect(data.single[4], equals('42'));
    });
  });

  group('normalisasi newline', () {
    test(
      'separator record LF; satu trailing LF; tidak ada CR/baris kosong',
      () {
        final bytes = CsvExporter.encode([
          tx(id: 'n', category: 'k', description: 'x', amount: 5),
        ], 'P');
        final text = CsvExporter.decodeStrict(bytes);
        expect(text.contains('\r'), isFalse);
        expect(text.endsWith('\n'), isTrue);
        expect(text.endsWith('\n\n'), isFalse);
        expect(CsvExporter.recordSeparator, equals('\n'));
        // Tidak ada baris kosong di tengah.
        expect(text.contains('\n\n'), isFalse);
      },
    );

    test('newline di dalam field -> satu spasi; CRLF & CR ditangani', () {
      final rows = CsvExporter.parseCsv(
        CsvExporter.decodeStrict(
          CsvExporter.encode([
            tx(id: 'n', category: 'k', description: 'a\nb\r\nc\rd', amount: 5),
          ], 'P'),
        ),
      );
      final data = dataRows(rows);
      expect(data, hasLength(1));
      expect(data.single[2], equals('a b c d'));
    });

    test('metadata newline dinormalisasi; tidak menyisipkan record', () {
      final text = CsvExporter.decodeStrict(
        CsvExporter.encode(
          [tx(id: 'n', category: 'k', description: 'x', amount: 5)],
          'Nov\r\n2026',
          search: 'needle\r\n=1+1',
        ),
      );
      expect(text.contains('# Periode: Nov 2026'), isTrue);
      expect(text.contains('# Pencarian: needle =1+1'), isTrue);
      // tidak ada record tersembunyi dari newline di scope
      final rows = CsvExporter.parseCsv(text);
      expect(
        rows.where((r) => r.length == 1 && r[0].startsWith('#')).length,
        greaterThan(0),
      );
      expect(dataRows(rows), hasLength(1));
    });
  });

  group('guard formula (tanpa mengubah domain)', () {
    const starters = ['=', '+', '-', '@', '|', '%'];

    test('field teks berawalan formula diawali spasi; tidak dieksekusi', () {
      final tricky = <TransactionModel>[
        for (final s in starters)
          tx(
            id: 'f$s',
            category: '$s kategori',
            description: '$s payload "x",\n=1+1',
            amount: 7,
          ),
      ];
      final rows = CsvExporter.parseCsv(
        CsvExporter.decodeStrict(CsvExporter.encode(tricky, 'P')),
      );
      final data = dataRows(rows);
      expect(data, hasLength(starters.length));
      for (var i = 0; i < starters.length; i++) {
        final s = starters[i];
        // kategori: 's kategori' + leading space guard
        expect(data[i][1], equals(' $s kategori'), reason: 'kategori $s');
        // keterangan diawali guard; newline di dalam -> spasi; kutip escape
        expect(
          data[i][2].startsWith(' $s payload "x", '),
          isTrue,
          reason: 'keterangan $s -> ${data[i][2]}',
        );
        // nominal TIDAK di-guard & tetap exact
        expect(data[i][4], equals('7'));
      }
    });

    test('=1+1 di field teks menjadi " =1+1", bukan rumus', () {
      final rows = CsvExporter.parseCsv(
        CsvExporter.decodeStrict(
          CsvExporter.encode([
            tx(id: 'g', category: '=1+1', description: '=1+1', amount: 9),
          ], 'P'),
        ),
      );
      final data = dataRows(rows);
      expect(data.single[1], equals(' =1+1'));
      expect(data.single[2], equals(' =1+1'));
      expect(data.single[4], equals('9')); // nominal exact, tidak tersentuh
    });

    test('=SUM(A1:A2) berawalan karakter formula -> spasi', () {
      final rows = CsvExporter.parseCsv(
        CsvExporter.decodeStrict(
          CsvExporter.encode([
            tx(
              id: 'g',
              category: '=SUM(A1:A2)',
              description: '@cmd',
              amount: 9,
            ),
          ], 'P'),
        ),
      );
      final data = dataRows(rows);
      expect(data.single[1], equals(' =SUM(A1:A2)'));
      expect(data.single[2], equals(' @cmd'));
    });
  });

  group('strict UTF-8 decode', () {
    test('Café/中文/emoji round-trip ketat', () {
      const s = 'Café 中文 😀🎉 nominal 9007199254740991';
      final bytes = utf8.encode(s);
      expect(CsvExporter.decodeStrict(bytes), equals(s));
      // BOM di awal dilepas.
      expect(
        CsvExporter.decodeStrict([...CsvExporter.utf8Bom, ...bytes]),
        equals(s),
      );
      // é dikodekan UTF-8 (C3 A9), bukan UTF-16 0xE9.
      expect(utf8.encode('é'), equals([0xC3, 0xA9]));
    });

    test('byte malformed / sequence terpotong -> FormatException', () {
      final malformed = <List<int>>[
        [0xFF],
        [0xFE],
        [0x80], // continuation tanpa starter
        [0x41, 0x80], // A + continuation penyangkal
        [0xC0, 0x80], // overlong
        [0xC3], // starter terpotong
        [0xE4, 0xB8], // 3-byte terpotong
        [0xF0, 0x9F, 0x98], // 4-byte terpotong
        [0xF4, 0x90, 0x80, 0x80], // > U+10FFFF
        [0xED, 0xA0, 0x80], // UTF-16 surrogate
      ];
      for (final bad in malformed) {
        expect(
          () => CsvExporter.decodeStrict(bad),
          throwsA(isA<FormatException>()),
          reason: 'malformed $bad harus ditolak ketat',
        );
      }
    });

    test('decodeStrict menerima output encode + BOM persis', () {
      final bytes = CsvExporter.encode([
        tx(id: 'u', category: 'Café 中文', description: '😀', amount: 9),
      ], 'Nov 2026');
      final text = CsvExporter.decodeStrict(bytes);
      final rows = CsvExporter.parseCsv(text);
      expect(dataRows(rows).single[1], equals('Café 中文'));
      expect(dataRows(rows).single[2], equals('😀'));
    });
  });

  group(
    'parser CSV independen (input hand-crafted, bukan output serializer)',
    () {
      test('koma/kutip/newline di dalam kutipan; CRLF/CR/LF; kolom kosong', () {
        // CSV dibuat manual, TIDAK dari serializer.
        const crafted =
            'a,b,c\r\n'
            '"1,1","say ""hi""","x\ny"\r\n'
            '"p\r\nq","m\rn","",tail\n';
        final rows = CsvExporter.parseCsv(crafted);
        expect(
          rows,
          equals(<List<String>>[
            ['a', 'b', 'c'],
            ['1,1', 'say "hi"', 'x\ny'],
            ['p\nq', 'm\nn', '', 'tail'],
          ]),
        );
      });

      test('kutipan kosong, kolom kosong, trailing comma, separator akhir', () {
        expect(
          CsvExporter.parseCsv('""'),
          equals([
            [''],
          ]),
        );
        expect(
          CsvExporter.parseCsv('a,b,'),
          equals([
            ['a', 'b', ''],
          ]),
        );
        expect(
          CsvExporter.parseCsv(','),
          equals([
            ['', ''],
          ]),
        );
        expect(
          CsvExporter.parseCsv('a,,b'),
          equals([
            ['a', '', 'b'],
          ]),
        );
        expect(
          CsvExporter.parseCsv('a,b\n'),
          equals([
            ['a', 'b'],
          ]),
        );
        expect(
          CsvExporter.parseCsv('a,b\r\n'),
          equals([
            ['a', 'b'],
          ]),
        );
        expect(
          CsvExporter.parseCsv('a,b\r'),
          equals([
            ['a', 'b'],
          ]),
        );
        expect(CsvExporter.parseCsv(''), equals(<List<String>>[]));
      });

      test('Unicode di dalam field kutipan tidak rusak', () {
        const crafted = '"Café","中文","😀"\n';
        expect(
          CsvExporter.parseCsv(crafted),
          equals([
            ['Café', '中文', '😀'],
          ]),
        );
      });

      test('kutipan tidak ditutup -> FormatException', () {
        expect(
          () => CsvExporter.parseCsv('"a,b\nc'),
          throwsA(isA<FormatException>()),
        );
      });

      test(
        'karakter tak terduga setelah kutipan penutup -> FormatException',
        () {
          expect(
            () => CsvExporter.parseCsv('"a"x,b'),
            throwsA(isA<FormatException>()),
          );
        },
      );

      test('newline di dalam field kutipan dinormalisasi ke LF', () {
        const crafted = '"a\r\nb","c\rd","e\nf"\n';
        expect(
          CsvExporter.parseCsv(crafted),
          equals([
            ['a\nb', 'c\nd', 'e\nf'],
          ]),
        );
      });
    },
  );

  group('scope + nominal', () {
    test('search scope tidak mengubah baris; Jumlah baris exact', () {
      final fixture = <TransactionModel>[
        tx(id: '1', category: 'Café', description: 'x', amount: 100),
        tx(id: '2', category: '中文', description: 'y', amount: 200),
      ];
      final plain = dataRows(
        CsvExporter.parseCsv(
          CsvExporter.decodeStrict(CsvExporter.encode(fixture, 'P')),
        ),
      );
      final scoped = dataRows(
        CsvExporter.parseCsv(
          CsvExporter.decodeStrict(
            CsvExporter.encode(fixture, 'P', search: 'Café'),
          ),
        ),
      );
      // Scope pencarian hanya metadata; baris tetap sama persis.
      expect(scoped, equals(plain));
      expect(scoped, hasLength(2));

      final text = CsvExporter.decodeStrict(CsvExporter.encode(fixture, 'P'));
      expect(text.contains('# Jumlah baris: 2'), isTrue);
      // nominal total tidak diubah oleh scope
      expect(scoped.map((r) => r[4]).toList(), equals(['100', '200']));
    });
  });
}
