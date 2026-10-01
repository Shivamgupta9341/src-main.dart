import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' show AudioPlayer, BytesSource;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const LudoApp());

// ═════════════════════════ Constants ═════════════════════════
const kColors = [
  Color(0xFFE53935), // Red
  Color(0xFF43A047), // Green
  Color(0xFFFDD835), // Yellow
  Color(0xFF1E88E5), // Blue
];
const kNames = ['Red', 'Green', 'Yellow', 'Blue'];
const kStart = [0, 13, 26, 39];
const kSafe = {0, 8, 13, 21, 26, 34, 39, 47};
const kService = 'com.example.ludo_nearby';
const kOrigin = [Offset(0, 0), Offset(9, 0), Offset(9, 9), Offset(0, 9)];
const kBaseSpots = [Offset(2, 2), Offset(4, 2), Offset(2, 4), Offset(4, 4)];
const kEmojis = ['😂', '🔥', '👏', '😡', '😎'];
// Power cards: 0 = Reroll, 1 = Shield, 2 = Freeze
const kCardIcon = ['🔁', '🛡️', '🧊'];
const kCardName = ['Reroll', 'Shield', 'Freeze'];

List<Offset> _buildTrack() {
  final t = <Offset>[];
  void add(int c, int r) => t.add(Offset(c.toDouble(), r.toDouble()));
  for (var c = 1; c <= 5; c++) add(c, 6);
  for (var r = 5; r >= 0; r--) add(6, r);
  add(7, 0);
  add(8, 0);
  for (var r = 1; r <= 5; r++) add(8, r);
  for (var c = 9; c <= 14; c++) add(c, 6);
  add(14, 7);
  add(14, 8);
  for (var c = 13; c >= 9; c--) add(c, 8);
  for (var r = 9; r <= 14; r++) add(8, r);
  add(7, 14);
  add(6, 14);
  for (var r = 13; r >= 9; r--) add(6, r);
  for (var c = 5; c >= 0; c--) add(c, 8);
  add(0, 7);
  add(0, 6);
  return t;
}

final List<Offset> kTrack = _buildTrack();
final List<List<Offset>> kHome = [
  [for (var c = 1; c <= 5; c++) Offset(c.toDouble(), 7)],
  [for (var r = 1; r <= 5; r++) Offset(7, r.toDouble())],
  [for (var c = 13; c >= 9; c--) Offset(c.toDouble(), 7)],
  [for (var r = 13; r >= 9; r--) Offset(7, r.toDouble())],
];
const kFinish = [Offset(6, 7), Offset(7, 6), Offset(8, 7), Offset(7, 8)];

// ═════════════════════════ Sound effects (generated in code, no files) ═════════════════════════
class Sfx {
  static const sr = 22050;
  final _r = Random();
  final Map<String, Uint8List> _d = {};
  final List<AudioPlayer> _pool = [];
  int _n = 0;
  bool on = true;

  Sfx() {
    try {
      for (var i = 0; i < 3; i++) {
        _pool.add(AudioPlayer());
      }
    } catch (_) {}
    _d['roll'] = _wav(_rattle());
    _d['move'] = _wav(_tone(720, 520, .07, .45));
    _d['card'] = _wav([..._tone(600, 900, .08, .45), ..._tone(900, 1300, .12, .45)]);
    _d['cap'] = _wav(_tone(700, 120, .35, .5, square: true));
    _d['win'] = _wav([
      ..._tone(523, 523, .15, .5),
      ..._tone(659, 659, .15, .5),
      ..._tone(784, 784, .15, .5),
      ..._tone(1047, 1047, .35, .5),
    ]);
  }

  List<double> _tone(double f0, double f1, double dur, double vol,
      {bool square = false}) {
    final n = (sr * dur).round();
    final out = List<double>.filled(n, 0);
    var ph = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final f = f0 + (f1 - f0) * t;
      ph += 2 * pi * f / sr;
      var v = sin(ph);
      if (square) v = v >= 0 ? .6 : -.6;
      final env = (1 - t) * min(1.0, i / (sr * .004));
      out[i] = v * env * vol;
    }
    return out;
  }

  List<double> _rattle() {
    final n = (sr * .6).round();
    final out = List<double>.filled(n, 0);
    for (var k = 0; k < 7; k++) {
      final st = (k * sr * .08).round();
      final len = (sr * .04).round();
      for (var i = 0; i < len && st + i < n; i++) {
        out[st + i] = (_r.nextDouble() * 2 - 1) * (1 - i / len) * .5;
      }
    }
    return out;
  }

  Uint8List _wav(List<double> s) {
    final n = s.length;
    final b = ByteData(44 + n * 2);
    void str(int o, String t) {
      for (var i = 0; i < t.length; i++) {
        b.setUint8(o + i, t.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, sr, Endian.little);
    b.setUint32(28, sr * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final v = (s[i].clamp(-1.0, 1.0) * 32767).round();
      b.setInt16(44 + i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  void play(String k) {
    if (!on || _pool.isEmpty) return;
    try {
      final p = _pool[_n++ % _pool.length];
      p.play(BytesSource(_d[k]!)).catchError((_) {});
    } catch (_) {}
  }
}

// ═════════════════════════ Game logic (host is the referee) ═════════════════════════
// pos: -1 = in base, 0..50 = main track (relative to own start),
// 51..55 = home column, 56 = home (finished).
class Game {
  List<List<int>> pos = List.generate(4, (_) => List.filled(4, -1));
  List<bool> active = [true, false, false, false];
  List<String> names = List.of(kNames);
  List<int> rank = [];
  List<List<int>> cards = List.generate(4, (_) => <int>[]);
  List<bool> shield = List.filled(4, false);
  List<bool> skip = List.filled(4, false);
  bool team = false; // 2 vs 2: Red+Yellow against Green+Blue
  int turn = 0, dice = 0, lastRoll = 0, lastRoller = -1;
  int rollSeq = 0, sixes = 0, winner = -1;
  bool started = false;
  String msg = 'Waiting for players...';

  String n(int c) => names[c];

  Map<String, dynamic> toJson() => {
        'pos': pos,
        'active': active,
        'names': names,
        'rank': rank,
        'cards': cards,
        'shield': shield,
        'skip': skip,
        'team': team,
        'turn': turn,
        'dice': dice,
        'lastRoll': lastRoll,
        'lastRoller': lastRoller,
        'rollSeq': rollSeq,
        'sixes': sixes,
        'winner': winner,
        'started': started,
        'msg': msg,
      };

  void loadJson(Map<String, dynamic> j) {
    pos = (j['pos'] as List)
        .map((r) => (r as List).map((e) => e as int).toList())
        .toList();
    active = (j['active'] as List).map((e) => e as bool).toList();
    names = (j['names'] as List).map((e) => e as String).toList();
    rank = (j['rank'] as List).map((e) => e as int).toList();
    cards = (j['cards'] as List)
        .map((r) => (r as List).map((e) => e as int).toList())
        .toList();
    shield = (j['shield'] as List).map((e) => e as bool).toList();
    skip = (j['skip'] as List).map((e) => e as bool).toList();
    team = j['team'] as bool;
    turn = j['turn'] as int;
    dice = j['dice'] as int;
    lastRoll = j['lastRoll'] as int;
    lastRoller = j['lastRoller'] as int;
    rollSeq = j['rollSeq'] as int;
    sixes = j['sixes'] as int;
    winner = j['winner'] as int;
    started = j['started'] as bool;
    msg = j['msg'] as String;
  }

  int partner(int c) => (c + 2) % 4;

  // Whose tokens does player c move? In team mode, a player whose own
  // tokens are all home moves their partner's tokens.
  int ctl(int c) =>
      (team && pos[c].every((e) => e == 56) && active[partner(c)])
          ? partner(c)
          : c;

  bool canMove(int c, int i) {
    if (dice == 0) return false;
    final p = pos[ctl(c)][i];
    if (p == -1) return dice == 6;
    return p + dice <= 56;
  }

  List<int> movable(int c) => [
        for (var i = 0; i < 4; i++)
          if (canMove(c, i)) i
      ];

  int _next() {
    var t = turn;
    for (var k = 0; k < 4; k++) {
      t = (t + 1) % 4;
      if (active[t] && !rank.contains(t)) return t;
    }
    return turn;
  }

  int nextTurn() {
    var t = turn;
    for (var k = 0; k < 8; k++) {
      t = (t + 1) % 4;
      if (!active[t] || rank.contains(t)) continue;
      if (skip[t]) {
        skip[t] = false;
        msg += ' (${n(t)} is frozen and skipped)';
        continue;
      }
      return t;
    }
    return turn;
  }

  void pass() {
    dice = 0;
    sixes = 0;
    turn = nextTurn();
    shield[turn] = false;
  }

  bool giveCard(int c) {
    if (cards[c].length >= 3) return false;
    cards[c].add(Random().nextInt(3));
    return true;
  }

  void dealCards() {
    for (var c = 0; c < 4; c++) {
      cards[c] = [];
      shield[c] = false;
      skip[c] = false;
      if (active[c]) giveCard(c);
    }
  }

  void useCard(int c, int k) {
    if (!started || winner >= 0 || c != turn || !cards[c].contains(k)) return;
    if (k == 0) {
      if (dice == 0) return;
      cards[c].remove(k);
      if (dice == 6 && sixes > 0) sixes--;
      dice = 0;
      roll(c);
      msg = '${n(c)} used Reroll: $msg';
    } else {
      if (dice != 0) return;
      cards[c].remove(k);
      if (k == 1) {
        shield[c] = true;
        msg = '${n(c)} raised a Shield until their next turn';
      } else {
        final t = _next();
        if (t == c) {
          cards[c].add(k);
          return;
        }
        skip[t] = true;
        msg = '${n(c)} froze ${n(t)} - they miss a turn';
      }
    }
  }

  void roll(int c) {
    if (!started || winner >= 0 || c != turn || dice != 0) return;
    dice = Random().nextInt(6) + 1;
    lastRoll = dice;
    lastRoller = c;
    rollSeq++;
    sixes = dice == 6 ? sixes + 1 : 0;
    if (sixes >= 3) {
      msg = '${n(c)} rolled three 6s in a row - turn lost!';
      pass();
      return;
    }
    if (movable(c).isEmpty) {
      msg = '${n(c)} rolled $dice - no move';
      pass();
    } else {
      msg = '${n(c)} rolled $dice - pick a token';
    }
  }

  void move(int c, int i) {
    if (!started || winner >= 0 || c != turn || !canMove(c, i)) return;
    final k = ctl(c);
    final p = pos[k][i];
    final np = p == -1 ? 0 : p + dice;
    pos[k][i] = np;
    var cap = false, blocked = false;
    if (np <= 50) {
      final a = (kStart[k] + np) % 52;
      if (!kSafe.contains(a)) {
        for (var o = 0; o < 4; o++) {
          if (o == k || !active[o]) continue;
          if (team && o % 2 == k % 2) continue;
          for (var j = 0; j < 4; j++) {
            final q = pos[o][j];
            if (q >= 0 && q <= 50 && (kStart[o] + q) % 52 == a) {
              if (shield[o]) {
                blocked = true;
              } else {
                pos[o][j] = -1;
                cap = true;
              }
            }
          }
        }
      }
    }
    var gotCard = false;
    if (cap || np == 56) gotCard = giveCard(c);
    if (team) {
      final mem = [
        for (var x = 0; x < 4; x++)
          if (active[x] && x % 2 == c % 2) x
      ];
      if (mem.every((x) => pos[x].every((e) => e == 56))) {
        winner = c;
        dice = 0;
        msg = '${mem.map(n).join(' & ')} win! 🎉';
        return;
      }
    } else if (pos[c].every((e) => e == 56)) {
      rank.add(c);
      final left = [
        for (var x = 0; x < 4; x++)
          if (active[x] && !rank.contains(x)) x
      ];
      if (left.length <= 1) {
        if (left.length == 1) rank.add(left.first);
        winner = rank.first;
        dice = 0;
        msg = '${n(winner)} wins! 🎉';
        return;
      }
      msg = '${n(c)} finished #${rank.length}! 🎉';
      pass();
      return;
    }
    final extra = dice == 6 || cap || np == 56;
    dice = 0;
    msg = '${n(c)} moved${cap ? ' and captured a token!' : ''}${blocked ? ' - the Shield blocked a capture!' : ''}${gotCard ? ' +1 power card' : ''}';
    if (extra) {
      msg += ' - roll again';
    } else {
      pass();
    }
  }

  // Start a fresh game with the same players
  void reset() {
    pos = List.generate(4, (_) => List.filled(4, -1));
    rank = [];
    winner = -1;
    dice = 0;
    lastRoll = 0;
    lastRoller = -1;
    sixes = 0;
    started = true;
    turn = max<int>(0, active.indexOf(true));
    dealCards();
    msg = 'New game - ${n(turn)} starts';
  }

  // A player leaves (or is removed) - the others carry on
  void removePlayer(int c) {
    if (!active[c]) return;
    final nm = names[c];
    active[c] = false;
    pos[c] = [-1, -1, -1, -1];
    cards[c] = [];
    shield[c] = false;
    skip[c] = false;
    names[c] = kNames[c];
    team = false;
    if (started && winner < 0) {
      final left = [
        for (var k = 0; k < 4; k++)
          if (active[k] && !rank.contains(k)) k
      ];
      if (left.length <= 1) {
        if (left.length == 1) rank.add(left.first);
        winner = rank.isNotEmpty ? rank.first : 0;
        dice = 0;
        msg = '${n(winner)} wins - the others left';
      } else if (turn == c) {
        msg = '$nm left the game';
        pass();
      } else {
        msg = '$nm left the game';
      }
    } else if (!started) {
      msg = '$nm left';
    }
  }
}

// ═════════════════════════ Token position helpers ═════════════════════════
Offset cellCenter(int c, int p) {
  Offset cell;
  if (p <= 50) {
    cell = kTrack[(kStart[c] + p) % 52];
  } else if (p <= 55) {
    cell = kHome[c][p - 51];
  } else {
    cell = kFinish[c];
  }
  return cell + const Offset(0.5, 0.5);
}

// d = display position (can be fractional while animating)
Offset tokenAt(int c, int i, double d, {Offset off = Offset.zero}) {
  final base = kOrigin[c] + kBaseSpots[i];
  if (d <= -1) return base;
  if (d < 0) return Offset.lerp(base, cellCenter(c, 0), d + 1)!;
  final lo = min(max(d.floor(), 0), 56);
  final hi = min(lo + 1, 56);
  return Offset.lerp(cellCenter(c, lo), cellCenter(c, hi), d - lo)! + off;
}

Offset stackOff(Game g, int c, int i) {
  final p = g.pos[c][i];
  var off = Offset.zero;
  if (p < 0) return off;
  if (p <= 50 && kSafe.contains((kStart[c] + p) % 52)) {
    off = Offset((c % 2 == 0 ? -1 : 1) * .09, (c < 2 ? -1 : 1) * .09);
  }
  final same = [
    for (var j = 0; j < 4; j++)
      if (g.pos[c][j] == p) j
  ];
  if (same.length > 1) {
    final k = same.indexOf(i);
    off += Offset(k % 2 == 0 ? -.15 : .15, k < 2 ? -.15 : .15);
  }
  return off;
}

// ═════════════════════════ App ═════════════════════════
class LudoApp extends StatelessWidget {
  const LudoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ludo Friends',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.indigo,
            useMaterial3: true),
        home: const LudoHome(),
      );
}

class LudoHome extends StatefulWidget {
  const LudoHome({super.key});
  @override
  State<LudoHome> createState() => _LudoHomeState();
}

class _LudoHomeState extends State<LudoHome> with TickerProviderStateMixin {
  final _name =
      TextEditingController(text: 'Player${Random().nextInt(900) + 100}');
  final sfx = Sfx();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();
  late final AnimationController _moveCtl = AnimationController(
      vsync: this, value: 1.0, duration: const Duration(milliseconds: 400));
  late final AnimationController _rollCtl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  Game g = Game();
  bool isHost = false, inRoom = false, discovering = false;
  int myColor = 0;
  String? hostId;
  String status = '';
  final Map<String, int> clients = {};
  final Map<String, String> found = {};
  final Map<String, String> _pending = {};
  final Map<int, String> emo = {};
  bool isLocal = false, localSetup = false, teamMode = false;
  int localCount = 4;
  final List<TextEditingController> _lnames =
      List.generate(4, (_) => TextEditingController());
  int get _self => isLocal ? g.turn : myColor;

  List<List<int>>? _from; // token positions before the current move animation
  bool _rolling = false, _winPlayed = false;
  int _rollColor = 0, _face = 1, _seenRoll = 0, _lastCards = 0;
  Timer? _flick;

  @override
  void initState() {
    super.initState();
    for (var c = 0; c < 4; c++) {
      _lnames[c].text = 'Player ${c + 1}';
    }
    _moveCtl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _from = null);
      }
    });
  }

  @override
  void dispose() {
    _flick?.cancel();
    _pulse.dispose();
    _moveCtl.dispose();
    _rollCtl.dispose();
    _name.dispose();
    for (final t in _lnames) {
      t.dispose();
    }
    super.dispose();
  }

  // ───────── helpers ─────────
  Uint8List _bytes(Map m) => Uint8List.fromList(utf8.encode(jsonEncode(m)));
  void _send(String id, Map m) => Nearby().sendBytesPayload(id, _bytes(m));
  void _sendHost(Map m) {
    if (hostId != null) _send(hostId!, m);
  }

  void _sendAll(Map m) {
    final b = _bytes(m);
    for (final id in clients.keys) {
      Nearby().sendBytesPayload(id, b);
    }
  }

  List<List<int>> _snap() => g.pos.map((r) => List<int>.from(r)).toList();

  Future<void> _perms() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();
    final gpsOn = await Permission.location.serviceStatus.isEnabled;
    if (!gpsOn && mounted) {
      setState(() => status = 'Please turn on Location (GPS) in your phone settings');
    }
  }

  // ───────── animations / sounds ─────────
  void _animateFrom(List<List<int>> before) {
    var steps = 0;
    var cap = false;
    for (var c = 0; c < 4; c++) {
      for (var i = 0; i < 4; i++) {
        final a = before[c][i], b = g.pos[c][i];
        if (a == b) continue;
        if (b == -1 && a >= 0) {
          cap = true;
          continue;
        }
        steps = max<int>(steps, b - a);
      }
    }
    if (steps == 0 && !cap) return;
    _from = before;
    final int ms = 170 * max<int>(steps, 1) + 150;
    _moveCtl.duration = Duration(milliseconds: ms);
    _moveCtl.forward(from: 0);
    for (var s = 0; s < min(steps, 6); s++) {
      Future.delayed(Duration(milliseconds: 170 * s), () => sfx.play('move'));
    }
    if (cap) {
      Future.delayed(Duration(milliseconds: ms), () {
        sfx.play('cap');
        HapticFeedback.heavyImpact();
      });
    }
  }

  void _startRoll(int c) {
    _flick?.cancel();
    _rolling = true;
    _rollColor = c;
    _face = Random().nextInt(6) + 1;
    sfx.play('roll');
    HapticFeedback.mediumImpact();
    _rollCtl.forward(from: 0);
    _flick = Timer.periodic(const Duration(milliseconds: 70), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _face = Random().nextInt(6) + 1);
    });
    Timer(const Duration(milliseconds: 700), () {
      _flick?.cancel();
      if (mounted) setState(() => _rolling = false);
    });
  }

  void _afterChange(List<List<int>> before) {
    _animateFrom(before);
    if (g.rollSeq != _seenRoll) {
      _seenRoll = g.rollSeq;
      _startRoll(g.lastRoller);
    }
    final tot = g.cards.fold<int>(0, (a, l) => a + l.length);
    if (tot > _lastCards) sfx.play('card');
    _lastCards = tot;
    if (g.winner < 0) _winPlayed = false;
    if (g.winner >= 0 && !_winPlayed) {
      _winPlayed = true;
      Future.delayed(const Duration(milliseconds: 600), () => sfx.play('win'));
    }
    setState(() {});
  }

  // Host: every change to the game goes through here
  void _hostAct(void Function() fn) {
    final before = _snap();
    fn();
    _afterChange(before);
    _sendAll({'t': 'state', 'g': g.toJson()});
    _maybeAuto();
  }

  // If there is only one sensible move, play it automatically
  void _maybeAuto() {
    if (!isHost || !g.started || g.winner >= 0 || g.dice == 0) return;
    final c = g.turn;
    final mv = g.movable(c);
    if (mv.isEmpty) return;
    final k = g.ctl(c);
    final uniq = mv.map((i) => g.pos[k][i]).toSet();
    if (uniq.length != 1) return;
    final seq = g.rollSeq;
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted || g.rollSeq != seq || g.dice == 0 || g.turn != c) return;
      _hostAct(() => g.move(c, mv.first));
    });
  }

  // ───────── host ─────────
  Future<void> _host() async {
    await _perms();
    g = Game();
    final nm = _name.text.trim();
    g.names[0] = nm.isEmpty ? 'Red' : nm;
    isHost = true;
    myColor = 0;
    clients.clear();
    _seenRoll = 0;
    _winPlayed = false;
    try {
      await Nearby().startAdvertising(
        _name.text,
        Strategy.P2P_STAR,
        onConnectionInitiated: (id, info) {
          _pending[id] = info.endpointName;
          Nearby().acceptConnection(id,
              onPayLoadRecieved: _onPayload,
              onPayloadTransferUpdate: (a, b) {});
        },
        onConnectionResult: (id, s) {
          if (s == Status.CONNECTED) _onJoined(id);
        },
        onDisconnected: _onLeft,
        serviceId: kService,
      );
      setState(() => inRoom = true);
    } catch (e) {
      setState(() => status = 'Error: $e');
    }
  }

  void _onJoined(String id) {
    final free = [1, 2, 3].where((c) => !g.active[c]).toList();
    if (free.isEmpty || g.started) {
      Nearby().disconnectFromEndpoint(id);
      return;
    }
    final c = free.first;
    clients[id] = c;
    _send(id, {'t': 'hello', 'color': c});
    _hostAct(() {
      g.active[c] = true;
      g.names[c] = _pending[id] ?? kNames[c];
      g.msg = '${g.names[c]} joined';
    });
  }

  void _onLeft(String id) {
    if (!isHost) {
      if (id == hostId) {
        _leave();
        setState(() => status = 'Host disconnected');
      }
      return;
    }
    final c = clients.remove(id);
    if (c == null) return;
    _hostAct(() => g.removePlayer(c));
  }

  void _start() {
    Nearby().stopAdvertising();
    _winPlayed = false;
    _hostAct(() {
      g.started = true;
      if (g.active.where((a) => a).length < 4) g.team = false;
      g.dealCards();
      g.turn = 0;
      g.dice = 0;
      g.msg = '${g.n(0)} starts - roll the dice';
    });
  }

  // ───────── joiner ─────────
  Future<void> _discover() async {
    await _perms();
    found.clear();
    isHost = false;
    try {
      await Nearby().startDiscovery(
        _name.text,
        Strategy.P2P_STAR,
        onEndpointFound: (id, n, s) => setState(() => found[id] = n),
        onEndpointLost: (id) => setState(() => found.remove(id)),
        serviceId: kService,
      );
      setState(() => discovering = true);
    } catch (e) {
      setState(() => status = 'Error: $e');
    }
  }

  void _connect(String endpoint) {
    Nearby().requestConnection(
      _name.text,
      endpoint,
      onConnectionInitiated: (id, info) {
        Nearby().acceptConnection(id,
            onPayLoadRecieved: _onPayload, onPayloadTransferUpdate: (a, b) {});
      },
      onConnectionResult: (id, s) {
        if (s == Status.CONNECTED) {
          Nearby().stopDiscovery();
          setState(() {
            hostId = id;
            inRoom = true;
            discovering = false;
            status = '';
          });
        } else {
          setState(() => status = 'Connection failed, try again');
        }
      },
      onDisconnected: _onLeft,
    );
  }

  // ───────── messages ─────────
  void _onPayload(String id, Payload p) {
    if (p.type != PayloadType.BYTES || p.bytes == null) return;
    final m = jsonDecode(utf8.decode(p.bytes!)) as Map<String, dynamic>;
    if (isHost) {
      final c = clients[id];
      if (c == null) return;
      if (m['t'] == 'roll') _hostAct(() => g.roll(c));
      if (m['t'] == 'move') _hostAct(() => g.move(c, m['i'] as int));
      if (m['t'] == 'card') _hostAct(() => g.useCard(c, m['k'] as int));
      if (m['t'] == 'emo') {
        final e = m['e'] as String;
        _showEmoji(c, e);
        _sendAll({'t': 'emo', 'c': c, 'e': e});
      }
    } else {
      if (m['t'] == 'hello') myColor = m['color'] as int;
      if (m['t'] == 'state') {
        final before = _snap();
        g.loadJson(m['g'] as Map<String, dynamic>);
        _afterChange(before);
      }
      if (m['t'] == 'emo') _showEmoji(m['c'] as int, m['e'] as String);
    }
  }

  void _showEmoji(int c, String e) {
    setState(() => emo[c] = e);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && emo[c] == e) setState(() => emo.remove(c));
    });
  }

  void _sendEmoji(String e) {
    if (isHost) {
      _showEmoji(0, e);
      _sendAll({'t': 'emo', 'c': 0, 'e': e});
    } else {
      _sendHost({'t': 'emo', 'e': e});
    }
  }

  void _rollTap() {
    if (isHost) {
      _hostAct(() => g.roll(_self));
    } else {
      _sendHost({'t': 'roll'});
    }
  }

  void _moveTap(int i) {
    if (isHost) {
      _hostAct(() => g.move(_self, i));
    } else {
      _sendHost({'t': 'move', 'i': i});
    }
  }

  void _useCard(int k) {
    String? why;
    if (g.turn != _self || g.winner >= 0) {
      why = "It's not your turn";
    } else if (k == 0 && g.dice == 0) {
      why = 'Roll the dice first, then use Reroll';
    } else if (k != 0 && g.dice != 0) {
      why = 'Use this before rolling the dice';
    }
    if (why != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(why), duration: const Duration(seconds: 2)));
      return;
    }
    if (isHost) {
      _hostAct(() => g.useCard(_self, k));
    } else {
      _sendHost({'t': 'card', 'k': k});
    }
  }

  Widget _cardTray() {
    final mine = g.cards[_self];
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (mine.isEmpty)
            const Flexible(
              child: Text('No power cards - capture a token or reach home to earn one',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          for (var i = 0; i < mine.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                avatar: Text(kCardIcon[mine[i]]),
                label: Text(kCardName[mine[i]]),
                onPressed: () => _useCard(mine[i]),
              ),
            ),
        ],
      ),
    );
  }

  void _boardTap(Offset o, double s) {
    if (g.turn != _self || g.dice == 0 || g.winner >= 0 || _from != null) {
      return;
    }
    final k = g.ctl(_self);
    int? best;
    var bestD = 0.75 * s;
    for (final i in g.movable(_self)) {
      final pt = tokenAt(k, i, g.pos[k][i].toDouble(),
              off: stackOff(g, k, i)) *
          s;
      final d = (pt - o).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best != null) _moveTap(best);
  }

  void _leave() {
    if (!isLocal) {
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
      Nearby().stopAllEndpoints();
    }
    _flick?.cancel();
    setState(() {
      inRoom = false;
      discovering = false;
      isHost = false;
      clients.clear();
      found.clear();
      _pending.clear();
      emo.clear();
      hostId = null;
      g = Game();
      myColor = 0;
      _from = null;
      _rolling = false;
      _seenRoll = 0;
      _lastCards = 0;
      _winPlayed = false;
      isLocal = false;
      localSetup = false;
      status = '';
    });
  }

  // ───────── screens ─────────
  @override
  Widget build(BuildContext context) {
    Widget body;
    var inGame = false;
    if (!inRoom && !discovering && localSetup) {
      body = _localSetup();
    } else if (!inRoom && !discovering) {
      body = _menu();
    } else if (discovering && !inRoom) {
      body = _finder();
    } else if (g.started) {
      body = _gameView();
      inGame = true;
    } else {
      body = _lobby();
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0D1440),
      appBar: inGame
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: (localSetup && !inRoom)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => localSetup = false))
                  : null,
              title: const Text('Ludo Friends'),
              actions: [
                if (inRoom || discovering)
                  IconButton(
                      icon: const Icon(Icons.exit_to_app), onPressed: _leave),
              ],
            ),
      body: SizedBox.expand(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2B3F9E), Color(0xFF0D1440)],
            ),
          ),
          child: CustomPaint(
            painter: BgPainter(),
            child: SafeArea(child: body),
          ),
        ),
      ),
    );
  }

  List<int> _cols() =>
      localCount == 2 ? [0, 2] : (localCount == 3 ? [0, 1, 2] : [0, 1, 2, 3]);

  void _startLocal() {
    g = Game();
    isLocal = true;
    isHost = true;
    myColor = 0;
    final cols = _cols();
    for (var c = 0; c < 4; c++) {
      g.active[c] = cols.contains(c);
      final t = _lnames[c].text.trim();
      g.names[c] = t.isEmpty ? kNames[c] : t;
    }
    g.team = localCount == 4 && teamMode;
    _seenRoll = 0;
    _lastCards = 0;
    _winPlayed = false;
    setState(() => inRoom = true);
    _hostAct(() {
      g.started = true;
      g.dealCards();
      g.turn = 0;
      g.msg = '${g.n(0)} starts - roll the dice';
    });
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the game?'),
        content: Text(isLocal
            ? 'This ends the game for everyone.'
            : (isHost
                ? 'You are the host - the game will end for everyone.'
                : 'The other players will carry on without you.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) _leave();
  }

  Future<void> _removeDialog() async {
    final c = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Who is leaving?'),
        children: [
          for (var k = 0; k < 4; k++)
            if (g.active[k])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, k),
                child: Row(
                  children: [
                    CircleAvatar(radius: 8, backgroundColor: kColors[k]),
                    const SizedBox(width: 10),
                    Text(g.names[k]),
                  ],
                ),
              ),
        ],
      ),
    );
    if (c != null) _hostAct(() => g.removePlayer(c));
  }

  Widget _localSetup() => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Text('Play on this phone',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Everyone sits together and passes the phone around. No internet or Bluetooth needed.',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            const Text('How many players?'),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(value: 2, label: Text('2 players')),
                ButtonSegment<int>(value: 3, label: Text('3 players')),
                ButtonSegment<int>(value: 4, label: Text('4 players')),
              ],
              selected: {localCount},
              onSelectionChanged: (v) => setState(() {
                localCount = v.first;
                if (localCount < 4) teamMode = false;
              }),
            ),
            if (localCount == 4)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('2 vs 2 teams'),
                subtitle: const Text(
                    'Red + Yellow vs Green + Blue. Partners never capture each other, and a team wins when all 8 tokens are home.'),
                value: teamMode,
                onChanged: (v) => setState(() => teamMode = v),
              ),
            const SizedBox(height: 12),
            for (final c in _cols())
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _lnames[c],
                  decoration: InputDecoration(
                    labelText: '${kNames[c]} player name',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.circle, color: kColors[c]),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
                onPressed: _startLocal,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start game')),
          ],
        ),
      );

  Widget _menu() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('🎲',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 72)),
            const Text('LUDO FRIENDS',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2)),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Your name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: () => setState(() => localSetup = true),
                icon: const Icon(Icons.groups),
                label: const Text('Play on this phone (offline)')),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
                onPressed: _host,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Host game (WiFi / Bluetooth)')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _discover,
                icon: const Icon(Icons.search),
                label: const Text('Join game')),
            const SizedBox(height: 20),
            const Text(
              'Phones connect directly (Bluetooth + WiFi, no internet needed). '
              'Keep phones close and turn on Bluetooth, WiFi and Location.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
      );

  Widget _finder() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Searching for nearby hosts...'),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            if (status.isNotEmpty)
              Text(status, style: const TextStyle(color: Colors.redAccent)),
            for (final e in found.entries)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: Text(e.value),
                  trailing: FilledButton(
                      onPressed: () => _connect(e.key),
                      child: const Text('Join')),
                ),
              ),
          ],
        ),
      );

  Widget _lobby() {
    final n = g.active.where((a) => a).length;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
              isHost
                  ? 'Room ready - waiting for friends'
                  : 'Connected - waiting for host to start',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          for (var c = 0; c < 4; c++)
            Card(
              color: g.active[c] ? kColors[c].withOpacity(.25) : Colors.white10,
              child: ListTile(
                leading: CircleAvatar(backgroundColor: kColors[c]),
                title: Text(g.active[c]
                    ? g.names[c] + (c == myColor ? '  (you)' : '')
                    : 'Waiting for player...'),
                subtitle: Text(kNames[c]),
                trailing: Icon(
                    g.active[c] ? Icons.check_circle : Icons.hourglass_empty),
              ),
            ),
          if (isHost && n == 4)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('2 vs 2 teams'),
              subtitle: const Text('Red + Yellow vs Green + Blue'),
              value: g.team,
              onChanged: (v) => _hostAct(() => g.team = v),
            ),
          const SizedBox(height: 8),
          const Text(
            'Power cards (everyone can see them):\n'
            '🔁 Reroll - after rolling, throw the dice again\n'
            '🛡️ Shield - before rolling, your tokens can\'t be captured until your next turn\n'
            '🧊 Freeze - before rolling, the next player misses a turn\n'
            'You start with 1 card. Capture a token or reach home to earn more (max 3).',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const Spacer(),
          if (isHost)
            FilledButton(
                onPressed: n >= 2 ? _start : null,
                child: Text('Start game ($n players)')),
        ],
      ),
    );
  }

  Widget _gameView() {
    final pickable = g.turn == _self &&
        g.dice > 0 &&
        g.winner < 0 &&
        !g.rank.contains(_self);
    return Stack(
      children: [
        Column(
          children: [
            _topBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_panel(0), _panel(1)],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(builder: (ctx, box) {
                      final s = box.maxWidth / 15;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black54,
                                blurRadius: 14,
                                offset: Offset(0, 6))
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: GestureDetector(
                            onTapUp: (d) => _boardTap(d.localPosition, s),
                            child: CustomPaint(
                              size: Size(box.maxWidth, box.maxWidth),
                              painter: BoardPainter(
                                g: g,
                                me: _self,
                                pickable: pickable,
                                from: _from,
                                moveCtl: _moveCtl,
                                pulse: _pulse,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_panel(3), _panel(2)],
              ),
            ),
            _cardTray(),
            if (!isLocal)
              Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final e in kEmojis)
                  TextButton(
                      onPressed: () => _sendEmoji(e),
                      child: Text(e, style: const TextStyle(fontSize: 24))),
              ],
            ),
          ],
        ),
        if (g.winner >= 0) _result(),
      ],
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          children: [
            isLocal
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.menu),
                    onSelected: (v) {
                      if (v == 'rm') {
                        _removeDialog();
                      } else {
                        _confirmExit();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rm', child: Text('A player is leaving')),
                      PopupMenuItem(value: 'exit', child: Text('End game & exit')),
                    ],
                  )
                : IconButton(
                    icon: const Icon(Icons.exit_to_app),
                    onPressed: _confirmExit),
            Expanded(
              child: Text(g.msg,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: Icon(sfx.on ? Icons.volume_up : Icons.volume_off),
              onPressed: () => setState(() => sfx.on = !sfx.on),
            ),
          ],
        ),
      );

  Widget _panel(int c) {
    if (!g.active[c]) return const SizedBox(width: 150, height: 96);
    final col = kColors[c];
    final fin = g.rank.contains(c);
    final turnNow = g.turn == c && g.winner < 0 && !fin;
    final mine = c == _self;
    final canRoll = turnNow && mine && g.dice == 0 && !_rolling;
    var shown = 0;
    var spin = false;
    if (_rolling && _rollColor == c) {
      shown = _face;
      spin = true;
    } else if (g.lastRoller == c) {
      shown = g.lastRoll;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 150,
      height: 96,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: turnNow ? col.withOpacity(.28) : Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: turnNow ? col : Colors.white24, width: turnNow ? 2.5 : 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CircleAvatar(radius: 8, backgroundColor: col),
                    for (final k in g.cards[c])
                      Text(kCardIcon[k], style: const TextStyle(fontSize: 14)),
                    if (emo[c] != null)
                      Text(emo[c]!, style: const TextStyle(fontSize: 20)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(g.names[c] + (mine && !isLocal ? ' (you)' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                Text(
                  [
                    if (fin) '🏅 #${g.rank.indexOf(c) + 1}',
                    if (g.shield[c]) '🛡️ Shield',
                    if (g.skip[c]) '🧊 Frozen',
                    if (g.team) 'Team ${c % 2 == 0 ? 'A' : 'B'}',
                  ].join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: canRoll ? _rollTap : null,
            child: _dice(shown, spin, canRoll, col),
          ),
        ],
      ),
    );
  }

  Widget _dice(int shown, bool spin, bool glow, Color col) {
    return AnimatedBuilder(
      animation: Listenable.merge([_rollCtl, _pulse]),
      builder: (_, __) {
        final ang = spin ? _rollCtl.value * pi * 4 : 0.0;
        final gl = glow ? 0.5 + 0.5 * sin(_pulse.value * 2 * pi) : 0.0;
        return Transform.rotate(
          angle: ang,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: shown == 0 ? Colors.white60 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: glow ? col.withOpacity(.4 + .5 * gl) : Colors.black38,
                  blurRadius: glow ? 14 : 4,
                  spreadRadius: glow ? 2 * gl : 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: shown == 0
                ? (glow
                    ? const Center(
                        child: Text('TAP',
                            style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w900)))
                    : null)
                : CustomPaint(
                    size: const Size(52, 52), painter: PipPainter(shown)),
          ),
        );
      },
    );
  }

  Widget _result() {
    const medals = ['🥇', '🥈', '🥉', '4️⃣'];
    final winners = [
      for (var x = 0; x < 4; x++)
        if (g.active[x] && g.winner >= 0 && x % 2 == g.winner % 2) g.names[x]
    ].join(' & ');
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏆 Game Over',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  if (g.team)
                    Text('$winners win!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold))
                  else
                    for (var k = 0; k < g.rank.length; k++)
                      ListTile(
                        leading: Text(medals[k],
                            style: const TextStyle(fontSize: 28)),
                        title: Text(g.names[g.rank[k]]),
                        trailing: CircleAvatar(
                            radius: 9, backgroundColor: kColors[g.rank[k]]),
                      ),
                  const SizedBox(height: 12),
                  if (isHost)
                    FilledButton(
                        onPressed: () => _hostAct(g.reset),
                        child: const Text('Play again'))
                  else
                    const Text('Waiting for the host to start a new game...',
                        style: TextStyle(fontSize: 12)),
                  TextButton(onPressed: _leave, child: const Text('Exit')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Painters ═════════════════════════
class BgPainter extends CustomPainter {
  @override
  void paint(Canvas cv, Size size) {
    final p = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 1.2;
    const step = 48.0;
    for (var x = -size.height; x < size.width; x += step) {
      cv.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
      cv.drawLine(Offset(x + size.height, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class PipPainter extends CustomPainter {
  final int v;
  PipPainter(this.v);
  static const _m = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  void paint(Canvas cv, Size size) {
    final cell = size.width / 4;
    final paint = Paint()..color = v == 1 ? Colors.red.shade700 : Colors.black87;
    for (final k in _m[v]!) {
      final r = k ~/ 3, c = k % 3;
      cv.drawCircle(Offset(cell * (c + 1), cell * (r + 1)), cell * .3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PipPainter old) => old.v != v;
}

class _Tok {
  final int c;
  final Offset p;
  final double lift;
  final bool pick;
  final bool shield;
  _Tok(this.c, this.p, this.lift, this.pick, this.shield);
}

class BoardPainter extends CustomPainter {
  final Game g;
  final int me;
  final bool pickable;
  final List<List<int>>? from;
  final AnimationController moveCtl;
  final AnimationController pulse;

  BoardPainter({
    required this.g,
    required this.me,
    required this.pickable,
    required this.from,
    required this.moveCtl,
    required this.pulse,
  }) : super(repaint: Listenable.merge([moveCtl, pulse]));

  double _disp(int c, int i) {
    final to = g.pos[c][i];
    if (from == null) return to.toDouble();
    final fr = from![c][i];
    final t = Curves.easeInOut.transform(moveCtl.value);
    if (to == -1 && fr >= 0) return t < 1 ? fr.toDouble() : -1.0;
    return fr + (to - fr) * t;
  }

  void _star(Canvas cv, Offset c, double r, Paint paint) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final rad = k.isEven ? r : r * .45;
      final a = -pi / 2 + k * pi / 5;
      final pt = Offset(c.dx + rad * cos(a), c.dy + rad * sin(a));
      if (k == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    cv.drawPath(path, paint);
  }

  void _arrow(Canvas cv, Offset center, Offset dir, double s, Color col) {
    final perp = Offset(-dir.dy, dir.dx);
    final path = Path()
      ..moveTo(center.dx + dir.dx * .24 * s, center.dy + dir.dy * .24 * s)
      ..lineTo(center.dx - dir.dx * .16 * s + perp.dx * .22 * s,
          center.dy - dir.dy * .16 * s + perp.dy * .22 * s)
      ..lineTo(center.dx - dir.dx * .16 * s - perp.dx * .22 * s,
          center.dy - dir.dy * .16 * s - perp.dy * .22 * s)
      ..close();
    cv.drawPath(path, Paint()..color = col);
  }

  void _pawn(Canvas cv, Offset p, double s, Color col, double lift, bool pick) {
    final r = s * .36;
    cv.drawOval(
        Rect.fromCenter(
            center: p + Offset(0, r * .7), width: r * 1.5, height: r * .55),
        Paint()..color = const Color(0x55000000));
    var bob = 0.0;
    if (pick) {
      final w = sin(pulse.value * 2 * pi);
      bob = w.abs() * s * .14;
      cv.drawCircle(
          p + Offset(0, r * .6),
          r * (1.0 + .12 * w),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white
            ..strokeWidth = 2.5);
    }
    final c = p - Offset(0, lift * s + bob);
    cv.drawOval(
        Rect.fromCenter(
            center: c + Offset(0, r * .55), width: r * 1.5, height: r * .7),
        Paint()..color = Color.lerp(col, Colors.black, .35)!);
    final head = c - Offset(0, r * .1);
    final shader = RadialGradient(
      center: const Alignment(-.35, -.45),
      radius: .95,
      colors: [
        Color.lerp(col, Colors.white, .65)!,
        col,
        Color.lerp(col, Colors.black, .35)!,
      ],
      stops: const [0, .5, 1],
    ).createShader(Rect.fromCircle(center: head, radius: r));
    cv.drawCircle(head, r, Paint()..shader = shader);
    cv.drawCircle(
        head,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeWidth = 2);
    cv.drawCircle(
        head,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x66000000)
          ..strokeWidth = .8);
  }

  @override
  void paint(Canvas cv, Size size) {
    final s = size.width / 15;
    final fill = Paint();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x33000000)
      ..strokeWidth = 1;

    fill.color = Colors.white;
    cv.drawRect(Offset.zero & size, fill);

    // Bases
    for (var c = 0; c < 4; c++) {
      final o = kOrigin[c];
      final col = kColors[c];
      final rect = Rect.fromLTWH(o.dx * s, o.dy * s, 6 * s, 6 * s);
      fill.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(col, Colors.white, .25)!, col],
      ).createShader(rect);
      cv.drawRect(rect, fill);
      fill.shader = null;
      fill.color = const Color(0xFFF7F7F7);
      cv.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH((o.dx + .9) * s, (o.dy + .9) * s, 4.2 * s, 4.2 * s),
            Radius.circular(s * .5)),
        fill,
      );
      for (final sp in kBaseSpots) {
        final ctr = (o + sp) * s;
        fill.color = Color.lerp(col, Colors.white, .55)!;
        cv.drawCircle(ctr, s * .55, fill);
        cv.drawCircle(
            ctr,
            s * .55,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = col
              ..strokeWidth = s * .08);
      }
    }

    // Main track
    final starPaint = Paint()..color = const Color(0xFF9E9E9E);
    for (var k = 0; k < 52; k++) {
      final c = kTrack[k];
      final si = kStart.indexOf(k);
      fill.color = si >= 0 ? kColors[si] : Colors.white;
      final r = Rect.fromLTWH(c.dx * s, c.dy * s, s, s);
      cv.drawRect(r, fill);
      cv.drawRect(r, line);
      if (si < 0 && kSafe.contains(k)) {
        _star(cv, (c + const Offset(.5, .5)) * s, s * .34, starPaint);
      } else if (si >= 0) {
        _star(cv, (c + const Offset(.5, .5)) * s, s * .3,
            Paint()..color = Colors.white70);
      }
    }

    // Home columns
    for (var c = 0; c < 4; c++) {
      for (final h in kHome[c]) {
        final r = Rect.fromLTWH(h.dx * s, h.dy * s, s, s);
        fill.color = kColors[c];
        cv.drawRect(r, fill);
        cv.drawRect(r, line);
      }
    }

    // Entry arrows
    _arrow(cv, const Offset(.5, 7.5) * s, const Offset(1, 0), s, kColors[0]);
    _arrow(cv, const Offset(7.5, .5) * s, const Offset(0, 1), s, kColors[1]);
    _arrow(cv, const Offset(14.5, 7.5) * s, const Offset(-1, 0), s, kColors[2]);
    _arrow(cv, const Offset(7.5, 14.5) * s, const Offset(0, -1), s, kColors[3]);

    // Centre triangles
    const tri = [
      [Offset(6, 6), Offset(6, 9), Offset(7.5, 7.5)],
      [Offset(6, 6), Offset(9, 6), Offset(7.5, 7.5)],
      [Offset(9, 6), Offset(9, 9), Offset(7.5, 7.5)],
      [Offset(6, 9), Offset(9, 9), Offset(7.5, 7.5)],
    ];
    for (var c = 0; c < 4; c++) {
      final path = Path()
        ..moveTo(tri[c][0].dx * s, tri[c][0].dy * s)
        ..lineTo(tri[c][1].dx * s, tri[c][1].dy * s)
        ..lineTo(tri[c][2].dx * s, tri[c][2].dy * s)
        ..close();
      fill.color = kColors[c];
      cv.drawPath(path, fill);
      cv.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white
            ..strokeWidth = 1.5);
    }

    // Tokens (drawn back-to-front so lower ones overlap upper ones)
    final mov = pickable ? g.movable(me).toSet() : <int>{};
    final items = <_Tok>[];
    for (var c = 0; c < 4; c++) {
      if (!g.active[c]) continue;
      for (var i = 0; i < 4; i++) {
        final d = _disp(c, i);
        final moving = from != null && from![c][i] != g.pos[c][i];
        final off = from == null ? stackOff(g, c, i) : Offset.zero;
        final p = tokenAt(c, i, d, off: off);
        var lift = 0.0;
        if (moving && d >= -1 && g.pos[c][i] != -1) {
          lift = sin(pi * (d - d.floor())) * .35;
        }
        final sh = g.shield[c] && g.pos[c][i] >= 0 && g.pos[c][i] <= 50;
        items.add(_Tok(c, p * s, lift, c == g.ctl(me) && mov.contains(i), sh));
      }
    }
    items.sort((a, b) => a.p.dy.compareTo(b.p.dy));
    for (final t in items) {
      if (t.shield) {
        cv.drawCircle(t.p, s * .62, Paint()..color = const Color(0x3300E5FF));
        cv.drawCircle(
            t.p,
            s * .62,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = Colors.cyanAccent
              ..strokeWidth = 2);
      }
      _pawn(cv, t.p, s, kColors[t.c], t.lift, t.pick);
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}
