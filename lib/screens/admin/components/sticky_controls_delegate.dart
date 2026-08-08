import 'package:flutter/material.dart';

class StickyControlsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color bgColor;
  final EdgeInsets padding;

  StickyControlsDelegate({
    required this.child,
    required this.height,
    required this.bgColor,
    required this.padding,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: bgColor,
      padding: padding.copyWith(top: 10.0, bottom: 16.0),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant StickyControlsDelegate oldDelegate) {
    return true;
  }
}
