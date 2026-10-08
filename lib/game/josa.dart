/// 한국어 조사 자동 선택: 받침 유무에 따라 을/를, 이/가, 으로/로 등을 고른다.
library;

const _digitBatchim = {
  '0': 'ㅇ',
  '1': 'ㄹ',
  '3': 'ㅁ',
  '6': 'ㄱ',
  '7': 'ㄹ',
  '8': 'ㄹ',
};

/// 마지막 글자의 받침. 없으면 null, 'ㄹ' 받침이면 'ㄹ'
String? _batchim(String word) {
  if (word.isEmpty) return null;
  final last = word[word.length - 1];
  if (_digitBatchim.containsKey(last)) return _digitBatchim[last];
  final code = last.codeUnitAt(0);
  if (code < 0xAC00 || code > 0xD7A3) return null;
  final jong = (code - 0xAC00) % 28;
  if (jong == 0) return null;
  return jong == 8 ? 'ㄹ' : 'O';
}

/// 예: josa('테라노바', '을', '를') → '테라노바를'
String josa(String word, String withBatchim, String without) =>
    word + (_batchim(word) != null ? withBatchim : without);

String eul(String w) => josa(w, '을', '를');
String iGa(String w) => josa(w, '이', '가');

/// 으로/로: ㄹ 받침은 '로'
String euro(String w) {
  final b = _batchim(w);
  return w + (b == null || b == 'ㄹ' ? '로' : '으로');
}
