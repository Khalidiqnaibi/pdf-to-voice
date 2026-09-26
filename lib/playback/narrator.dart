import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../services/narration_script.dart';
import '../services/tts_service.dart';

enum NarratorPhase {
  /// No script attached yet.
  idle,

  /// Waiting on Kokoro to render the sentence the user is about to hear.
  rendering,

  playing,
  paused,
  finished,
  error,
}

/// Drives narration over a [NarrationScript].
///
/// Sentences are rendered one clip at a time and played back-to-back, with the
/// next few sentences rendered speculatively so playback rarely stalls. Speed is
/// applied at the player (mpv keeps the pitch), which means a speed change takes
/// effect instantly and never invalidates the cache.
class Narrator extends ChangeNotifier {
  Narrator(this._tts) {
    _player = Player();
    _subs.add(_player.stream.position.listen(_onPosition));
    _subs.add(_player.stream.completed.listen(_onCompleted));
    _subs.add(_player.stream.error.listen((e) => _setError('Audio playback failed: $e')));
  }

  /// How many sentences ahead of the cursor to render speculatively.
  static const _prefetchAhead = 3;
  static const skipStep = Duration(seconds: 10);

  final TtsService _tts;
  late final Player _player;
  final _subs = <StreamSubscription<dynamic>>[];

  NarrationScript _script = NarrationScript.empty;
  NarratorPhase _phase = NarratorPhase.idle;
  String? _error;
  int _index = 0;
  String _voiceId = '';
  double _speed = 1.0;

  /// Whether the user wants audio running; [_phase] may briefly be `rendering`
  /// while this is true.
  bool _intendsToPlay = false;

  /// Guards against a slow render landing after the user has moved on.
  int _loadToken = 0;
  Duration _clipDuration = Duration.zero;
  Timer? _sleepTimer;
  DateTime? _sleepAt;

  /// Position within the current clip. Kept out of [notifyListeners] so the
  /// ticking progress rail does not rebuild the whole reader.
  final position = ValueNotifier<Duration>(Duration.zero);

  /// Fires whenever the spoken sentence changes, so the viewer can scroll.
  final cursor = ValueNotifier<int>(0);

  NarrationScript get script => _script;
  NarratorPhase get phase => _phase;
  String? get error => _error;
  int get index => _index;
  double get speed => _speed;
  String get voiceId => _voiceId;
  Duration get clipDuration => _clipDuration;
  DateTime? get sleepAt => _sleepAt;

  bool get hasScript => _script.isNotEmpty;
  bool get isPlaying => _phase == NarratorPhase.playing;
  bool get isRendering => _phase == NarratorPhase.rendering;
  bool get isActive => _intendsToPlay;

  Sentence? get current =>
      hasScript && _index >= 0 && _index < _script.length ? _script[_index] : null;

  Sentence? get upcoming =>
      hasScript && _index + 1 < _script.length ? _script[_index + 1] : null;

  /// 0..1 through the whole document, blending the sentence cursor with the
  /// position inside the current clip so the rail moves smoothly.
  double get documentProgress {
    if (!hasScript) return 0;
    final within = _clipDuration.inMilliseconds == 0
        ? 0.0
        : (position.value.inMilliseconds / _clipDuration.inMilliseconds).clamp(0.0, 1.0);
    return ((_index + within) / _script.length).clamp(0.0, 1.0);
  }

  /// Rough time left in the document at the current speed.
  Duration get remaining {
    if (!hasScript) return Duration.zero;
    var ms = (_clipDuration - position.value).inMilliseconds;
    for (var i = _index + 1; i < _script.length; i++) {
      final sentence = _script[i];
      ms += (_tts.knownDuration(sentence.text, _voiceId) ?? sentence.estimatedDuration)
          .inMilliseconds;
    }
    return Duration(milliseconds: (ms / _speed).round().clamp(0, 1 << 40));
  }

  // ------------------------------------------------------------------- attach

  Future<void> attach(
    NarrationScript script, {
    required String voiceId,
    required double speed,
    int startIndex = 0,
  }) async {
    _loadToken++;
    _script = script;
    _voiceId = voiceId;
    _speed = speed;
    _index = script.isEmpty ? 0 : startIndex.clamp(0, script.length - 1);
    _intendsToPlay = false;
    _clipDuration = Duration.zero;
    _error = null;
    position.value = Duration.zero;
    cursor.value = _index;
    _phase = script.isEmpty ? NarratorPhase.idle : NarratorPhase.paused;

    await _player.stop();
    notifyListeners();
    _schedulePrefetch();
  }

  // ---------------------------------------------------------------- transport

  Future<void> toggle() => _intendsToPlay ? pause() : play();

  Future<void> play() async {
    if (!hasScript) return;
    if (_phase == NarratorPhase.finished) {
      await jumpTo(0, autoplay: true);
      return;
    }

    _intendsToPlay = true;
    _error = null;

    // Resuming mid-clip: the media is still open, just un-pause it.
    if (_clipDuration > Duration.zero && position.value < _clipDuration) {
      _phase = NarratorPhase.playing;
      notifyListeners();
      await _player.play();
      _schedulePrefetch();
      return;
    }

    await _loadAndPlay(_index, from: Duration.zero);
  }

  Future<void> pause() async {
    _intendsToPlay = false;
    if (_phase == NarratorPhase.playing || _phase == NarratorPhase.rendering) {
      _phase = NarratorPhase.paused;
    }
    notifyListeners();
    await _player.pause();
  }

  /// Media-player convention: tapping back restarts the sentence unless you are
  /// still near its start, in which case it steps to the previous one.
  Future<void> previous() async {
    if (position.value > const Duration(milliseconds: 2500) || _index == 0) {
      await jumpTo(_index, autoplay: _intendsToPlay);
    } else {
      await jumpTo(_index - 1, autoplay: _intendsToPlay);
    }
  }

  Future<void> next() async {
    if (_index + 1 >= _script.length) {
      await _finish();
      return;
    }
    await jumpTo(_index + 1, autoplay: _intendsToPlay);
  }

  Future<void> jumpTo(int index, {bool autoplay = true, Duration offset = Duration.zero}) async {
    if (!hasScript) return;
    final target = index.clamp(0, _script.length - 1);
    _intendsToPlay = autoplay;
    _index = target;
    cursor.value = target;
    position.value = offset;
    _clipDuration = Duration.zero;
    _error = null;

    if (!autoplay) {
      _loadToken++;
      _phase = NarratorPhase.paused;
      await _player.stop();
      notifyListeners();
      _schedulePrefetch();
      return;
    }

    await _loadAndPlay(target, from: offset);
  }

  /// Scrub by [delta], walking across sentence boundaries using the durations of
  /// clips that have already been rendered.
  Future<void> nudge(Duration delta) async {
    if (!hasScript) return;

    var target = position.value + delta;

    if (delta.isNegative) {
      var index = _index;
      while (target.isNegative && index > 0) {
        index--;
        final previousLength = _durationOf(index);
        if (previousLength == Duration.zero) {
          target = Duration.zero; // not rendered yet: land on its first word
          break;
        }
        target += previousLength;
      }
      if (target.isNegative) target = Duration.zero;
      if (index != _index) {
        await jumpTo(index, autoplay: _intendsToPlay, offset: target);
        return;
      }
      await _seekWithin(target);
      return;
    }

    var index = _index;
    var span = _clipDuration;
    while (span > Duration.zero && target >= span && index + 1 < _script.length) {
      target -= span;
      index++;
      span = _durationOf(index);
      if (span == Duration.zero) {
        target = Duration.zero;
        break;
      }
    }

    if (index != _index) {
      await jumpTo(index, autoplay: _intendsToPlay, offset: target);
      return;
    }
    if (_clipDuration > Duration.zero && target >= _clipDuration) {
      await next();
      return;
    }
    await _seekWithin(target);
  }

  /// Seek within the current sentence, as a fraction of its length.
  Future<void> seekFraction(double fraction) async {
    if (_clipDuration == Duration.zero) return;
    await _seekWithin(_clipDuration * fraction.clamp(0.0, 1.0));
  }

  Future<void> _seekWithin(Duration target) async {
    final clamped = target < Duration.zero ? Duration.zero : target;
    position.value = clamped;
    try {
      await _player.seek(clamped);
    } catch (_) {
      // Seeking before the media is open is harmless; the next load honours it.
    }
  }

  Duration _durationOf(int index) =>
      _tts.knownDuration(_script[index].text, _voiceId) ?? Duration.zero;

  // ------------------------------------------------------------------ settings

  Future<void> setSpeed(double value) async {
    _speed = value.clamp(0.5, 3.0);
    notifyListeners();
    try {
      await _player.setRate(_speed);
    } catch (_) {}
  }

  /// Switching voice invalidates the rendered audio, so the current sentence is
  /// re-rendered from its start and playback continues if it was running.
  Future<void> setVoice(String voiceId) async {
    if (voiceId == _voiceId) return;
    _voiceId = voiceId;
    _tts.cancelPending();
    final wasPlaying = _intendsToPlay;
    _clipDuration = Duration.zero;
    position.value = Duration.zero;
    notifyListeners();

    if (wasPlaying) {
      await _loadAndPlay(_index, from: Duration.zero);
    } else {
      _loadToken++;
      await _player.stop();
      _schedulePrefetch();
    }
  }

  void setSleepTimer(Duration? after) {
    _sleepTimer?.cancel();
    if (after == null) {
      _sleepTimer = null;
      _sleepAt = null;
    } else {
      _sleepAt = DateTime.now().add(after);
      _sleepTimer = Timer(after, () {
        _sleepAt = null;
        _sleepTimer = null;
        pause();
      });
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------- engine

  Future<void> _loadAndPlay(int index, {required Duration from}) async {
    final token = ++_loadToken;
    final sentence = _script[index];

    _phase = NarratorPhase.rendering;
    notifyListeners();
    _schedulePrefetch();

    Clip clip;
    try {
      clip = await _tts.clip(sentence.text, _voiceId, priority: 0);
    } on Object catch (e) {
      if (token != _loadToken) return;
      _setError(e.toString());
      return;
    }
    if (token != _loadToken || !_intendsToPlay) return;

    _clipDuration = clip.duration;

    try {
      await _player.open(Media(clip.file.path), play: false);
      if (token != _loadToken) return;
      await _player.setRate(_speed);
      if (from > Duration.zero) await _player.seek(from);
      if (token != _loadToken || !_intendsToPlay) return;
      await _player.play();
    } on Object catch (e) {
      if (token != _loadToken) return;
      _setError('Could not play the rendered audio: $e');
      return;
    }

    if (token != _loadToken) return;
    position.value = from;
    _phase = NarratorPhase.playing;
    _error = null;
    notifyListeners();
    _schedulePrefetch();
  }

  void _onPosition(Duration value) {
    if (_phase == NarratorPhase.playing) position.value = value;
  }

  void _onCompleted(bool completed) {
    if (!completed || !_intendsToPlay || _phase != NarratorPhase.playing) return;
    assert(() {
      final at = position.value.inMilliseconds;
      final clip = _clipDuration.inMilliseconds;
      debugPrint(
        '[narrator] eof at ${at}ms of ${clip}ms '
        '(short by ${clip - at}ms), player says '
        '${_player.state.duration.inMilliseconds}ms',
      );
      return true;
    }());
    if (_index + 1 >= _script.length) {
      _finish();
      return;
    }
    _index++;
    cursor.value = _index;
    position.value = Duration.zero;
    _clipDuration = Duration.zero;
    _loadAndPlay(_index, from: Duration.zero);
  }

  Future<void> _finish() async {
    _intendsToPlay = false;
    _phase = NarratorPhase.finished;
    position.value = _clipDuration;
    notifyListeners();
    await _player.pause();
  }

  void _setError(String message) {
    _error = message;
    _intendsToPlay = false;
    _phase = NarratorPhase.error;
    notifyListeners();
  }

  /// Keeps a short runway of rendered sentences ahead of the cursor.
  void _schedulePrefetch() {
    if (!hasScript || _voiceId.isEmpty) return;
    for (var offset = 1; offset <= _prefetchAhead; offset++) {
      final at = _index + offset;
      if (at >= _script.length) break;
      _tts.prefetch(_script[at].text, _voiceId, priority: offset);
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    position.dispose();
    cursor.dispose();
    _player.dispose();
    super.dispose();
  }
}
