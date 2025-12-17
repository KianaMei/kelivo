import 'package:flutter/material.dart';

/// Web: check if path is a valid URL or data URL (local files not supported)
bool fileExists(String path) {
  if (path.isEmpty) return false;
  // On web, http/https URLs and data URLs are valid image sources
  return path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('data:');
}

/// Web: create NetworkImage for URLs, placeholder for others
ImageProvider createFileImage(String path) {
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('data:')) {
    return NetworkImage(path);
  }
  return const AssetImage('assets/icons/kelivo.png');
}
