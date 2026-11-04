import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (_) => TrackerProvider(prefs),
      child: const TimeTrackerApp(),
    ),
  );
}

// ---------------- MODELOS ----------------
class TaskEntry {
  final String id;
  final String title;
  final String category;
  final DateTime startTime;
  final DateTime endTime;

  TaskEntry({
    required this.id,
    required this.title,
    required this.category,
    required this.startTime,
    required this.endTime,
  });

  Duration get duration => endTime.difference(startTime);

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'category': category,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
  };

  factory TaskEntry.fromMap(Map<String, dynamic> map) => TaskEntry(
    id: map['id'],
    title: map['title'],
    category: map['category'],
    startTime: DateTime.parse(map['startTime']),
    endTime: DateTime.parse(map['endTime']),
  );
}

// ---------------- GESTIÓN DE ESTADO ----------------
class TrackerProvider with ChangeNotifier {
  final SharedPreferences prefs;
  List<TaskEntry> _entries = [];
  
  // Cronómetro
  Timer? _timer;
  int _secondsElapsed = 0;
  bool _isRunning = false;
  String _currentTask = '';
  String _currentCategory = 'Trabajo';
  DateTime? _timerStartTime;

  TrackerProvider(this.prefs) {
    _loadEntries();
  }

  List<TaskEntry> get entries => _entries;
  bool get isRunning => _isRunning;
  int get secondsElapsed => _secondsElapsed;
  String get currentCategory => _currentCategory;
  final List<String> categories = ['Trabajo', 'Estudio', 'Deporte', 'Ocio', 'Descanso'];

  void setCategory(String cat) {
    _currentCategory = cat;
    notifyListeners();
  }

  void startTimer(String taskName) {
    _currentTask = taskName.isEmpty ? 'Actividad sin nombre' : taskName;
    _secondsElapsed = 0;
    _isRunning = true;
    _timerStartTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsElapsed++;
      notifyListeners();
    });
    notifyListeners();
  }

  void stopTimer() {
    if (!_isRunning) return;
    _timer?.cancel();
    final endTime = DateTime.now();
    addEntry(TaskEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _currentTask,
      category: _currentCategory,
      startTime: _timerStartTime ?? endTime.subtract(Duration(seconds: _secondsElapsed)),
      endTime: endTime,
    ));
    _isRunning = false;
    _secondsElapsed = 0;
    notifyListeners();
  }

  void addEntry(TaskEntry entry) {
    _entries.insert(0, entry);
    _saveEntries();
    notifyListeners();
  }

  void _loadEntries() {
    final data = prefs.getString('entries');
    if (data != null) {
      final List decoded = jsonDecode(data);
      _entries = decoded.map((e) => TaskEntry.fromMap(e)).toList();
      notifyListeners();
    }
  }

  void _saveEntries() {
    final data = jsonEncode(_entries.map((e) => e.toMap()).toList());
    prefs.setString('entries', data);
  }

  // Filtrado de reportes
  List<TaskEntry> getFilteredEntries(String period) {
    final now = DateTime.now();
    return _entries.where((entry) {
      if (period == 'Día') {
        return entry.startTime.year == now.year &&
               entry.startTime.month == now.month &&
               entry.startTime.day == now.day;
      } else if (period == 'Semana') {
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return entry.startTime.isAfter(startOfWeek.subtract(const Duration(days: 1)));
      } else { // Mes
        return entry.startTime.year == now.year && entry.startTime.month == now.month;
      }
    }).toList();
  }
}

// ---------------- INTERFAZ PRINCIPAL ----------------
class TimeTrackerApp extends StatelessWidget {
  const TimeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Manager Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const TimerScreen(),
    const ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer), label: 'Cronómetro'),
          NavigationDestination(icon: Icon(Icons.pie_chart), label: 'Informes'),
        ],
      ),
    );
  }
}

// ---------------- PANTALLA CRONÓMETRO Y REGISTRO ----------------
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final TextEditingController _taskController = TextEditingController();

  String _formatDuration(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _showManualEntryDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String title = '';
    String category = 'Trabajo';
    int minutes = 30;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registro Manual'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Tarea'),
                onSaved: (val) => title = val ?? 'Tarea Manual',
              ),
              DropdownButtonFormField<String>(
                value: category,
                items: context.read<TrackerProvider>().categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => category = val!,
                decoration: const InputDecoration(labelText: 'Categoría'),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Duración (minutos)'),
                keyboardType: TextInputType.number,
                initialValue: '30',
                onSaved: (val) => minutes = int.tryParse(val ?? '30') ?? 30,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              formKey.currentState?.save();
              final now = DateTime.now();
              context.read<TrackerProvider>().addEntry(TaskEntry(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: title,
                category: category,
                startTime: now.subtract(Duration(minutes: minutes)),
                endTime: now,
              ));
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TrackerProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Registro de Tiempo')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Añadir registro manual',
        onPressed: () => _showManualEntryDialog(context),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Text(
                      _formatDuration(tracker.secondsElapsed),
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _taskController,
                      enabled: !tracker.isRunning,
                      decoration: const InputDecoration(
                        hintText: '¿En qué estás trabajando?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: tracker.currentCategory,
                      onChanged: tracker.isRunning ? null : (c) => tracker.setCategory(c!),
                      items: tracker.categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tracker.isRunning ? Colors.red : Colors.indigo,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: () {
                        if (tracker.isRunning) {
                          tracker.stopTimer();
                          _taskController.clear();
                        } else {
                          tracker.startTimer(_taskController.text);
                        }
                      },
                      icon: Icon(tracker.isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(tracker.isRunning ? 'DETENER' : 'INICIAR'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Registros Recientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: tracker.entries.length,
                itemBuilder: (ctx, i) {
                  final item = tracker.entries[i];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.access_time)),
                    title: Text(item.title),
                    subtitle: Text('${item.category} • ${DateFormat('dd/MM HH:mm').format(item.startTime)}'),
                    trailing: Text(
                      '${item.duration.inMinutes}m',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- PANTALLA INFORMES Y GRÁFICOS ----------------
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedPeriod = 'Día';
  final Map<String, Color> _categoryColors = {
    'Trabajo': Colors.blue,
    'Estudio': Colors.green,
    'Deporte': Colors.orange,
    'Ocio': Colors.purple,
    'Descanso': Colors.teal,
  };

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TrackerProvider>();
    final filtered = tracker.getFilteredEntries(_selectedPeriod);

    // Calcular distribución por categoría
    Map<String, double> categoryDurations = {};
    for (var entry in filtered) {
      categoryDurations[entry.category] =
          (categoryDurations[entry.category] ?? 0.0) + entry.duration.inMinutes.toDouble();
    }

    double totalMinutes = categoryDurations.values.fold(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: const Text('Informes y Gráficos')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Día', label: Text('Día')),
                ButtonSegment(value: 'Semana', label: Text('Semana')),
                ButtonSegment(value: 'Mes', label: Text('Mes')),
              ],
              selected: {_selectedPeriod},
              onSelectionChanged: (val) => setState(() => _selectedPeriod = val.first),
            ),
            const SizedBox(height: 24),
            Text(
              'Tiempo Total: ${(totalMinutes / 60).toStringAsFixed(1)} horas',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: categoryDurations.isEmpty
                  ? const Center(child: Text('No hay datos en este periodo'))
                  : Column(
                      children: [
                        Expanded(
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: categoryDurations.entries.map((entry) {
                                final percentage = (entry.value / totalMinutes) * 100;
                                return PieChartSectionData(
                                  value: entry.value,
                                  title: '${percentage.toStringAsFixed(0)}%',
                                  color: _categoryColors[entry.category] ?? Colors.grey,
                                  radius: 60,
                                  titleStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: categoryDurations.entries.map((e) {
                              return ListTile(
                                leading: CircleAvatar(backgroundColor: _categoryColors[e.key] ?? Colors.grey),
                                title: Text(e.key),
                                trailing: Text('${e.value.toInt()} min'),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
