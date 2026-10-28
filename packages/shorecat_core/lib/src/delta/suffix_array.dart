import 'dart:typed_data';

/// Larsson-Sadakane suffix sorting (qsufsort), as used by bsdiff.
///
/// Returns `I` of length `data.length + 1`, where `I[0]` is the empty suffix.
/// The recursive `split` from the reference implementation runs on an explicit
/// stack here because repetitive inputs (zero-filled sections of a shared
/// object) can recurse deeper than the Dart stack allows.
Int32List suffixSort(Uint8List data) {
  final size = data.length;
  final buckets = Int32List(256);
  final index = Int32List(size + 1);
  final rank = Int32List(size + 1);

  for (var i = 0; i < size; i++) {
    buckets[data[i]]++;
  }
  for (var i = 1; i < 256; i++) {
    buckets[i] += buckets[i - 1];
  }
  for (var i = 255; i > 0; i--) {
    buckets[i] = buckets[i - 1];
  }
  buckets[0] = 0;

  for (var i = 0; i < size; i++) {
    index[++buckets[data[i]]] = i;
  }
  index[0] = size;
  for (var i = 0; i < size; i++) {
    rank[i] = buckets[data[i]];
  }
  rank[size] = 0;
  for (var i = 1; i < 256; i++) {
    if (buckets[i] == buckets[i - 1] + 1) index[buckets[i]] = -1;
  }
  index[0] = -1;

  final sorter = _Splitter(index, rank);
  for (var h = 1; index[0] != -(size + 1); h += h) {
    var len = 0;
    var i = 0;
    while (i < size + 1) {
      if (index[i] < 0) {
        len -= index[i];
        i -= index[i];
      } else {
        if (len != 0) index[i - len] = -len;
        len = rank[index[i]] + 1 - i;
        sorter.split(i, len, h);
        i += len;
        len = 0;
      }
    }
    if (len != 0) index[i - len] = -len;
  }

  for (var i = 0; i < size + 1; i++) {
    index[rank[i]] = i;
  }
  return index;
}

class _Splitter {
  final Int32List index;
  final Int32List rank;
  final List<int> _tasks = [];

  _Splitter(this.index, this.rank);

  static const _splitTask = 0;
  static const _assignTask = 1;

  void split(int start, int len, int h) {
    _tasks
      ..clear()
      ..addAll([_splitTask, start, len]);
    while (_tasks.isNotEmpty) {
      final c = _tasks.removeLast();
      final b = _tasks.removeLast();
      final kind = _tasks.removeLast();
      if (kind == _assignTask) {
        _assign(b, c);
      } else {
        _split(b, c, h);
      }
    }
  }

  void _assign(int jj, int kk) {
    for (var i = 0; i < kk - jj; i++) {
      rank[index[jj + i]] = kk - 1;
    }
    if (jj == kk - 1) index[jj] = -1;
  }

  void _split(int start, int len, int h) {
    if (len < 16) {
      _insertionSplit(start, len, h);
      return;
    }

    final x = rank[index[start + len ~/ 2] + h];
    var jj = 0;
    var kk = 0;
    for (var i = start; i < start + len; i++) {
      final v = rank[index[i] + h];
      if (v < x) jj++;
      if (v == x) kk++;
    }
    jj += start;
    kk += jj;

    var i = start;
    var j = 0;
    var k = 0;
    while (i < jj) {
      final v = rank[index[i] + h];
      if (v < x) {
        i++;
      } else if (v == x) {
        _swap(i, jj + j);
        j++;
      } else {
        _swap(i, kk + k);
        k++;
      }
    }
    while (jj + j < kk) {
      if (rank[index[jj + j] + h] == x) {
        j++;
      } else {
        _swap(jj + j, kk + k);
        k++;
      }
    }

    // Reverse order of the reference recursion: left, assign, right.
    if (start + len > kk) _tasks.addAll([_splitTask, kk, start + len - kk]);
    _tasks.addAll([_assignTask, jj, kk]);
    if (jj > start) _tasks.addAll([_splitTask, start, jj - start]);
  }

  void _insertionSplit(int start, int len, int h) {
    var j = 1;
    for (var k = start; k < start + len; k += j) {
      j = 1;
      var x = rank[index[k] + h];
      for (var i = 1; k + i < start + len; i++) {
        final v = rank[index[k + i] + h];
        if (v < x) {
          x = v;
          j = 0;
        }
        if (v == x) {
          _swap(k + j, k + i);
          j++;
        }
      }
      for (var i = 0; i < j; i++) {
        rank[index[k + i]] = k + j - 1;
      }
      if (j == 1) index[k] = -1;
    }
  }

  void _swap(int a, int b) {
    final tmp = index[a];
    index[a] = index[b];
    index[b] = tmp;
  }
}
