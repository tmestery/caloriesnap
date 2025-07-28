import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io' show Platform, File;
import 'package:flutter/foundation.dart';

// Meal model
class Meal {
  final String id;
  final List<String> foodItems;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double sodium;
  final DateTime timestamp;

  Meal({
    required this.id,
    required this.foodItems,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.sugar,
    required this.sodium,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'foodItems': foodItems,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'sugar': sugar,
        'sodium': sodium,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
        id: json['id'],
        foodItems: List<String>.from(json['foodItems']),
        calories: json['calories'],
        protein: json['protein'].toDouble(),
        carbs: json['carbs'].toDouble(),
        fat: json['fat'].toDouble(),
        fiber: json['fiber'].toDouble(),
        sugar: json['sugar'].toDouble(),
        sodium: json['sodium'].toDouble(),
        timestamp: DateTime.parse(json['timestamp']),
      );
}

void main() {
  runApp(const CaloriScanApp());
}

class CaloriScanApp extends StatelessWidget {
  const CaloriScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CaloriScan',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blue,
          accentColor: Colors.blueAccent,
          backgroundColor: Colors.white,
        ).copyWith(secondary: Colors.blueAccent),
        scaffoldBackgroundColor: Colors.white,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color.fromARGB(255, 69, 90, 100)),
          titleLarge: TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontWeight: FontWeight.bold),
        ),
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
    const DailySummaryScreen(),
  ];

  void _onItemTapped(int index) {
    debugPrint('Tapped index: $index');
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CaloriScan'),
        backgroundColor: Color.fromARGB(255, 69, 90, 100),
        elevation: 4,
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Summary'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.blueGrey[400],
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(),
        elevation: 8,
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
  final TextEditingController _descriptionController = TextEditingController();
  List<String> _foodItems = [];
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      XFile? pickedFile;
      if (!kIsWeb && Platform.isIOS) {
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        if (!iosInfo.isPhysicalDevice) {
          pickedFile = await picker.pickImage(source: ImageSource.gallery);
        } else {
          pickedFile = await picker.pickImage(source: ImageSource.camera);
        }
      } else {
        pickedFile = await picker.pickImage(source: ImageSource.camera);
      }

      if (pickedFile != null) {
        setState(() {
          _image = pickedFile;
          _isLoading = true;
          _errorMessage = null;
        });

        _getFoodItemsFromDescription();
      } else {
        setState(() {
          _errorMessage = 'No image selected.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error accessing camera or gallery: $e';
      });
      debugPrint('Image picker error: $e');
    }
  }

  Future<void> _getFoodItemsFromDescription() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Describe the Image'),
        content: TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(hintText: 'e.g., burger and fries on a plate'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _processDescription();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _processDescription() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() {
        _errorMessage = 'Please provide a description.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('Processing description: $description');
      final prompt = "Based on this description: '$description', identify possible food items. Return a comma-separated list of food items (e.g., cheeseburger, fries).";
      final response = await _queryOllama(prompt).timeout(const Duration(seconds: 10));
      debugPrint('Ollama response: $response');
      final foodItems = response.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      if (foodItems.isNotEmpty) {
        setState(() {
          _foodItems = foodItems;
        });
        debugPrint('Navigating with food items: $_foodItems');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResultsScreen(foodItems: _foodItems),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'No food items identified.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error processing description: $e';
      });
      debugPrint('Ollama error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String> _queryOllama(String prompt) async {
    try {
      debugPrint('Querying Ollama at: http://127.0.0.1:11434/api/generate');
      final response = await http.post(
        Uri.parse('http://127.0.0.1:11434/api/generate'),
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
        throw Exception("Failed to get response from Ollama: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('Ollama error: $e');
      return 'No items identified';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (_image == null)
            const Text('No image selected.', style: TextStyle(color: Color.fromARGB(255, 69, 90, 100)))
          else
            Image.file(File(_image!.path), height: 200),
          const SizedBox(height: 20),
          _isLoading
              ? const CircularProgressIndicator(color: Colors.blueAccent)
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: _pickImage,
                  child: const Text('Take Photo', style: TextStyle(color: Colors.white)),
                ),
        ],
      ),
    );
  }
}

// ... (keep existing imports and Meal class unchanged)

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
    debugPrint('Fetching nutrition for: ${widget.foodItems}');
    final prompt = _buildPrompt(widget.foodItems);
    final response = await _queryOllama(prompt).timeout(const Duration(seconds: 10));
    debugPrint('Nutrition response: $response');

    final nutritionData = _parseOllamaResponse(response);

    // Ensure valid numeric values
    final calories = nutritionData['calories'] is int ? nutritionData['calories'] : 0;
    final protein = nutritionData['protein'] is num ? nutritionData['protein'].toDouble() : 0.0;
    final carbs = nutritionData['carbs'] is num ? nutritionData['carbs'].toDouble() : 0.0;
    final fat = nutritionData['fat'] is num ? nutritionData['fat'].toDouble() : 0.0;
    final fiber = nutritionData['fiber'] is num ? nutritionData['fiber'].toDouble() : 0.0;
    final sugar = nutritionData['sugar'] is num ? nutritionData['sugar'].toDouble() : 0.0;
    final sodium = nutritionData['sodium'] is num ? nutritionData['sodium'].toDouble() : 0.0;

    final meal = Meal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      foodItems: widget.foodItems,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fiber,
      sugar: sugar,
      sodium: sodium,
      timestamp: DateTime.now(),
    );

    await _saveMeal(meal);
    debugPrint('Saved meal: ${meal.foodItems}, Calories: ${meal.calories}');

    setState(() {
      _meal = meal;
      _isLoading = false;
    });
  }

  String _buildPrompt(List<String> foodItems) {
    final items = foodItems.join(", ");
    return "Estimate total calories, protein, carbs, fat, fiber, sugar, and sodium for a meal containing: $items. Return ONLY a JSON object with the following structure: {\"calories\": int, \"protein\": double, \"carbs\": double, \"fat\": double, \"fiber\": double, \"sugar\": double, \"sodium\": double}. Do not include any additional text or explanations.";
  }

  Future<String> _queryOllama(String prompt) async {
    try {
      debugPrint('Querying Ollama at: http://127.0.0.1:11434/api/generate');
      final response = await http.post(
        Uri.parse('http://127.0.0.1:11434/api/generate'),
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
        throw Exception("Failed to get response from Ollama: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('Ollama error: $e');
      return '{"calories": 0, "protein": 0.0, "carbs": 0.0, "fat": 0.0, "fiber": 0.0, "sugar": 0.0, "sodium": 0.0}';
    }
  }

  Map<String, dynamic> _parseOllamaResponse(String response) {
    try {
      return json.decode(response) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Parse error: $e');
      return {'calories': 0, 'protein': 0.0, 'carbs': 0.0, 'fat': 0.0, 'fiber': 0.0, 'sugar': 0.0, 'sodium': 0.0};
    }
  }

  Future<void> _saveMeal(Meal meal) async {
    final prefs = await SharedPreferences.getInstance();
    final mealsJson = prefs.getString('meals') ?? '[]';
    final meals = json.decode(mealsJson) as List;
    meals.add(meal.toJson());
    await prefs.setString('meals', json.encode(meals));
    debugPrint('Meal saved to SharedPreferences: ${meal.toJson()}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition Results'),
        backgroundColor: Color.fromARGB(255, 69, 90, 100),
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : _meal == null
              ? const Center(child: Text('No data available', style: TextStyle(color: Color.fromARGB(255, 69, 90, 100))))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Foods: ${widget.foodItems.join(", ")}',
                          style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 18)),
                      const SizedBox(height: 10),
                      Text('Calories: ${_meal!.calories} cals',
                          style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 16)),
                      Text('Protein: ${_meal!.protein}g',
                          style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 16)),
                      Text('Carbs: ${_meal!.carbs}g',
                          style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 16)),
                      Text('Fat: ${_meal!.fat}g',
                          style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 16)),
                      Text('Fiber: ${_meal!.fiber}g',
                          style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 16)),
                      Text('Sugar: ${_meal!.sugar}g',
                          style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 16)),
                      Text('Sodium: ${_meal!.sodium}mg',
                          style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 16)),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: PieChart(
                          PieChartData(
                            sections: [
                              PieChartSectionData(
                                value: _meal!.protein > 0 ? _meal!.protein : 1.0,
                                title: 'Protein',
                                color: Colors.blue[200],
                                titleStyle: const TextStyle(color: Colors.black),
                              ),
                              PieChartSectionData(
                                value: _meal!.carbs > 0 ? _meal!.carbs : 1.0,
                                title: 'Carbs',
                                color: Colors.blue[300],
                                titleStyle: const TextStyle(color: Colors.black),
                              ),
                              PieChartSectionData(
                                value: _meal!.fat > 0 ? _meal!.fat : 1.0,
                                title: 'Fat',
                                color: Colors.blue[400],
                                titleStyle: const TextStyle(color: Colors.black),
                              ),
                            ],
                            borderData: FlBorderData(show: false),
                            centerSpaceRadius: 40,
                            sectionsSpace: 2,
                            centerSpaceColor: Color.fromARGB(255, 69, 90, 100),
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
    debugPrint('HistoryScreen initialized, loading meals');
  }

  Future<void> _loadMeals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mealsJson = prefs.getString('meals') ?? '[]';
      debugPrint('Raw mealsJson: $mealsJson');
      final mealsList = json.decode(mealsJson) as List;
      debugPrint('Decoded mealsList length: ${mealsList.length}');
      setState(() {
        _meals = mealsList.map((json) => Meal.fromJson(json)).toList();
        debugPrint('Loaded meals count: ${_meals.length}, Meals: ${_meals.map((m) => m.foodItems).toList()}');
      });
    } catch (e) {
      debugPrint('Error loading meals: $e, Stack trace: ${StackTrace.current}');
      setState(() {
        _meals = [];
        debugPrint('Set meals to empty due to error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meal History'), backgroundColor: Color.fromARGB(255, 69, 90, 100), elevation: 4),
      body: Container(
        color: Colors.white,
        child: _meals.isEmpty
            ? const Center(child: Text('No meals logged yet.', style: TextStyle(color: Color.fromARGB(255, 69, 90, 100))))
            : ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: _meals.length,
                itemBuilder: (context, index) {
                  final meal = _meals[index];
                  return Card(
                    color: Colors.blue[50],
                    elevation: 4,
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12.0),
                      title: Text(
                        meal.foodItems.join(", "),
                        style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100)),
                      ),
                      subtitle: Text(
                        'Calories: ${meal.calories} cals',
                        style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100)),
                      ),
                      onTap: () {
                        debugPrint('Tapped meal: ${meal.foodItems}');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ResultsScreen(foodItems: meal.foodItems),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class DailySummaryScreen extends StatefulWidget {
  const DailySummaryScreen({super.key});

  @override
  _DailySummaryScreenState createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  List<Meal> _meals = [];
  double _totalCalories = 0.0;
  double _totalProtein = 0.0;
  double _totalCarbs = 0.0;
  double _totalFat = 0.0;

  @override
  void initState() {
    super.initState();
    _loadMeals();
    debugPrint('DailySummaryScreen initialized, loading meals');
  }

  Future<void> _loadMeals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mealsJson = prefs.getString('meals') ?? '[]';
      debugPrint('Raw mealsJson for summary: $mealsJson');
      final mealsList = json.decode(mealsJson) as List;
      debugPrint('Decoded mealsList length for summary: ${mealsList.length}');
      setState(() {
        _meals = mealsList.map((json) => Meal.fromJson(json)).toList();
        final now = DateTime.now();
        final todayMeals = _meals.where((meal) => meal.timestamp.day == now.day && meal.timestamp.month == now.month && meal.timestamp.year == now.year).toList();
        _totalCalories = todayMeals.map((m) => m.calories.toDouble()).reduce((a, b) => a + b);
        _totalProtein = todayMeals.map((m) => m.protein).reduce((a, b) => a + b);
        _totalCarbs = todayMeals.map((m) => m.carbs).reduce((a, b) => a + b);
        _totalFat = todayMeals.map((m) => m.fat).reduce((a, b) => a + b);
        debugPrint('Today\'s totals - Calories: $_totalCalories, Protein: $_totalProtein, Carbs: $_totalCarbs, Fat: $_totalFat');
      });
    } catch (e) {
      debugPrint('Error loading meals for summary: $e, Stack trace: ${StackTrace.current}');
      setState(() {
        _meals = [];
        _totalCalories = 0.0;
        _totalProtein = 0.0;
        _totalCarbs = 0.0;
        _totalFat = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Summary'), backgroundColor: Color.fromARGB(255, 69, 90, 100), elevation: 4),
      body: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16.0),
        child: _meals.isEmpty
            ? const Center(child: Text('No meals logged yet.', style: TextStyle(color: Color.fromARGB(255, 69, 90, 100))))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Calories: ${_totalCalories.toStringAsFixed(1)} cals',
                      style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 18)),
                  const SizedBox(height: 10),
                  Text('Total Protein: ${_totalProtein.toStringAsFixed(1)}g',
                      style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 18)),
                  Text('Total Carbs: ${_totalCarbs.toStringAsFixed(1)}g',
                      style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 18)),
                  Text('Total Fat: ${_totalFat.toStringAsFixed(1)}g',
                      style: const TextStyle(color: Color.fromARGB(255, 69, 90, 100), fontSize: 18)),
                ],
              ),
      ),
    );
  }
}