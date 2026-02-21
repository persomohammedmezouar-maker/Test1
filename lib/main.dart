import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseFirestore.instance.enablePersistence();

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
  final MapController _mapController = MapController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedId;
  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 10),
    );

    final userLatLng = LatLng(pos.latitude, pos.longitude);

    setState(() {
      _userLocation = userLatLng;
    });

    _mapController.move(userLatLng, 15);
  }

  Future<int> _reserveNextNumber() async {
    final counterRef = _firestore.collection('meta').doc('counter');

    return _firestore.runTransaction<int>((tx) async {
      final snap = await tx.get(counterRef);
      final current = (snap.data()?['nidCounter'] as int?) ?? 0;
      final next = current + 1;

      tx.set(counterRef, {'nidCounter': next}, SetOptions(merge: true));
      return next;
    });
  }

  double? _distanceFromUser(LatLng pos) {
    if (_userLocation == null) return null;
    return const Distance()
        .as(LengthUnit.Kilometer, _userLocation!, pos);
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
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, __) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (_, __, ___) =>
              const Center(child: Icon(Icons.error)),
        ),
      ),
    );
  }

  LatLng _getCurrentMapCenter() {
    return _mapController.camera.center;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐓 Nids de Poule'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('nids')
            .orderBy('date', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          return Row(
            children: [
              Expanded(
                flex: 6,
                child: FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(50.8503, 4.3517),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=d123fd3281734f0f977e15eb84dba100',
                      maxZoom: 19,
                      userAgentPackageName: 'com.example.nidpoule',
                    ),
                    MarkerClusterLayerWidget(
                      options: MarkerClusterLayerOptions(
                        maxClusterRadius: 60,
                        size: const Size(50, 50),
                        markers: docs.map<Marker>((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final gp = data['pos'] as GeoPoint;
                          final pos =
                              LatLng(gp.latitude, gp.longitude);
                          final isSelected =
                              _selectedId == doc.id;

                          return Marker(
                            point: pos,
                            width: 60,
                            height: 60,
                            child: GestureDetector(
                              onTap: () =>
                                  _onNidSelected(pos, doc.id),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 300),
                                width: isSelected ? 56 : 44,
                                height: isSelected ? 56 : 44,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.green
                                      : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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
                    final data =
                        doc.data() as Map<String, dynamic>;
                    final gp = data['pos'] as GeoPoint;
                    final pos =
                        LatLng(gp.latitude, gp.longitude);
                    final distance =
                        _distanceFromUser(pos);

                    return ListTile(
                      leading: data['photoUrl'] != null
                          ? CachedNetworkImage(
                              imageUrl: data['photoUrl'],
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            )
                          : const Icon(Icons.location_on),
                      title: Text('Nid #${data['num']}'),
                      subtitle: distance != null
                          ? Text(
                              '${distance.toStringAsFixed(2)} km')
                          : null,
                      onTap: () {
                        _onNidSelected(pos, doc.id);
                        _showFullImage(data['photoUrl']);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final num = await _reserveNextNumber();

          final center =
              _userLocation ?? _mapController.camera.center;

          if (!mounted) return;

          showDialog(
            context: context,
            builder: (_) => AddNidDialog(
              pos: center,
              autoNum: num,
              onSuccess: () {},
            ),
          );
        },
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Nouveau Nid'),
        backgroundColor: Colors.green,
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
  final ImagePicker _picker = ImagePicker();

  Uint8List? _bytes;
  bool _loading = false;

  bool get _canSubmit =>
      !_loading &&
      _bytes != null &&
      _controller.text.trim().isNotEmpty;

  Future<void> _pickImage() async {
    final photoStatus = await Permission.photos.request();
    final cameraStatus = await Permission.camera.request();
    if (!photoStatus.isGranted || !cameraStatus.isGranted) return;

    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
    );

    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() => _bytes = bytes);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _loading = true);

    final fileName =
        'nids/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref =
        FirebaseStorage.instance.ref().child(fileName);

    await ref.putData(_bytes!);
    final photoUrl = await ref.getDownloadURL();

    await FirebaseFirestore.instance.collection('nids').add({
      'num': widget.autoNum,
      'nid': _controller.text.trim(),
      'photoUrl': photoUrl,
      'pos': GeoPoint(
          widget.pos.latitude, widget.pos.longitude),
      'date': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    widget.onSuccess();
    Navigator.pop(context);
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
            decoration:
                const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _bytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _bytes!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.add_a_photo),
                    ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(_loading ? 'Envoi...' : 'Publier'),
        ),
      ],
    );
  }
}
