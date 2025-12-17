import 'dart:io' show File;
import 'package:flutter/material.dart';

/// Check if file exists (IO platforms only)
bool fileExists(String path) => File(path).existsSync();

/// Create FileImage widget for local file (IO platforms only)
ImageProvider createFileImage(String path) => FileImage(File(path));
