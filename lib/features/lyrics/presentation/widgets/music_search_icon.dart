import 'package:flutter/material.dart';

class MusicSearchIcon extends StatelessWidget {
  const MusicSearchIcon({
    super.key,
    this.size = 22,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Icon(
              Icons.music_note_rounded,
              size: size,
              color: iconColor,
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Icon(
              Icons.search_rounded,
              size: size * 0.55,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}
