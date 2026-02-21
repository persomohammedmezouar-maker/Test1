import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
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

  @override
  void initState() {
    super.initState();
    _initLocation();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐓 Nids de Poule'),
        centerTitle: true,
        elevation: 2,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('nids').orderBy('date', descending: true).limit(100).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Erreur de connexion'));
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
                    onLongPress: (tapPosition, point) async {
                      final num = await _reserveNextNumber();
                      if (!mounted) return;

                      showDialog(
                        context: context,
                        builder: (_) => AddNidDialog(
                          pos: point,
                          autoNum: num,
                          onSuccess: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Nid ajouté avec succès')),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=d123fd3281734f0f977e15eb84dba100',
                      maxZoom: 19,
                    ),
                    MarkerLayer(
                      markers: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final gp = data['pos'] as GeoPoint;
                        final pos = LatLng(gp.latitude, gp.longitude);
                        final isSelected = _selectedId == doc.id;

                        return Marker(
                          point: pos,
                          width: 60,
                          height: 60,
                          child: GestureDetector(
                            onTap: () => _onNidSelected(pos, doc.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: isSelected ? 56 : 44,
                              height: isSelected ? 56 : 44,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.green : Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10)],
                              ),
                              child: const Icon(Icons.location_on, color: Colors.white),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.red.withOpacity(0.1),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.red),
                          const SizedBox(width: 8),
                          Text('Total : ${docs.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final gp = data['pos'] as GeoPoint;
                          final pos = LatLng(gp.latitude, gp.longitude);
                          final distance = _distanceFromUser(pos);
                          final isSelected = _selectedId == doc.id;

                          return GestureDetector(
                            onTap: () {
                              _onNidSelected(pos, doc.id);
                              _showFullImage(data['photoUrl']);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.green.withOpacity(0.15) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Nid #${data['num']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(data['nid'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if (distance != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text('${distance.toStringAsFixed(2)} km',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AddNidDialog extends StatefulWidget {
  final LatLng pos;
  final int autoNum;
  final VoidCallback onSuccess;

  const AddNidDialog({
    super.key,
    required this.pos,
    required this.autoNum,
    required this.onSuccess,
  });

  @override
  State<AddNidDialog> createState() => _AddNidDialogState();
}

class _AddNidDialogState extends State<AddNidDialog> {
  final _controller = TextEditingController();
  Uint8List? _bytes;
  bool _loading = false;

  bool get _canSubmit => !_loading && _bytes != null && _controller.text.trim().isNotEmpty;

  Future<void> _pickImage() async {
    // 1️⃣ Demande runtime permission
    if (Platform.isAndroid) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        final storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('❌ Permission images refusée')));
          }
          return;
        }
      }
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() => _bytes = result.files.single.bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur photo: $e')));
      }
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _loading = true);

    try {
      final fileName = 'nids/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child(fileName);
      await ref.putData(_bytes!);
      final photoUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('nids').add({
        'num': widget.autoNum,
        'nid': _controller.text.trim(),
        'photoUrl': photoUrl,
        'pos': GeoPoint(widget.pos.latitude, widget.pos.longitude),
        'date': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      widget.onSuccess();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur upload: $e')));
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nid #${widget.autoNum}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo),
            label: const Text('Ajouter photo'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(_loading ? 'Envoi...' : 'Publier'),
        )
      ],
    );
  }
}