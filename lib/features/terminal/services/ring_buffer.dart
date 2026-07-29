/// 环形缓冲区 — 固定容量，自动覆盖最旧元素
///
/// 用于终端输出的 Scrollback 历史，保证 O(1) 入队，
/// 不会无限增长。
class RingBuffer<E> {
  final int _capacity;
  final List<E?> _buffer;
  int _head = 0; // 下一个写入位置
  int _size = 0; // 当前元素数量

  RingBuffer(this._capacity)
      : assert(_capacity > 0, '容量必须大于 0'),
        _buffer = List<E?>.filled(_capacity, null);

  /// 当前元素数量
  int get size => _size;

  /// 当前元素数量（兼容 List API）
  int get length => _size;

  /// 容量
  int get capacity => _capacity;

  /// 是否为空
  bool get isEmpty => _size == 0;

  /// 是否已满
  bool get isFull => _size == _capacity;

  /// 添加元素
  void add(E element) {
    _buffer[_head] = element;
    _head = (_head + 1) % _capacity;
    if (_size < _capacity) _size++;
  }

  /// 批量添加
  void addAll(Iterable<E> elements) {
    for (final e in elements) {
      add(e);
    }
  }

  /// 获取索引处的元素（0 = 最早，size-1 = 最新）
  E operator [](int index) {
    if (index < 0 || index >= _size) {
      throw RangeError.index(index, this, 'index', null, _size);
    }
    final offset = (_head - _size + index) % _capacity;
    return _buffer[offset] as E;
  }

  /// 转换为列表（从最早到最新）
  List<E> toList() {
    final result = <E>[];
    for (int i = 0; i < _size; i++) {
      result.add(this[i]);
    }
    return result;
  }

  /// 清空
  void clear() {
    for (int i = 0; i < _capacity; i++) {
      _buffer[i] = null;
    }
    _head = 0;
    _size = 0;
  }
}
