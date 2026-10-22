/// One v2 line icon: stroked path data (24 grid) + optional filled parts
/// (AI spark, record dot, filled star…).
class MgIconData {
  final List<String> stroke;
  final List<String> fill;
  const MgIconData(this.stroke, {this.fill = const []});
}
