import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const size = 1024;
  final icon = img.Image(width: size, height: size);

  final bg = img.ColorRgb8(27, 31, 59);
  img.fill(icon, color: bg);

  final accent = img.ColorRgb8(126, 154, 255);
  final white = img.ColorRgb8(245, 248, 255);

  for (var y = 0; y < size; y++) {
    final t = y / size;
    final r = (27 + (46 - 27) * t).round();
    final g = (31 + (39 - 31) * t).round();
    final b = (59 + (82 - 59) * t).round();
    final lineColor = img.ColorRgb8(r, g, b);
    for (var x = 0; x < size; x++) {
      icon.setPixel(x, y, lineColor);
    }
  }

  final noteHeadCenterX = (size * 0.42).round();
  final noteHeadCenterY = (size * 0.63).round();
  final noteHeadRadius = (size * 0.11).round();
  img.fillCircle(
    icon,
    x: noteHeadCenterX,
    y: noteHeadCenterY,
    radius: noteHeadRadius,
    color: white,
  );

  final stemLeft = (size * 0.48).round();
  final stemTop = (size * 0.18).round();
  final stemRight = (size * 0.58).round();
  final stemBottom = (size * 0.62).round();
  img.fillRect(
    icon,
    x1: stemLeft,
    y1: stemTop,
    x2: stemRight,
    y2: stemBottom,
    color: white,
  );

  final flagTop = (size * 0.17).round();
  final flagBottom = (size * 0.29).round();
  final flagLeft = stemRight;
  final flagRight = (size * 0.83).round();

  for (var y = flagTop; y <= flagBottom; y++) {
    final t = (y - flagTop) / (flagBottom - flagTop);
    final curve = (1 - (t - 0.5).abs() * 2) * 0.12;
    final xStart = (flagLeft - size * 0.02).round();
    final xEnd = (flagRight - size * curve).round();
    img.drawLine(
      icon,
      x1: xStart,
      y1: y,
      x2: xEnd,
      y2: y,
      color: white,
      thickness: 3,
    );
  }

  final searchCenterX = (size * 0.69).round();
  final searchCenterY = (size * 0.70).round();
  final searchRadius = (size * 0.15).round();

  img.fillCircle(
    icon,
    x: searchCenterX,
    y: searchCenterY,
    radius: searchRadius,
    color: accent,
  );
  img.fillCircle(
    icon,
    x: searchCenterX,
    y: searchCenterY,
    radius: (searchRadius * 0.62).round(),
    color: bg,
  );

  final handleStartX = (searchCenterX + searchRadius * 0.62).round();
  final handleStartY = (searchCenterY + searchRadius * 0.62).round();
  final handleEndX = (size * 0.90).round();
  final handleEndY = (size * 0.90).round();

  img.drawLine(
    icon,
    x1: handleStartX,
    y1: handleStartY,
    x2: handleEndX,
    y2: handleEndY,
    color: accent,
    thickness: (size * 0.045).round(),
  );

  final outDir = Directory('assets/app_icon')..createSync(recursive: true);
  final outFile = File('${outDir.path}/singsync.png');
  outFile.writeAsBytesSync(img.encodePng(icon));
  stdout.writeln('Icon generated at: ${outFile.path}');
}
