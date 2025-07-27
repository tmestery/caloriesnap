import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:tflite/tflite.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

// Meal model
class Meal {
  final String id;
  final List<String> foodItems;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final DateTime timestamp;

  Meal({
    required this.id,
    required this.foodItems,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'foodItems': foodItems,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
        id: json['id'],
        foodItems: List<String>.from(json['foodItems']),
        calories: json['calories'],
        protein: json['protein'].toDouble(),
        carbs: json['carbs'].toDouble(),
        fat: json['fat'].toDouble(),
        timestamp: DateTime.parse(json['timestamp']),
      );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load TFLite model on Android, iOS, and macOS
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    await _loadTfLiteModel();
  }

  runApp(const CaloriScanApp());
}

Future<void> _loadTfLiteModel() async {
  try {
    String? result = await Tflite.loadModel(
      model: "assets/mobilenet_v1_0.25_128.tflite",
      labels: "assets/labels.txt",
    );
    debugPrint("Model loaded: $result");
  } catch (e) {
    debugPrint("Failed to load TFLite model: $e");
  }
}

class CaloriScanApp extends StatelessWidget {
  const CaloriScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CaloriScan',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static final List<Widget> _widgetOptions = <Widget>[
    const CameraScreen(),
    const HistoryScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CaloriScan')),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  XFile? _image;
  List<String> _foodItems = [];
  bool _isLoading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // Explicitly set source to camera for macOS, iOS, Android
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _image = pickedFile;
        _isLoading = true;
      });

      await _classifyImage(_image!);
      setState(() {
        _isLoading = false;
      });

      if (_foodItems.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResultsScreen(foodItems: _foodItems),
          ),
        );
      }
    }
  }

  Future<void> _classifyImage(XFile image) async {
    if (kIsWeb) {
      setState(() {
        _foodItems = [];
      });
    } else {
      var recognitions = await Tflite.runModelOnImage(
        path: image.path,
        numResults: 5,
        threshold: 0.5,
      );

      setState(() {
        _foodItems = recognitions?.map((rec) => rec['label'] as String).toList() ?? [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_image == null)
            const Text('No image selected.')
          else if (kIsWeb)
            FutureBuilder<Uint8List>(
              future: _image!.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                  return Image.memory(snapshot.data!, height: 200);
                } else {
                  return const CircularProgressIndicator();
                }
              },
            )
          else
            Image.file(File(_image!.path), height: 200),
          const SizedBox(height: 20),
          _isLoading
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed: _pickImage,
                  child: const Text('Take Photo'),
                ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    Tflite.close();
    super.dispose();
  }
}

class ResultsScreen extends StatefulWidget {
  final List<String> foodItems;

  const ResultsScreen({super.key, required this.foodItems});

  @override
  _ResultsScreenState createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  Meal? _meal;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNutritionData();
  }

  Future<void> _fetchNutritionData() async {
    final prompt = _buildPrompt(widget.foodItems);
    final response = await _queryOllama(prompt);

    final nutritionData = _parseOllamaResponse(response);

    final meal = Meal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      foodItems: widget.foodItems,
      calories: nutritionData['calories'] ?? 0,
      protein: nutritionData['protein']?.toDouble() ?? 0.0,
      carbs: nutritionData['carbs']?.toDouble() ?? 0.0,
      fat: nutritionData['fat']?.toDouble() ?? 0.0,
      timestamp: DateTime.now(),
    );

    await _saveMeal(meal);

    setState(() {
      _meal = meal;
      _isLoading = false;
    });
  }

  String _buildPrompt(List<String> foodItems) {
    final items = foodItems.join(", ");
    return "Estimate total calories, protein, carbs, and fat for a meal containing: $items. Format output clearly as JSON: {\"calories\": int, \"protein\": double, \"carbs\": double, \"fat\": double}";
  }

  Future<String> _queryOllama(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:11434/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "model": "llama3",
          "prompt": prompt,
          "stream": false,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body)['response'];
      } else {
        throw Exception("Failed to get response from Ollama");
      }
    } catch (e) {
      return '{"calories": 0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}';
    }
  }

  Map<String, dynamic> _parseOllamaResponse(String response) {
    try {
      return json.decode(response);
    } catch (e) {
      return {'calories': 0, 'protein': 0.0, 'carbs': 0.0, 'fat': 0.0};
    }
  }

  Future<void> _saveMeal(Meal meal) async {
    final prefs = await SharedPreferences.getInstance();
    final mealsJson = prefs.getString('meals') ?? '[]';
    final meals = json.decode(mealsJson) as List;
    meals.add(meal.toJson());
    await prefs.setString('meals', json.encode(meals));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nutrition Results')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _meal == null
              ? const Center(child: Text('No data available'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Foods: ${widget.foodItems.join(", ")}'),
                      Text('Calories: ${_meal!.calories} kcal'),
                      Text('Protein: ${_meal!.protein}g'),
                      Text('Carbs: ${_meal!.carbs}g'),
                      Text('Fat: ${_meal!.fat}g'),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: PieChart(
                          PieChartData(
                            sections: [
                              PieChartSectionData(
                                value: _meal!.protein,
                                title: 'Protein',
                                color: Colors.blue,
                              ),
                              PieChartSectionData(
                                value: _meal!.carbs,
                                title: 'Carbs',
                                color: Colors.green,
                              ),
                              PieChartSectionData(
                                value: _meal!.fat,
                                title: 'Fat',
                                color: Colors.red,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Meal> _meals = [];

  @override
  void initState() {
    super.initState();
    _loadMeals();
  }

  Future<void> _loadMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final mealsJson = prefs.getString('meals') ?? '[]';
    final mealsList = json.decode(mealsJson) as List;
    setState(() {
      _meals = mealsList.map((json) => Meal.fromJson(json)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meal History')),
      body: _meals.isEmpty
          ? const Center(child: Text('No meals logged yet.'))
          : ListView.builder(
              itemCount: _meals.length,
              itemBuilder: (context, index) {
                final meal = _meals[index];
                return ListTile(
                  title: Text(meal.foodItems.join(", ")),
                  subtitle: Text(
                      'Calories: ${meal.calories} kcal | ${meal.timestamp.toString()}'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ResultsScreen(foodItems: meal.foodItems),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}