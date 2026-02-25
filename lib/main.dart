import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';

void main() {
  runApp(NidPouleApp());
}

class NidPouleApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nid Poule App',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        brightness: Brightness.light,
      ),
      home: NidDashboardScreen(),
    );
  }
}

class NidDashboardScreen extends StatefulWidget {
  @override
  _NidDashboardScreenState createState() => _NidDashboardScreenState();
}

class _NidDashboardScreenState extends State<NidDashboardScreen> {
  final MapController _mapController = MapController();
  final ValueNotifier<List<Marker>> _markersNotifier = ValueNotifier([]);
  LatLng _currentCenter = LatLng(48.8566, 2.3522);
  Uint8List? _userLogoBytes;

  @override
  void initState() {
    super.initState();
    _loadNidsFromFirestore();
  }

  // ----- Charger Firestore -----
  Future<void> _loadNidsFromFirestore() async {
    final snapshot = await FirebaseFirestore.instance.collection('nids').get();
    final loadedMarkers = snapshot.docs.map((doc) {
      final data = doc.data();
      return Marker(
        point: LatLng(data['lat'], data['lng']),
        width: 80,
        height: 80,
        child: Icon(Icons.warning, color: Colors.red),
      );
    }).toList();
    _markersNotifier.value = loadedMarkers;
  }

  // ----- Ajouter marker -----
  void _addMarker(LatLng pos) {
    final marker = Marker(
      point: pos,
      width: 80,
      height: 80,
      child: GestureDetector(
        onTap: () => _showMarkerInfo(pos),
        child: _userLogoBytes != null
            ? Image.memory(_userLogoBytes!)
            : Icon(Icons.location_on, size: 40, color: Colors.red),
      ),
    );
    _markersNotifier.value = [..._markersNotifier.value, marker];
  }

  // ----- Popup info -----
  void _showMarkerInfo(LatLng pos) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Info Nid'),
        content: Text('Position: ${pos.latitude}, ${pos.longitude}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Fermer')),
          TextButton(
              onPressed: () {
                _markersNotifier.value =
                    _markersNotifier.value.where((m) => m.point != pos).toList();
                Navigator.pop(context);
              },
              child: Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // ----- Choisir image ou photo -----
  Future<void> _pickImage({bool fromCamera = false}) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 70);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _userLogoBytes = bytes;
      });
    }
  }

  // ----- Géolocalisation -----
  Future<void> _centerOnUser() async {
    final pos = await Geolocator.getCurrentPosition();
    final latLng = LatLng(pos.latitude, pos.longitude);
    _mapController.move(latLng, 15.0);
    _addMarker(latLng);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard Nid Poule'),
        actions: [
          IconButton(
            tooltip: 'Galerie',
            icon: Icon(Icons.photo),
            onPressed: () => _pickImage(fromCamera: false),
          ),
          IconButton(
            tooltip: 'Appareil photo',
            icon: Icon(Icons.camera_alt),
            onPressed: () => _pickImage(fromCamera: true),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentCenter,
          initialZoom: 13,
          onTap: (tapPos, latlng) {
            if (latlng != null) _addMarker(latlng);
          },
          onPositionChanged: (position, _) {
            _currentCenter = position.center!;
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.nid_poule_app',
          ),
          ValueListenableBuilder<List<Marker>>(
            valueListenable: _markersNotifier,
            builder: (_, markers, __) {
              return MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 120,
                  size: Size(50, 50),
                  markers: markers,
                  builder: (context, markers) {
                    return Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${markers.length}',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'user_location',
            tooltip: 'Ma position',
            onPressed: _centerOnUser,
            child: Icon(Icons.my_location),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'add_center',
            tooltip: 'Ajouter au centre',
            onPressed: () => _addMarker(_currentCenter),
            child: Icon(Icons.add_location),
          ),
        ],
      ),
    );
  }
}