import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../engine/eq.dart';
import '../theme/theme.dart';

/// Ten-band equalizer. The curve is applied live: mpv's `equalizer` filter on desktop and iOS, the
/// system Equalizer effect on Android.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  final settings = AppController.I.settings;
  final backend = AppController.I.backend;
  late bool _on = settings.eqEnabled;
  late List<double> _gains = settings.eqGains;
  late String _preset = settings.eqPreset;

  void _apply() {
    settings.eqEnabled = _on;
    settings.eqGains = _gains;
    settings.eqPreset = _preset;
    backend.applyEq(_on, _gains);
  }

  String _label(double hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k' : hz.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final supported = backend.eqSupported;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: context.accent,
        actions: [
          Switch(
            activeColor: context.accent,
            value: _on,
            onChanged: supported
                ? (v) {
                    setState(() => _on = v);
                    _apply();
                  }
                : null,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
        if (!supported)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'The equalizer is not available in browsers: they give apps no access to the audio signal. Use the Android, Windows, macOS, Linux or iOS app.',
              style: TextStyle(color: context.secondaryText),
            ),
          ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final name in eqPresets.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(name),
                    selected: _preset == name,
                    selectedColor: context.accent,
                    labelStyle: TextStyle(color: _preset == name ? context.onAccent : null, fontWeight: FontWeight.w600),
                    showCheckmark: false,
                    onSelected: !supported
                        ? null
                        : (_) {
                            setState(() {
                              _preset = name;
                              _gains = List.of(eqPresets[name]!);
                              _on = true;
                            });
                            _apply();
                          },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Opacity(
          opacity: _on ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < eqFrequencies.length; i++)
                Expanded(
                  child: Column(children: [
                    Text('${_gains[i] > 0 ? '+' : ''}${_gains[i].toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 11, color: context.secondaryText, fontFeatures: const [FontFeature.tabularFigures()])),
                    SizedBox(
                      height: 240,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            activeTrackColor: context.accent,
                            thumbColor: context.accent,
                            inactiveTrackColor: context.separator,
                            overlayShape: SliderComponentShape.noOverlay,
                          ),
                          child: Slider(
                            min: eqMinDb,
                            max: eqMaxDb,
                            value: _gains[i].clamp(eqMinDb, eqMaxDb),
                            onChanged: supported
                                ? (v) {
                                    setState(() {
                                      _gains[i] = double.parse(v.toStringAsFixed(1));
                                      _preset = 'Custom';
                                      _on = true;
                                    });
                                    _apply();
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ),
                    Text(_label(eqFrequencies[i]), style: TextStyle(fontSize: 11, color: context.secondaryText)),
                  ]),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: !supported
                ? null
                : () {
                    setState(() {
                      _gains = List.filled(10, 0.0);
                      _preset = 'Flat';
                    });
                    _apply();
                  },
            icon: Icon(Icons.restart_alt_rounded, color: context.accent),
            label: Text('Reset', style: TextStyle(color: context.accent)),
          ),
        ),
        if (backend.hasBeatEngine)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text('On Android the effect maps this curve onto your device\'s equalizer bands.', style: TextStyle(color: context.secondaryText, fontSize: 12)),
          ),
      ]),
    );
  }
}
