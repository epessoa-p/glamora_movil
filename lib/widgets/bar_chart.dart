import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Una serie de la leyenda (p. ej. «Semana actual»).
class ChartSeries {
  const ChartSeries(this.label, this.color);

  final String label;
  final Color color;
}

/// Un grupo de barras con su etiqueta; un valor por serie.
class ChartGroup {
  const ChartGroup(this.label, this.values);

  final String label;
  final List<double> values;
}

/// Número corto para el eje: 6700 → 6.7k.
String compactNumber(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Gráfico de barras verticales, simples o agrupadas, en una tarjeta.
class BarChartCard extends StatelessWidget {
  const BarChartCard({super.key, required this.title, required this.series, required this.groups, required this.format, this.height = 170});

  final String title;
  final List<ChartSeries> series;
  final List<ChartGroup> groups;

  /// Texto completo de un valor, para la ayuda al mantener presionada la barra.
  final String Function(double) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // Las devoluciones pueden dejar un día en negativo: el gráfico parte de 0.
    final top = groups.expand((g) => g.values).fold<double>(0, math.max);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          if (series.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 4, children: [
              for (final s in series)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 5),
                  Text(s.label, style: const TextStyle(fontSize: 12)),
                ]),
            ]),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            child: top <= 0
                ? Center(child: Text('Sin datos en este período', style: TextStyle(color: muted)))
                : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Eje: cuatro marcas, de arriba hacia abajo.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (var i = 4; i >= 1; i--) Text(compactNumber(top * i / 4), style: TextStyle(color: muted, fontSize: 10)),
                        const SizedBox.shrink(),
                      ]),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final g in groups)
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(
                                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  for (final (i, v) in g.values.indexed)
                                    Expanded(
                                      child: _Bar(
                                        factor: v <= 0 ? 0 : math.max(v / top, .012),
                                        color: series[i].color,
                                        tooltip: '${g.label} · ${series[i].label.isEmpty ? '' : '${series[i].label}: '}${format(v)}',
                                      ),
                                    ),
                                ]),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 16,
                                child: FittedBox(fit: BoxFit.scaleDown, child: Text(g.label, maxLines: 1, style: TextStyle(color: muted, fontSize: 11))),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.factor, required this.color, required this.tooltip});

  final double factor;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: factor,
          child: Tooltip(
            message: tooltip,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 20),
              child: Container(decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lista de barras horizontales: nombre, valor y proporción respecto al mayor.
class RankingCard extends StatelessWidget {
  const RankingCard({super.key, required this.title, required this.rows, required this.color, this.subtitle});

  final String title;
  final String? subtitle;

  /// Nombre, valor numérico y texto a mostrar; ya vienen ordenadas.
  final List<(String, double, String)> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final top = rows.map((r) => r.$2).fold<double>(0, math.max);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          if (subtitle != null) Text(subtitle!, style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 10),
          if (rows.isEmpty) Text('Sin datos en este período', style: TextStyle(color: muted)),
          for (final (name, value, text) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: top <= 0 ? 0 : (value / top).clamp(0.0, 1.0), minHeight: 7, color: color, backgroundColor: color.withValues(alpha: .12)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
