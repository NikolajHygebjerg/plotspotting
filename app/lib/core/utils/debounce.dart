import 'dart:async';

/// Simple debouncer for search fields and similar UI.
class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}

/// Runs [action] at most once per [interval].
class Throttler {
  Throttler(this.interval);

  final Duration interval;
  bool _locked = false;

  void run(void Function() action) {
    if (_locked) return;
    _locked = true;
    action();
    Timer(interval, () => _locked = false);
  }
}
