import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const NidPouleApp());
}

class NidPouleApp extends StatelessWidget {
  const NidPouleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nid Poule Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
      ),
      home: const NidDashboardScreen(),
    );
  }
}

class NidDashboardScreen extends StatefulWidget {
  const NidDashboardScreen({super.key});

  @override
  State<NidDashboardScreen> createState() => _NidDashboardScreenState();
}

class _NidDashboardScreenState extends State<NidDashboardScreen> {
  final _mapController = MapController();
  final _firestore = FirebaseFirestore.instance;

  String? _selectedId;
  LatLng? _userLocation;
  Uint8List? _userLogoBytes;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadUserLogo();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _userLocation = LatLng(pos.latitude, pos.longitude);
    });

    _mapController.move(_userLocation!, 15);
  }

  Future<void> _loadUserLogo() async {
    _userLogoBytes = null; // Placeholder
  }

  Future<int> _reserveNextNumber() async {
    final counterRef = _firestore.collection('meta').doc('counter');
    return await _firestore.runTransaction<int>((tx) async {
      final snap = await tx.get(counterRef);
      final current = (snap.data()?['nidCounter'] as int?) ?? 0;
      final next = current + 1;
      tx.set(counterRef, {'nidCounter': next}, SetOptions(merge: true));
      return next;
    });
  }

  double? _distanceFromUser(LatLng pos) {
    if (_userLocation == null) return null;
    return const Distance().as(LengthUnit.Kilometer, _userLocation!, pos);
  }

  void _onNidSelected(LatLng pos, String id) {
    setState(() => _selectedId = id);
    _mapController.move(pos, 17);
  }

  void _showFullImage(String? url) {
    if (url == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  void _addNidButtonPressed() async {
    if (_userLocation == null) return;
    final num = await _reserveNextNumber();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AddNidDialog(
        pos: _userLocation!,
        autoNum: num,
        onSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Nid ajouté avec succès')),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐓 Nids de Poule'),
        centerTitle: true,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_road),
            tooltip: 'Ajouter Nid',
            onPressed: _addNidButtonPressed,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('nids')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          return Row(
            children: [
              Expanded(
                flex: 6,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(50.8503, 4.3517),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=d123fd3281734f0f977e15eb84dba100',
                      maxZoom: 19,
                    ),
                    if (_userLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _userLocation!,
                            width: 48,
                            height: 48,
                            builder: (_) => _userLogoBytes != null
                                ? Image.memory(_userLogoBytes!)
                                : const Icon(Icons.person_pin_circle, size: 48, color: Colors.blue),
                          ),
                        ],
                      ),
                    MarkerClusterLayerWidget(
                      options: MarkerClusterLayerOptions(
                        maxClusterRadius: 50,
                        size: const Size(50, 50),
                        markers: docs.map<Marker>((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final gp = data['pos'] as GeoPoint;
                          final pos = LatLng(gp.latitude, gp.longitude);
                          final isSelected = _selectedId == doc.id;

                          return Marker(
                            point: pos,
                            width: 60,
                            height: 60,
                            builder: (_) => GestureDetector(
                              onTap: () => _onNidSelected(pos, doc.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: isSelected ? 56 : 44,
                                height: isSelected ? 56 : 44,
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.4),
                                      blurRadius: 10,
                                    )
                                  ],
                                ),
                                child: const Icon(Icons.location_on, color: Colors.white),
                              ),
                            ),
                          );
                        }).toList(),
                        builder: (context, markers) => Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.7),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${markers.length}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final gp = data['pos'] as GeoPoint;
                    final pos = LatLng(gp.latitude, gp.longitude);
                    final distance = _distanceFromUser(pos);
                    final isSelected = _selectedId == doc.id;

                    return Dismissible(
                      key: Key(doc.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) async {
                        await _firestore.collection('nids').doc(doc.id).delete();
                        if (mounted) setState(() => _selectedId = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🗑 Nid supprimé')),
                        );
                      },
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: ListTile(
                        tileColor: isSelected ? Colors.green.withOpacity(0.15) : null,
                        title: Text('Nid #${data['num']}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['nid'] ?? ''),
                            if (distance != null)
                              Text('${distance.toStringAsFixed(2)} km',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        onTap: () {
                          _onNidSelected(pos, doc.id);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Petit AddNidDialog de test
class AddNidDialog extends StatelessWidget {
  final LatLng pos;
  final int autoNum;
  final VoidCallback onSuccess;

  const AddNidDialog({super.key, required this.pos, required this.autoNum, required this.onSuccess});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter Nid'),
      content: Text('Position: ${pos.latitude}, ${pos.longitude}\nNuméro: $autoNum'),
      actions: [
        TextButton(
          onPressed: () {
            onSuccess();
            Navigator.of(context).pop();
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
