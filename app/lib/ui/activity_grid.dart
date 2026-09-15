import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/activity_calendar.dart';

const _monthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

const _weekdayNames = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];

/// «marzo». En minúscula, como se escribe en español fuera de un título.
String monthName(int month) => _monthNames[month - 1];

/// «jueves».
String weekdayName(DateTime day) => _weekdayNames[day.weekday - 1];

/// La cuadrícula de un mes, con un cuadrito por día coloreado según lo leído.
///
/// Vive aparte de la pantalla por la misma razón que el anillo de racha: es la
/// pieza con miga, y mezclada con el resto de Mi Viaje no se lee ni se prueba
/// bien.
class ActivityGrid extends StatelessWidget {
  const ActivityGrid({
    required this.month,
    required this.onSelect,
    this.today,
    this.selected,
    super.key,
  });

  final MonthActivity month;

  /// Medianoche del día de lectura en curso, si cae dentro de [month].
  final DateTime? today;

  final DateTime? selected;
  final ValueChanged<DayActivity> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Iniciales de lunes a domingo: la semana empieza en lunes, igual que
        // el `leadingBlanks` que calcula el dominio.
        Row(
          children: [
            for (final initial in const ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
              Expanded(
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ChromeTheme.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          // Sin scroll propio y ajustada a su contenido: la cuadrícula va
          // dentro del ListView de la pantalla, y dos scrolls anidados en el
          // mismo eje se pelean por el gesto.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < month.leadingBlanks; i++)
              const SizedBox.shrink(),
            for (final day in month.days)
              _DayCell(
                day: day,
                isToday: today == day.day,
                isSelected: selected == day.day,
                onTap: () => onSelect(day),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DayActivity day;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = colorForLevel(day.level);

    return Semantics(
      button: true,
      selected: isSelected,
      // La casilla se anuncia como una sola cosa y el número del día se excluye
      // del árbol: si no, el lector de pantalla lo leería dos veces, una suelto
      // y otra dentro de la frase.
      container: true,
      excludeSemantics: true,
      // El color por sí solo no comunica nada a quien usa lector de pantalla,
      // ni a quien no distingue estos ámbares del fondo.
      label: day.hasActivity
          ? '${day.day.day} de ${monthName(day.day.month)}, '
                '${day.read.inMinutes} minutos'
          : '${day.day.day} de ${monthName(day.day.month)}, sin lectura',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: switch ((isSelected, isToday)) {
              (true, _) => Border.all(color: ChromeTheme.textPrimary, width: 2),
              // Hoy se marca con un aro y no con otro color: el color ya está
              // diciendo cuánto se leyó, y darle un segundo significado lo
              // haría ilegible.
              (false, true) => Border.all(color: ChromeTheme.accentSoft, width: 1.5),
              _ => null,
            },
          ),
          alignment: Alignment.center,
          child: Text(
            '${day.day.day}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: day.level.goalMet ? FontWeight.w700 : FontWeight.w400,
              color: _inkFor(day.level),
            ),
          ),
        ),
      ),
    );
  }
}

/// La rampa de intensidad, del índigo del fondo al ámbar más claro.
///
/// Es una escala de luminancia creciente y no de tonos distintos: así se ordena
/// sola de un vistazo y sigue funcionando para quien no distingue bien los
/// colores, que vería igualmente una casilla más clara que otra.
Color colorForLevel(ActivityLevel level) => switch (level) {
  ActivityLevel.none => ChromeTheme.surfaceHigh,
  ActivityLevel.partial =>
    Color.lerp(ChromeTheme.surfaceHigh, ChromeTheme.accent, 0.35)!,
  ActivityLevel.met => ChromeTheme.accent,
  ActivityLevel.strong => ChromeTheme.accentSoft,
  ActivityLevel.intense => const Color(0xFFFFC49A),
};

/// Tinta del número del día: clara sobre las casillas apagadas, oscura sobre
/// las encendidas.
Color _inkFor(ActivityLevel level) => switch (level) {
  ActivityLevel.none => ChromeTheme.textMuted,
  ActivityLevel.partial => ChromeTheme.textPrimary,
  _ => const Color(0xFF2A1206),
};

/// La leyenda de la rampa: «menos ▪▪▪▪▪ más».
class ActivityLegend extends StatelessWidget {
  const ActivityLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 10, color: ChromeTheme.textMuted);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text('menos', style: style),
        const SizedBox(width: 6),
        for (final level in ActivityLevel.values) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: colorForLevel(level),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 3),
        ],
        const SizedBox(width: 3),
        const Text('más', style: style),
      ],
    );
  }
}
