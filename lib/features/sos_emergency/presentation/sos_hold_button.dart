import 'package:flutter/material.dart';

/// Tombol SOS: tahan 3 detik untuk memicu (mencegah terkirim tidak sengaja).
class SosHoldButton extends StatefulWidget {
  const SosHoldButton({super.key, required this.onTriggered, this.size = 64});
  final VoidCallback onTriggered;
  final double size;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onTriggered();
        _c.reset();
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _release() {
    if (_c.status != AnimationStatus.completed) _c.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tombol SOS, tahan 3 detik untuk mengirim peringatan darurat',
      child: Listener(
        onPointerDown: (_) => _c.forward(),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(fit: StackFit.expand, children: [
              Container(
                margin: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('SOS',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: widget.size * 0.28)),
              ),
              CircularProgressIndicator(
                value: _c.value,
                strokeWidth: 5,
                color: Colors.white,
                backgroundColor: Colors.transparent,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
