// Version 16.2.0 – SmartWake+ mit verbesserter Sprachsteuerung und Alexa-Reminder

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const SmartWakeApp());
}

class SmartWakeApp extends StatelessWidget {
  const SmartWakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartWake+',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const WakeHomePage(),
    );
  }
}

class WakeHomePage extends StatefulWidget {
  const WakeHomePage({super.key});

  @override
  State<WakeHomePage> createState() => _WakeHomePageState();
}

class _WakeHomePageState extends State<WakeHomePage> {
  // Einstellungen
  bool _is24HourFormat = true;
  bool _isVoiceControlEnabled = true;
  bool _isAlexaEnabled = false;
  String _triggerName = "SmartWake";

  // Weckzeit
  TimeOfDay? _wakeTime;
  bool _wakeTimeSet = false;
  String _formattedTime = '';
  DateTime? _lastWakeTrigger;

  // Radiostream-Auswahl
  String _selectedStream = 'Radio Berg';

  // Audio-Player & TTS
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();

  // Spracheingabe
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _recognizedText = '';

  // Alexa-Anbindung
  String? _alexaAccessToken;

  // Text-Controller
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _triggerNameController = TextEditingController();

  // Menü-Overlay
  final GlobalKey _menuKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  // Alarmstatus & Blinken
  bool _isWakingUp = false;
  bool _blink = false;
  Timer? _blinkTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _updateLiveTime();
    _startWakeChecker();
  }

  // Präferenzen laden
  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _is24HourFormat = prefs.getBool('is24HourFormat') ?? true;
      _isVoiceControlEnabled =
          prefs.getBool('isVoiceControlEnabled') ?? true;
      _isAlexaEnabled = prefs.getBool('isAlexaEnabled') ?? false;
      _selectedStream = prefs.getString('selectedStream') ?? 'Radio Berg';
      _triggerName = prefs.getString('triggerName') ?? 'SmartWake';
      _triggerNameController.text = _triggerName;
    });
  }

  // Präferenzen speichern
  void _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('is24HourFormat', _is24HourFormat);
    prefs.setBool('isVoiceControlEnabled', _isVoiceControlEnabled);
    prefs.setBool('isAlexaEnabled', _isAlexaEnabled);
    prefs.setString('selectedStream', _selectedStream);
    prefs.setString('triggerName', _triggerName);
  }

  // Live-Uhrzeit aktualisieren
  void _updateLiveTime() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final formatted = DateFormat(
        _is24HourFormat ? 'HH:mm' : 'hh:mm a',
      ).format(now);
      setState(() => _formattedTime = formatted);
    });
  }

  // Weckzeit-Checker alle 5 s
  void _startWakeChecker() {
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (_wakeTime == null || _isWakingUp) return;
      final now = TimeOfDay.now();
      final current = DateTime.now();
      if (now.hour == _wakeTime!.hour &&
          now.minute == _wakeTime!.minute) {
        if (_lastWakeTrigger == null ||
            current.difference(_lastWakeTrigger!).inMinutes >= 1) {
          _lastWakeTrigger = current;
          _startWeckton();
        }
      }
    });
  }

  // Weckton starten
  void _startWeckton() async {
    setState(() => _isWakingUp = true);
    String? url;
    if (_selectedStream == 'Radio Berg') {
      url = 'https://stream.lokalradio.nrw/446kbhp';
    } else if (_selectedStream == 'Absolut Relax') {
      url =
          'https://absolut-relax.live-sm.absolutradio.de/absolut-relax/stream/mp3';
    }
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    if (_selectedStream == 'Weckton') {
      await _audioPlayer.play(AssetSource('sounds/smarter_wecker.mp3'));
    } else if (url != null) {
      await _audioPlayer.play(UrlSource(url));
    }
    _startBlinking();
  }

  // Weckton stoppen
  void _stopWeckton() {
    _audioPlayer.stop();
    _stopBlinking();
    _clearWakeTime();
    setState(() => _isWakingUp = false);
  }

  // Blinken starten/stoppen
  void _startBlinking() {
    _blinkTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _blink = !_blink);
    });
  }

  void _stopBlinking() {
    _blinkTimer?.cancel();
    setState(() => _blink = false);
  }

  // Weckzeit auswählen
  void _pickWakeTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(alwaysUse24HourFormat: _is24HourFormat),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _wakeTime = picked;
        _wakeTimeSet = true;
        _timeController.text = _is24HourFormat
            ? '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'
            : picked.format(context);
      });
      if (_isAlexaEnabled && _alexaAccessToken != null) {
        await _scheduleAlexaReminder();
      }
    }
  }

  // Weckzeit löschen
  void _clearWakeTime() {
    setState(() {
      _wakeTime = null;
      _wakeTimeSet = false;
      _timeController.clear();
    });
  }

  // Weckton testen
  void _testWeckton() async {
    String? url;
    if (_selectedStream == 'Radio Berg') {
      url = 'https://stream.lokalradio.nrw/446kbhp';
    } else if (_selectedStream == 'Absolut Relax') {
      url =
          'https://absolut-relax.live-sm.absolutradio.de/absolut-relax/stream/mp3';
    }
    if (_selectedStream == 'Weckton') {
      await _audioPlayer.play(AssetSource('sounds/smarter_wecker.mp3'));
    } else if (url != null) {
      await _audioPlayer.play(UrlSource(url));
    }
    Future.delayed(const Duration(seconds: 15),
        () => _audioPlayer.stop());
  }

  // Overlay-Menü umschalten
  void _toggleCustomPopup() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    } else {
      final box = _menuKey.currentContext!
          .findRenderObject() as RenderBox;
      final offset = box.localToGlobal(Offset.zero);
      _overlayEntry = OverlayEntry(
        builder: (_) => Positioned(
          top: offset.dy + box.size.height + 5,
          left: offset.dx - 110,
          width: 180,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF772625),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    onPressed: () {
                      _overlayEntry!.remove();
                      _overlayEntry = null;
                      _openSettingsMenu();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text('Einstellungen'),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () {
                      _overlayEntry!.remove();
                      _overlayEntry = null;
                      _openAboutPopup();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text('Über SmartWake+'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Overlay.of(context)!.insert(_overlayEntry!);
    }
  }

  // Einstellungen-Dialog
  void _openSettingsMenu() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF772625),
            title: const Text('Einstellungen',
                style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSwitchRow(
                      '24-Stunden-Format', _is24HourFormat, (v) {
                    setState(() => _is24HourFormat = v);
                    setStateDialog(() {});
                    _savePreferences();
                  }),
                  _buildDropdownRow(
                    'Weckton',
                    _selectedStream,
                    ['Radio Berg', 'Absolut Relax', 'Weckton'],
                    (v) {
                      setState(() => _selectedStream = v!);
                      setStateDialog(() {});
                      _savePreferences();
                    },
                  ),
                  ElevatedButton(
                      onPressed: _testWeckton, child: const Text('Test')),
                  _buildSwitchRow('Sprachsteuerung',
                      _isVoiceControlEnabled, (v) {
                    setState(() => _isVoiceControlEnabled = v);
                    setStateDialog(() {});
                    _savePreferences();
                  }),
                  if (_isVoiceControlEnabled)
                    TextField(
                      controller: _triggerNameController,
                      onChanged: (v) {
                        setState(() => _triggerName = v);
                        _savePreferences();
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Triggername',
                        labelStyle: TextStyle(color: Colors.white),
                      ),
                    ),
                  _buildSwitchRow(
                      'Alexa-Anbindung', _isAlexaEnabled, (v) {
                    setState(() => _isAlexaEnabled = v);
                    setStateDialog(() {});
                    _savePreferences();
                  }),
                  if (_isAlexaEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: ElevatedButton(
                        onPressed: _loginWithAmazon,
                        child: Text(
                          _alexaAccessToken == null
                              ? 'Alexa verbinden'
                              : 'Alexa verbunden',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Schließen',
                      style: TextStyle(color: Colors.white))),
            ],
          );
        },
      ),
    );
  }

  // Über-Dialog
  void _openAboutPopup() {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF772625),
      title: const Text(
        'Über SmartWake+',
        style: TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'SmartWake+ ist dein persönlicher Wecker-Begleiter im eleganten Dark-Theme:',
              style: TextStyle(color: Colors.white),
            ),
            SizedBox(height: 8),
            Text(
              '• Wecke dich mit deinen liebsten Radiostreams (z. B. Radio Berg oder Absolut Relax) oder einem eigenen MP3-Weckton.',
              style: TextStyle(color: Colors.white),
            ),
            Text(
              '• Stelle deine Weckzeit per Touch, Sprachbefehl („SmartWake, stell den Wecker für …“) oder direkt über die Alexa-Anbindung ein.',
              style: TextStyle(color: Colors.white),
            ),
            Text(
              '• Im 24-Stunden-Format immer im Blick: Die Uhrzeit wird live aktualisiert, der Alarmton läuft in endloser Dauerschleife und das Display blinkt, bis du ihn stoppst.',
              style: TextStyle(color: Colors.white),
            ),
            Text(
              '• Dank integrierter Alexa-Integration planst du deine Alarme sogar von unterwegs – perfekt vernetzt, damit du garantiert nicht verschläfst.',
              style: TextStyle(color: Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Version 16.1.0',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            Text(
              '© 2025 SmartWake+',
              style: TextStyle(color: Colors.white),
            ),
            SizedBox(height: 8),
            Text(
              'https://smartwakeplus.de',
              style: TextStyle(
                  color: Colors.blueAccent,
                  decoration: TextDecoration.underline),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Schließen',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}


  // Hilfs-Widgets
  Widget _buildDropdownRow(String label, String currentValue,
          List<String> options, Function(String?) onChanged) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white)),
          DropdownButton<String>(
            value: currentValue,
            dropdownColor: const Color(0xFF772625),
            items: options
                .map((opt) => DropdownMenuItem<String>(
                      value: opt,
                      child:
                          Text(opt, style: const TextStyle(color: Colors.white)),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      );

  Widget _buildSwitchRow(
          String label, bool value, Function(bool) onChanged) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white)),
          Switch(value: value, onChanged: onChanged, activeColor: Colors.white),
        ],
      );

  // Login with Amazon
  Future<void> _loginWithAmazon() async {
    final clientId = '<YOUR_CLIENT_ID>';
    final redirectUri = 'com.yourapp://oauth';
    final url = Uri.https('www.amazon.com', '/ap/oa', {
      'client_id': clientId,
      'scope': 'alexa::alerts:reminders:skill:readwrite',
      'response_type': 'code',
      'redirect_uri': redirectUri,
    });
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: Uri.parse(redirectUri).scheme,
      );
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) throw 'Kein Code erhalten';
      final tokenResp = await http.post(
        Uri.parse('https://api.amazon.com/auth/o2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'client_id': clientId,
          'client_secret': '<YOUR_CLIENT_SECRET>',
          'redirect_uri': redirectUri,
        },
      );
      final data = jsonDecode(tokenResp.body);
      setState(() => _alexaAccessToken = data['access_token']);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alexa verbunden!')),
      );
    } catch (e) {
      debugPrint('Login Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login fehlgeschlagen: $e')),
      );
    }
  }

  // Alexa Reminder anlegen
  Future<void> _scheduleAlexaReminder() async {
    if (_wakeTime == null || _alexaAccessToken == null) return;
    final now = DateTime.now();
    var sched = DateTime(now.year, now.month, now.day,
        _wakeTime!.hour, _wakeTime!.minute);
    if (sched.isBefore(now)) sched = sched.add(const Duration(days: 1));
    final payload = {
      'requestTime': now.toIso8601String(),
      'trigger': {
        'type': 'SCHEDULED_ABSOLUTE',
        'scheduledTime': sched.toIso8601String(),
        'timeZoneId': 'Europe/Berlin'
      },
      'alertInfo': {
        'spokenInfo': {
          'content': [
            {
              'locale': 'de-DE',
              'ssml': '<speak><amazon:volume level="70%">'
                  '<audio src="https://dein-backend.de/wake.mp3"/>'
                  '</amazon:volume></speak>'
            }
          ]
        }
      },
      'pushNotification': {'status': 'ENABLED'}
    };
    try {
      final res = await http.post(
        Uri.parse(
            'https://api.eu.amazonalexa.com/v1/alerts/reminders'),
        headers: {
          'Authorization': 'Bearer $_alexaAccessToken',
          'Content-Type': 'application/json'
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alexa-Wecker geplant!')),
        );
      } else {
        throw 'Status ${res.statusCode}';
      }
    } catch (e) {
      debugPrint('Alexa Reminder Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alexa-Wecker fehlgeschlagen: $e')),
      );
    }
  }

  // Spracheingabe starten
  void _startListening() async {
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon-Zugriff erforderlich')),
        );
        return;
      }
    }
    bool available = await _speech.initialize(
      onStatus: (s) {
        debugPrint('🎙 Status: $s');
        if (s == 'done' || s == 'notListening')
          setState(() => _isListening = false);
      },
      onError: (e) {
        debugPrint('❌ Sprachfehler: $e');
        setState(() => _isListening = false);
      },
    );
    if (available) {
      setState(() {
        _recognizedText = '';
        _isListening = true;
      });
      _speech.listen(
        localeId: 'de_DE',
        listenFor: const Duration(seconds: 20),
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          debugPrint('🗣 Erkannt: ${result.recognizedWords}');
          setState(() => _recognizedText = result.recognizedWords);
          if (result.finalResult) {
            _speech.stop();
            _processSpokenText(_recognizedText);
            setState(() => _isListening = false);
          }
        },
      );
    } else {
      debugPrint('⚠️ Spracherkennung nicht verfügbar');
    }
  }

  // Verbesserte Sprachverarbeitung
  void _processSpokenText(String text) {
    final lower = text.toLowerCase();
    if (!lower.contains(_triggerName.toLowerCase())) return;
    if (!(lower.contains('wecker') ||
        lower.contains('wecke mich') ||
        lower.contains('stell den wecker'))) {
      return;
    }
    final regex = RegExp(r'(\d{1,2})(?:(?:[:\.])(\d{1,2}))?\s*(?:uhr)?');
    final match = regex.firstMatch(lower);
    if (match == null) return;
    final hour = int.parse(match.group(1)!);
    final minute =
        match.group(2) != null ? int.parse(match.group(2)!) : 0;
    if (!_is24HourFormat && hour > 12) return;
    final picked = TimeOfDay(hour: hour, minute: minute);
    setState(() {
      _wakeTime = picked;
      _wakeTimeSet = true;
      _timeController.text = picked.format(context);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Weckzeit gesetzt auf ${picked.format(context)}')),
    );
    if (_isAlexaEnabled && _alexaAccessToken != null) {
      _scheduleAlexaReminder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedWakeTime = _wakeTime != null
        ? (_is24HourFormat
            ? '${_wakeTime!.hour.toString().padLeft(2, '0')}:${_wakeTime!.minute.toString().padLeft(2, '0')}'
            : _wakeTime!.format(context))
        : '';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/background.jpg',
              fit: BoxFit.cover),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Image.asset('assets/images/logo.png',
                          height: 88, width: 88),
                      const SizedBox(width: 10),
                      const Text('SmartWake+',
                          style: TextStyle(
                              fontSize: 28,
                              color: Colors.white)),
                      const Spacer(),
                      GestureDetector(
                        key: _menuKey,
                        onTap: _toggleCustomPopup,
                        child:
                            const Icon(Icons.menu, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),
                  Text(_formattedTime,
                      style: const TextStyle(
                          fontSize: 65,
                          color: Colors.white)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _timeController,
                          readOnly: true,
                          onTap: _pickWakeTime,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.black),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white
                                .withOpacity(0.6),
                            hintText: 'HH:MM',
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_wakeTimeSet)
                        IconButton(
                          icon: const Icon(
                              Icons.notifications_off,
                              color: Colors.white),
                          onPressed: _clearWakeTime,
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (_isVoiceControlEnabled)
                    Column(
                      children: [
                        GestureDetector(
                          onTap: _startListening,
                          child: Container(
                            padding:
                                const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  const Color(0xFFAF3A36),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black
                                        .withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(
                                        0, 6)),
                              ],
                            ),
                            child: const Icon(
                                Icons.mic,
                                color: Colors.white,
                                size: 32),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFAF3A36),
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Sag: „$_triggerName, stell den Wecker für …“',
                            style: const TextStyle(
                                color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_isListening)
                          Container(
                            padding:
                                const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                    BorderRadius.circular(
                                        12)),
                            child: Text(
                              'Ich höre zu: $_recognizedText',
                              style: const TextStyle(
                                  color: Colors.white),
                            ),
                          ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  if (_wakeTimeSet)
                    Text('Weckzeit gesetzt: $formattedWakeTime',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  const SizedBox(height: 20),
                  if (_isWakingUp)
                    GestureDetector(
                      onTap: _stopWeckton,
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                          boxShadow: [
                            if (_blink)
                              const BoxShadow(
                                  color: Colors.white,
                                  blurRadius: 12,
                                  spreadRadius: 4)
                          ],
                        ),
                        child: const Icon(
                            Icons.notifications_off,
                            color: Colors.white,
                            size: 48),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _blinkTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
