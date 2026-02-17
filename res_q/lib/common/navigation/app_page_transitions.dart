import 'package:flutter/material.dart';

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();
  static const Duration _transitionDuration = Duration(milliseconds: 220);

  static final Animatable<Offset> _offsetTween = Tween<Offset>(
    begin: const Offset(0.03, 0),
    end: Offset.zero,
  );

  @override
  Duration get transitionDuration => _transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curvedAnimation,
      child: SlideTransition(
        position: curvedAnimation.drive(_offsetTween),
        child: child,
      ),
    );
  }
}
