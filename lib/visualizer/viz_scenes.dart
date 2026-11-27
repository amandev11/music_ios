import 'package:flutter/material.dart';

/// One visualizer scene: a fragment shader plus how it is listed in the picker.
class VizScene {
  const VizScene(
    this.id,
    this.name,
    this.asset,
    this.icon, {
    this.extended = true,
  });
  final String id;
  final String name;
  final String asset;
  final IconData icon;

  /// Whether the shader takes the extra uniforms (intensity, speed, beat and 16 bands). The original
  /// plasma scene only has the first 15.
  final bool extended;
}

const vizScenes = <VizScene>[
  VizScene(
    'plasma',
    'Plasma',
    'shaders/velour_voxel_engine.frag',
    Icons.blur_on_rounded,
    extended: false,
  ),
  VizScene(
    'voxel',
    'Voxel Wall',
    'shaders/voxel_wall.frag',
    Icons.grid_view_rounded,
  ),
  VizScene(
    'tunnel',
    'Tunnel',
    'shaders/tunnel.frag',
    Icons.trip_origin_rounded,
  ),
  VizScene('aurora', 'Aurora', 'shaders/aurora.frag', Icons.waves_rounded),
  VizScene(
    'terrain',
    'Outrun',
    'shaders/terrain.frag',
    Icons.landscape_rounded,
  ),
];

VizScene vizSceneById(String id) =>
    vizScenes.firstWhere((s) => s.id == id, orElse: () => vizScenes.first);

/// Presets set the response intensity and motion speed together; Energy Saver also halves the frame rate.
class VizPreset {
  const VizPreset(this.id, this.name, this.intensity, this.speed);
  final String id;
  final String name;
  final double intensity;
  final double speed;
}

const vizPresets = <VizPreset>[
  VizPreset('subtle', 'Subtle', 0.6, 0.7),
  VizPreset('balanced', 'Balanced', 1.0, 1.0),
  VizPreset('intense', 'Intense', 1.5, 1.3),
  VizPreset('saver', 'Energy Saver', 0.8, 0.8),
];
