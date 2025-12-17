import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider localFileImage(String path) => FileImage(File(path));

