// Version 15.1.8e
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _is24HourFormat = true;
  bool _isVoiceControlEnabled = true;
  bool _isAlexaEnabled = false;

  String _triggerName = "SmartWake";

  TimeOfDay? _wakeTime;
  bool _wakeTimeSet = false;
  String _formattedTime = '';

  String _selectedStream = 'Radio Berg';

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();

  Timer? _clockTimer;

  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _triggerNameController = TextEditingController();

  final GlobalKey _menuKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  bool _isWakingUp = false;
  bool _blink = false;
  Timer? _blinkTimer;

  // NEU: letzte Alarmzeit merken, um Neustart in gleicher Minute zu verhindern
  DateTime? _lastWakeTrigger;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _updateLiveTime();
    _startWakeChecker();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _is24HourFormat = prefs.getBool('is24HourFormat') ?? true;
      _isVoiceControlEnabled = prefs.getBool('isVoiceControlEnabled') ?? true;
      _isAlexaEnabled = prefs.getBool('isAlexaEnabled') ?? false;
      _selectedStream = prefs.getString('selectedStream') ?? 'Radio Berg';
      _triggerName = prefs.getString('triggerName') ?? 'SmartWake';
      _triggerNameController.text = _triggerName;
    });
  }

  void _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('is24HourFormat', _is24HourFormat);
    prefs.setBool('isVoiceControlEnabled', _isVoiceControlEnabled);
    prefs.setBool('isAlexaEnabled', _isAlexaEnabled);
    prefs.setString('selectedStream', _selectedStream);
    prefs.setString('triggerName', _triggerName);
  }

  void _updateLiveTime() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final formatted = DateFormat(_is24HourFormat ? 'HH:mm' : 'hh:mm a').format(now);
      setState(() {
        _formattedTime = formatted;
      });
    });
  }

  void _startWakeChecker() {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_wakeTime == null || _isWakingUp) return;

      final now = TimeOfDay.now();
      final currentTime = DateTime.now();

      if (now.hour == _wakeTime!.hour && now.minute == _wakeTime!.minute) {
        if (_lastWakeTrigger == null ||
            currentTime.difference(_lastWakeTrigger!).inMinutes >= 1) {
          _lastWakeTrigger = currentTime;
          _startWeckton();
        }
      }
    });
  }

  void _startWeckton() async {
    setState(() => _isWakingUp = true);
    String? streamUrl;

    if (_selectedStream == 'Radio Berg') {
      streamUrl = 'https://stream.lokalradio.nrw/446kbhp';
    } else if (_selectedStream == 'Absolut Relax') {
      streamUrl = 'https://absolut-relax.live-sm.absolutradio.de/absolut-relax/stream/mp3';
    }

    if (_selectedStream == 'Weckton') {
      await _audioPlayer.setSource(AssetSource('sounds/smarter_wecker.mp3'));
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.resume();
    } else {
      if (streamUrl != null) {
        await _audioPlayer.play(UrlSource(streamUrl));
      }
    }

    _startBlinking();
  }

  void _stopWeckton() {
    _audioPlayer.stop();
    _stopBlinking();
    _clearWakeTime(); // NEU: Weckzeit löschen bei Stop
    setState(() => _isWakingUp = false);
  }

  void _startBlinking() {
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() => _blink = !_blink);
    });
  }

  void _stopBlinking() {
    _blinkTimer?.cancel();
    setState(() => _blink = false);
  }

  void _pickWakeTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: _is24HourFormat),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      setState(() {
        _wakeTime = pickedTime;
        _wakeTimeSet = true;
        _timeController.text = _is24HourFormat
            ? '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}'
            : pickedTime.format(context);
      });
    }
  }

  void _clearWakeTime() {
    setState(() {
      _wakeTime = null;
      _wakeTimeSet = false;
      _timeController.clear();
    });
  }

  void _testWeckton() async {
    String? streamUrl;

    if (_selectedStream == 'Radio Berg') {
      streamUrl = 'https://stream.lokalradio.nrw/446kbhp';
    } else if (_selectedStream == 'Absolut Relax') {
      streamUrl = 'https://absolut-relax.live-sm.absolutradio.de/absolut-relax/stream/mp3';
    }

    if (_selectedStream == 'Weckton') {
      await _audioPlayer.setSource(AssetSource('sounds/smarter_wecker.mp3'));
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.resume();
    } else {
      if (streamUrl != null) {
        await _audioPlayer.play(UrlSource(streamUrl));
      }
    }

    Future.delayed(const Duration(seconds: 15), () => _audioPlayer.stop());
  }

  void _toggleCustomPopup() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    } else {
      final RenderBox renderBox = _menuKey.currentContext!.findRenderObject() as RenderBox;
      final Offset offset = renderBox.localToGlobal(Offset.zero);

      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          top: offset.dy + renderBox.size.height + 5,
          left: offset.dx - 110,
          width: 180,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF772625),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _openSettingsMenu() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF772625),
            title: const Text('Einstellungen', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSwitchRow('24-Stunden-Format', _is24HourFormat, (value) {
                  setState(() => _is24HourFormat = value);
                  setStateDialog(() {});
                  _savePreferences();
                }),
                _buildDropdownRow('Weckton', _selectedStream,
                    ['Radio Berg', 'Absolut Relax', 'Weckton'], (value) {
                  setState(() => _selectedStream = value!);
                  setStateDialog(() {});
                  _savePreferences();
                }),
                ElevatedButton(
                  onPressed: _testWeckton,
                  child: const Text('Test'),
                ),
                _buildSwitchRow('Sprachanwahl', _isVoiceControlEnabled, (value) {
                  setState(() => _isVoiceControlEnabled = value);
                  setStateDialog(() {});
                  _savePreferences();
                }),
                if (_isVoiceControlEnabled)
                  TextField(
                    controller: _triggerNameController,
                    onChanged: (value) {
                      _triggerName = value;
                      _savePreferences();
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Triggername',
                      labelStyle: TextStyle(color: Colors.white),
                    ),
                  ),
                _buildSwitchRow('Alexa-Anbindung', _isAlexaEnabled, (value) {
                  setState(() => _isAlexaEnabled = value);
                  setStateDialog(() {});
                  _savePreferences();
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Schließen', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  void _openAboutPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF772625),
          title: const Text('Über SmartWake+', style: TextStyle(color: Colors.white)),
          content: const Text(
            'SmartWake+ ist dein persönlicher Wecker mit Radiostream, Sprachsteuerung und Alexa-Anbindung.\n\nVersion 15.1.8e',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdownRow(String label, String currentValue,
      List<String> options, Function(String?) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white)),
        DropdownButton<String>(
          value: currentValue,
          dropdownColor: const Color(0xFF772625),
          items: options.map((option) {
            return DropdownMenuItem<String>(
              value: option,
              child: Text(option, style: const TextStyle(color: Colors.white)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSwitchRow(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _blinkTimer?.cancel();
    super.dispose();
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
          Image.asset('assets/images/background.jpg', fit: BoxFit.cover),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Image.asset('assets/images/logo.png', height: 88, width: 88),
                      const SizedBox(width: 10),
                      const Text('SmartWake+', style: TextStyle(fontSize: 28, color: Colors.white)),
                      const Spacer(),
                      GestureDetector(
                        key: _menuKey,
                        onTap: _toggleCustomPopup,
                        child: const Icon(Icons.menu, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),
                  Text(_formattedTime,
                      style: const TextStyle(fontSize: 65, color: Colors.white)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _timeController,
                          readOnly: true,
                          onTap: _pickWakeTime,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.6),
                            hintText: 'HH:MM',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_wakeTimeSet)
                        IconButton(
                          icon: const Icon(Icons.notifications_off, color: Colors.white),
                          onPressed: _clearWakeTime,
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (_isVoiceControlEnabled)
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () {},
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFAF3A36),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.mic, color: Colors.white, size: 32),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFAF3A36),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Sag: „$_triggerName, stell den Wecker für …“',
                            style: const TextStyle(color: Colors.white),
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
                        padding: const EdgeInsets.all(24),
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
                        child: const Icon(Icons.notifications_off,
                            color: Colors.white, size: 48),
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
}
